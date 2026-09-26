<#
  Shared functions for the "Read Marvel Comics Upscaled - 4K TV Mode"
  launcher. Dot-sourced by Start-ComicMode-TV.ps1 (the main orchestrator),
  TVModeTray.ps1 (the tray icon / Quit) and Watch-BrowserFullscreen.ps1
  (the background F11 watcher), so this logic only exists in one place.
#>

Add-Type -Path (Join-Path $PSScriptRoot 'TVModeCommon.cs') -ErrorAction Stop
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms

$script:TVStatusPath       = Join-Path $PSScriptRoot '.tv-infra-status.json'
$script:TVActionFlagPath   = Join-Path $PSScriptRoot '.tv-mode-action'
$script:TVElevatedTaskName = 'ComicUpscale-TVMode-ElevatedHelper'
$script:TVDisplaySwitchExe = Join-Path $env:SystemRoot 'System32\DisplaySwitch.exe'

function Invoke-ElevatedAction {
    <# Runs one action of Ensure-TVModeInfra.ps1 through the pre-approved
       elevated Scheduled Task (silent, no UAC) and returns its status. #>
    param([Parameter(Mandatory)][string]$Action, [int]$TimeoutSeconds = 95)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    # The task is set to IgnoreNew, so a trigger while a previous action is
    # still running (e.g. Quit clicked while the launch is mid Sunshine
    # restart) would be silently dropped - wait for it to finish first.
    while ((Get-ScheduledTask -TaskName $script:TVElevatedTaskName).State -eq 'Running' -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
    }

    Remove-Item $script:TVStatusPath -Force -ErrorAction SilentlyContinue
    Set-Content -Path $script:TVActionFlagPath -Value $Action -Encoding ASCII -NoNewline
    Start-ScheduledTask -TaskName $script:TVElevatedTaskName -ErrorAction Stop

    while ((Get-Date) -lt $deadline) {
        if (Test-Path $script:TVStatusPath) {
            # The file can exist a moment before it's fully written, and is
            # only trusted if it's the result of THIS action.
            try {
                $s = Get-Content $script:TVStatusPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                if ($s.action -eq $Action) { return $s }
            } catch { }
        }
        Start-Sleep -Milliseconds 500
    }
    return [pscustomobject]@{ action = $Action; success = $false; error = "The elevated '$Action' step didn't finish in time. Check Task Scheduler history for '$($script:TVElevatedTaskName)'." }
}

function Test-FileHasUtf8Bom {
    param([Parameter(Mandatory)][string]$Path)
    $fs = [System.IO.File]::OpenRead($Path)
    try {
        $b = New-Object byte[] 3
        $n = $fs.Read($b, 0, 3)
        return ($n -eq 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
    } finally { $fs.Dispose() }
}

function Set-MagpieDefaultScalingMode {
    <# Changes only the default profile's "scalingMode" number in Magpie's
       config, and writes it back as UTF-8 WITHOUT a byte-order mark.
       Magpie's JSON parser rejects a BOM outright ("failed to parse config,
       error 3") and then refuses to run - which is exactly what PowerShell
       5.1's Set-Content -Encoding UTF8 silently caused before. Editing just
       the one number (rather than a ConvertTo-Json round trip) also leaves
       the rest of Magpie's file untouched. #>
    param([Parameter(Mandatory)][string]$ConfigPath, [Parameter(Mandatory)][int]$Index)
    $text = [System.IO.File]::ReadAllText($ConfigPath)   # drops a BOM if one is there
    $profilesAt = $text.IndexOf('"profiles"')
    if ($profilesAt -lt 0) { throw "Magpie's config has no profiles section." }
    $m = ([regex]'"scalingMode"\s*:\s*-?\d+').Match($text, $profilesAt)
    if (-not $m.Success) { throw "Magpie's default profile has no scalingMode." }
    $replacement = $m.Value -replace '-?\d+$', "$Index"
    $text = $text.Substring(0, $m.Index) + $replacement + $text.Substring($m.Index + $m.Length)
    [System.IO.File]::WriteAllText($ConfigPath, $text, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-MagpieWindows {
    $magpie = Get-Process Magpie -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $magpie) { return @() }
    return [TVMode]::GetAllTopLevelWindowsForProcess([uint32]$magpie.Id)
}

function Test-MagpieStartupFailed {
    # A fatal startup problem leaves a standard error dialog as Magpie's
    # only real window.
    return [bool](Get-MagpieWindows | Where-Object { $_.ClassName -eq '#32770' })
}

function Wait-MagpieReady {
    <# $true once Magpie is up and running normally (its main window and
       its own tray icon exist - observed on a healthy start), $false if
       it's stuck on an error dialog or didn't get there in time. #>
    param([int]$TimeoutSeconds = 30)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $wins = Get-MagpieWindows
        if ($wins | Where-Object { $_.ClassName -eq '#32770' }) { return $false }
        if ($wins | Where-Object { $_.ClassName -eq 'Magpie_Main' -or $_.ClassName -eq 'Magpie_NotifyIcon' }) { return $true }
        if ($TimeoutSeconds -gt 0) { Start-Sleep -Milliseconds 500 }
    } while ((Get-Date) -lt $deadline)
    return $false
}

function Test-MagpieScalingOn {
    <# Whether Magpie is actually upscaling onto the given monitor right now:
       while it scales, Magpie shows its own full-monitor scaling window
       (class Window_Magpie_<guid>) - confirmed live covering exactly the
       virtual 4K display's bounds. #>
    param([Parameter(Mandatory)]$Monitor)
    return [bool](Get-MagpieWindows | Where-Object {
        $_.Visible -and $_.ClassName -like 'Window_Magpie_*' -and
        $_.Left -eq $Monitor.Left -and $_.Top -eq $Monitor.Top -and
        $_.Right -eq $Monitor.Right -and $_.Bottom -eq $Monitor.Bottom
    })
}

function Get-MagpieScaleHotkey {
    <# Magpie's "scale" shortcut, read from its own config so a changed
       shortcut keeps working. Magpie stores it as one number: the key's
       virtual-key code in the low byte, plus 0x100 Win, 0x200 Ctrl,
       0x400 Alt, 0x800 Shift - e.g. the default 2369 = 0x941 = Win+Shift+A
       (and its default overlay shortcut 2372 = 0x944 = Win+Shift+D, which
       confirms the bit layout). #>
    $code = 2369
    try {
        $c = (Get-Content (Join-Path $env:LOCALAPPDATA 'Magpie\config\v2\config.json') -Raw -Encoding UTF8 | ConvertFrom-Json).shortcuts.scale
        if ($c) { $code = [int]$c }
    } catch { }
    $keys = New-Object System.Collections.Generic.List[byte]
    $mods = [uint32]0
    if ($code -band 0x100) { $keys.Add([TVMode]::VK_LWIN);    $mods = $mods -bor [TVMode]::MOD_WIN }
    if ($code -band 0x200) { $keys.Add([TVMode]::VK_CONTROL); $mods = $mods -bor [TVMode]::MOD_CONTROL }
    if ($code -band 0x400) { $keys.Add([TVMode]::VK_MENU);    $mods = $mods -bor [TVMode]::MOD_ALT }
    if ($code -band 0x800) { $keys.Add([TVMode]::VK_SHIFT);   $mods = $mods -bor [TVMode]::MOD_SHIFT }
    $vk = [byte]($code -band 0xFF)
    $keys.Add($vk)
    return [pscustomobject]@{ Keys = $keys.ToArray(); Modifiers = $mods; Vk = [uint32]$vk }
}

function Test-MagpieListening {
    <# Whether Magpie has actually registered its scale hotkey yet - its
       windows exist a while before it does, and presses sent in that gap
       are silently lost. #>
    $hk = Get-MagpieScaleHotkey
    return [TVMode]::IsHotkeyTaken($hk.Modifiers, $hk.Vk)
}

function Start-MagpieScaling {
    <# Presses Magpie's scale hotkey for the given window, then confirms the
       scaling window actually appeared. Never presses it when scaling is
       already on, since the hotkey is a toggle. #>
    param([Parameter(Mandatory)][IntPtr]$Hwnd, [Parameter(Mandatory)]$Monitor, [int]$TimeoutSeconds = 5)
    if (Test-MagpieScalingOn -Monitor $Monitor) { return $true }
    # A scaling window that exists but isn't showing on the TV display
    # means Magpie IS scaling, just not visibly - pressing the toggle now
    # would switch it off, not on.
    if (Get-MagpieWindows | Where-Object { $_.ClassName -like 'Window_Magpie_*' }) { return $false }
    Assert-Focused -Hwnd $Hwnd
    [TVMode]::SendKeyCombo((Get-MagpieScaleHotkey).Keys)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 300
        if (Test-MagpieScalingOn -Monitor $Monitor) { return $true }
    }
    return $false
}

function Get-BrowserWindowOnMonitor {
    <# A default-browser window filling exactly the given monitor (i.e.
       fullscreen on it), or $null. #>
    param([Parameter(Mandatory)][string]$BrowserExe, [Parameter(Mandatory)]$Monitor)
    $procs = Get-BrowserProcesses -ExePath $BrowserExe
    if (-not $procs) { return $null }
    $pidSet = New-Object 'System.Collections.Generic.HashSet[uint32]'
    foreach ($p in $procs) { [void]$pidSet.Add([uint32]$p.Id) }
    return [TVMode]::GetTopLevelWindowsForProcesses($pidSet) | Where-Object {
        $_.Left -eq $Monitor.Left -and $_.Top -eq $Monitor.Top -and $_.Right -eq $Monitor.Right -and $_.Bottom -eq $Monitor.Bottom -and
        -not [TVMode]::IsMinimized($_.Handle)
    } | Select-Object -First 1
}

function Stop-TVModeHelperProcesses {
    <# Hidden PowerShell processes running the given tools scripts (e.g. a
       launch still in progress, or an F11 watcher and its prompt). #>
    param([Parameter(Mandatory)][string[]]$ScriptNames)
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
        Where-Object { $cmd = $_.CommandLine; $_.ProcessId -ne $PID -and ($ScriptNames | Where-Object { $cmd -like "*$_*" }) } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

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
       having F11 blindly re-sent to it.

       Deliberately does NOT turn Magpie's upscaling on: that's owned by
       one place only - the tray process's watch loop (TVModeTray.ps1),
       which confirms it took effect. Magpie's hotkey is a toggle, so two
       things pressing it could switch it straight back off. #>
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
