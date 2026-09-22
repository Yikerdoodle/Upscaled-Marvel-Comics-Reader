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

function Move-WindowToVirtualDisplayAndFullscreen {
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd,
        [Parameter(Mandatory)]$Monitor,
        [switch]$AlreadyFullscreen
    )
    [TVMode]::MoveWindowTo($Hwnd, $Monitor.Left, $Monitor.Top, $Monitor.Width, $Monitor.Height)
    Start-Sleep -Milliseconds 400
    if (-not $AlreadyFullscreen) {
        [TVMode]::Focus($Hwnd)
        Start-Sleep -Milliseconds 200
        [TVMode]::SendKeyCombo(@([TVMode]::VK_F11))
        Start-Sleep -Milliseconds 500
    }
    # Turn Magpie's upscaling on for this now-fullscreened, now-focused window.
    [TVMode]::Focus($Hwnd)
    Start-Sleep -Milliseconds 200
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
