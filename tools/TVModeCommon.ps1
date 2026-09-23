<#
  Shared functions for the "Read Marvel Comics Upscaled - 4K TV Mode"
  launcher. Dot-sourced by both Start-ComicMode-TV.ps1 (the main
  orchestrator) and Watch-BrowserFullscreen.ps1 (the background watcher),
  so window/monitor/browser logic only exists in one place.
#>

Add-Type -Path (Join-Path $PSScriptRoot 'TVModeCommon.cs') -ErrorAction Stop
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms

function Get-DefaultBrowserExe {
    <# Resolves Windows' actual default browser for https links - not
       hardcoded to Firefox, so this keeps working if that ever changes. #>
    $progId = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice' -ErrorAction SilentlyContinue).ProgId
    if (-not $progId) { throw "Could not determine default browser (no UserChoice ProgId set for https)." }
    $cmd = (Get-ItemProperty "Registry::HKEY_CLASSES_ROOT\$progId\shell\open\command" -ErrorAction SilentlyContinue).'(default)'
    if (-not $cmd) { throw "Default browser ProgId '$progId' has no open command registered." }
    # Command is like: "C:\Path\To\browser.exe" -osint -url "%1"  - pull out
    # just the quoted (or bare) executable path at the front.
    if ($cmd -match '^\s*"([^"]+)"') { return $Matches[1] }
    if ($cmd -match '^\s*(\S+)') { return $Matches[1] }
    throw "Could not parse executable path out of default browser command: $cmd"
}

function Get-BrowserProcesses {
    param([Parameter(Mandatory)][string]$ExePath)
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($ExePath)
    Get-Process -Name $baseName -ErrorAction SilentlyContinue
}

function Get-VirtualDisplayMonitor {
    <# The 4K virtual display, identified by its known resolution and by
       NOT being the primary (laptop) panel - matches Sunshine's own
       confirmed "Capture size 3840x2160 / Offset 1920x0" log output. #>
    $monitors = [TVMode]::GetMonitors()
    $match = $monitors | Where-Object { -not $_.Primary -and $_.Width -eq 3840 -and $_.Height -eq 2160 }
    if (-not $match) {
        # Fallback: widest non-primary display, in case resolution ever changes.
        $match = $monitors | Where-Object { -not $_.Primary } | Sort-Object Width -Descending | Select-Object -First 1
    }
    return $match
}

# Known address-bar AutomationIds for browsers actually tested against this
# script. Firefox's "urlbar-input" is confirmed live. Others are
# best-effort names Chromium browsers have used for their omnibox and are
# NOT independently verified here - the startswith-http fallback below
# covers those cases too, just without the blank-tab detection benefit
# that a known id gives (a truly empty address bar has nothing to pattern-
# match against, so an unrecognized browser can still find an existing
# marvel.com tab, but "no marvel tab found, is a blank tab already open"
# degrades to "no" for it - a new tab just gets opened instead, which
# still works correctly, just slightly less tidy).
$script:KnownAddressBarAutomationIds = @('urlbar-input', 'omnibox', 'toolbar-input', 'view_id_omnibox')

function Get-AddressBarCandidates {
    <# Restricts to actual address-bar elements, not just any Edit control
       anywhere in the window - a plain "any Edit/Value control" search
       picks up dozens of unrelated elements from OTHER background tabs'
       page content that Firefox keeps attached in the accessibility tree
       even while inactive (confirmed live: a Reddit search filter box, a
       chat input, a Settings search box, all with no relation to the
       active tab's actual address). #>
    param([Parameter(Mandatory)][IntPtr]$Hwnd)
    $candidates = New-Object System.Collections.Generic.List[object]
    try {
        $elem = [System.Windows.Automation.AutomationElement]::FromHandle($Hwnd)
        if (-not $elem) { return $candidates }
        $condEdit = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit)
        $condCombo = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::ComboBox)
        $orCond = New-Object System.Windows.Automation.OrCondition($condEdit, $condCombo)
        $found = $elem.FindAll([System.Windows.Automation.TreeScope]::Descendants, $orCond)
        foreach ($e in $found) {
            $autoId = $e.Current.AutomationId
            $name = $e.Current.Name
            if (($script:KnownAddressBarAutomationIds -contains $autoId) -or ($name -match '^https?://')) {
                $value = $null
                try {
                    $vp = $e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern) -as [System.Windows.Automation.ValuePattern]
                    if ($vp) { $value = $vp.Current.Value }
                } catch { }
                [void]$candidates.Add([pscustomobject]@{ Element = $e; AutomationId = $autoId; Name = $name; Value = $value })
            }
        }
    } catch { }
    return $candidates
}

function Find-MarvelOrBlankBrowserWindow {
    <# Scans every top-level window of the given browser processes for a
       currently-active tab whose address bar contains the target URL
       fragment. This can only see each window's ACTIVE tab (whatever its
       address bar currently shows) - there is no generic, browser-agnostic
       way to read every background tab's URL without a debugging flag or
       extension, which would break working with "whatever the default
       browser is". Also separately notes the first window found with a
       genuinely blank address bar (a real new tab). #>
    param(
        [Parameter(Mandatory)][System.Diagnostics.Process[]]$Processes,
        [string]$UrlFragment = 'marvel\.com/comics/issue'
    )
    $pids = New-Object 'System.Collections.Generic.HashSet[uint32]'
    foreach ($p in $Processes) { [void]$pids.Add([uint32]$p.Id) }
    if ($pids.Count -eq 0) { return @{ Marvel = $null; Blank = $null } }

    $windows = [TVMode]::GetTopLevelWindowsForProcesses($pids)
    $marvelMatch = $null
    $blankMatch = $null
    foreach ($w in $windows) {
        $candidates = Get-AddressBarCandidates -Hwnd $w.Handle
        foreach ($c in $candidates) {
            if ($c.Name -match $UrlFragment -or $c.Value -match $UrlFragment) { $marvelMatch = $w; break }
            elseif (($script:KnownAddressBarAutomationIds -contains $c.AutomationId) -and [string]::IsNullOrEmpty($c.Value) -and -not $blankMatch) {
                $blankMatch = $w
            }
        }
        if ($marvelMatch) { break }
    }
    return @{ Marvel = $marvelMatch; Blank = $blankMatch; AllWindows = $windows }
}

function Assert-Focused {
    <# Every keystroke this tool sends goes through here first. If the
       target window can't be confirmed in the foreground, throw instead of
       sending - otherwise the keys land in whatever app IS in front
       (observed: Ctrl+T and "marvel0 " typed into a different app when
       focusing failed). #>
    param([Parameter(Mandatory)][IntPtr]$Hwnd)
    if (-not [TVMode]::Focus($Hwnd)) {
        throw "Couldn't bring the browser window to the front ($([TVMode]::LastFocusDiagnostic)), so no keystrokes were sent - rather than risk typing into a different app."
    }
    Start-Sleep -Milliseconds 150
}

function Move-WindowToVirtualDisplayAndFullscreen {
    <# Idempotent on purpose: F11 TOGGLES fullscreen, so a window that's
       already exactly on the virtual display is left alone rather than
       having F11 (and Magpie's toggle) blindly re-sent to it. #>
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd,
        [Parameter(Mandatory)]$Monitor
    )

    # Restore first so the real (non-minimized) geometry can be inspected.
    [TVMode]::Restore($Hwnd)
    Start-Sleep -Milliseconds 300

    $before = [TVMode]::GetWindowInfo($Hwnd)
    $alreadyInPlace = $before.Left -eq $Monitor.Left -and $before.Top -eq $Monitor.Top -and
        $before.Right -eq $Monitor.Right -and $before.Bottom -eq $Monitor.Bottom
    if ($alreadyInPlace) { return }

    # Fullscreen on some OTHER monitor - e.g. the laptop screen, where
    # Windows relocates it when Quit disables the virtual display, or where
    # you pressed F11 yourself while the watcher was waiting. F11 toggles,
    # so exit fullscreen from this known state first, then move and
    # re-enter it on the TV display, rather than guessing what a single
    # blind F11 would do.
    if (Test-WindowIsFullscreenOnItsMonitor -WinInfo $before) {
        Assert-Focused -Hwnd $Hwnd
        [TVMode]::SendKeyCombo(@([TVMode]::VK_F11))
        Start-Sleep -Milliseconds 700
    }

    [TVMode]::MoveWindowTo($Hwnd, $Monitor.Left, $Monitor.Top, $Monitor.Width, $Monitor.Height)
    Start-Sleep -Milliseconds 400
    Assert-Focused -Hwnd $Hwnd
    [TVMode]::SendKeyCombo(@([TVMode]::VK_F11))
    Start-Sleep -Milliseconds 500
    # Turn Magpie's upscaling on for this now-fullscreened, now-focused window.
    Assert-Focused -Hwnd $Hwnd
    [TVMode]::SendKeyCombo(@([TVMode]::VK_LWIN, [TVMode]::VK_SHIFT, [TVMode]::VK_A))
}

function Test-WindowIsFullscreenOnItsMonitor {
    param([Parameter(Mandatory)]$WinInfo)
    $monitors = [TVMode]::GetMonitors()
    foreach ($m in $monitors) {
        if ($WinInfo.Left -eq $m.Left -and $WinInfo.Top -eq $m.Top -and $WinInfo.Right -eq $m.Right -and $WinInfo.Bottom -eq $m.Bottom) {
            return $true
        }
    }
    return $false
}
