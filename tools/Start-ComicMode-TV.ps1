<#
  Orchestrator behind "Read Marvel Comics Upscaled - 4K TV Mode.vbs".
  Runs fully hidden (no console window) - see that .vbs for the launch
  wrapper, same pattern as the existing laptop-mode launcher.

  Order of operations, and why:
    1. Bring the virtual 4K display up as a real extended desktop, THEN
       make sure Sunshine is running against it. Order matters: the tray
       icon's Quit disables the display and sets Windows to "PC screen
       only", so coming back means enable device -> switch to Extend ->
       enforce 3840x2160 -> (re)start Sunshine last, since Sunshine only
       enumerates displays once, at its own startup. Admin-only steps go
       through the pre-approved elevated task; the display-topology step
       (DisplaySwitch.exe) runs here instead, because it acts on the
       interactive desktop session, which the elevated S4U task can't see.
    2. Make sure Magpie is running in the "TV 4K" scaling mode specifically
       - closing and relaunching it if it's running in some OTHER mode,
       since Magpie only reads its config at startup and silently reverts
       live edits otherwise.
    3. Find the default browser (whatever it currently is, not hardcoded),
       and look for a currently-open tab already on a marvel.com/comics/
       issue page. If found, move+fullscreen it on the TV display right
       away and turn Magpie's upscaling on for it.
    4. Otherwise, get a blank tab ready (reusing one if already open) with
       "marvel0 " typed in - your Series/Issue search shortcut - and leave
       it on the laptop screen for you to finish, then hand off to
       Watch-BrowserFullscreen.ps1 to notice when you press F11 yourself
       and move it over at that point.
    5. Leave a "4K" tray icon whose Quit stops Magpie and Sunshine,
       disables the virtual display, and sets "PC screen only".
#>

. (Join-Path $PSScriptRoot 'TVModeCommon.ps1')
Add-Type -Path (Join-Path $PSScriptRoot '..\4K-TV-Setup\SetVirtualDisplay4K.cs') -ErrorAction Stop

$statusPath = Join-Path $PSScriptRoot '.tv-infra-status.json'
$actionFlagPath = Join-Path $PSScriptRoot '.tv-mode-action'
$elevatedTaskName = 'ComicUpscale-TVMode-ElevatedHelper'
$displaySwitch = Join-Path $env:SystemRoot 'System32\DisplaySwitch.exe'

function Show-TvModeWarning($message) {
    [System.Windows.Forms.MessageBox]::Show($message, 'Read Marvel Comics Upscaled - 4K TV Mode', 'OK', 'Warning') | Out-Null
}

function Test-VddEnabled {
    # Filtered CIM query (~2s) instead of Get-PnpDevice (~7s, enumerates
    # every device). ConfigManagerErrorCode 0 = working, 22 = disabled.
    $vdd = Get-CimInstance Win32_PnPEntity -Filter 'DeviceID LIKE "ROOT\\DISPLAY\\%"' | Select-Object -First 1
    return [bool]($vdd -and $vdd.ConfigManagerErrorCode -eq 0)
}

function Test-SunshineUp {
    return [bool](Test-NetConnection -ComputerName localhost -Port 47990 -WarningAction SilentlyContinue -InformationLevel Quiet)
}

function Invoke-ElevatedAction {
    <# Runs one action of Ensure-TVModeInfra.ps1 through the pre-approved
       elevated Scheduled Task (silent, no UAC) and returns its status. #>
    param([Parameter(Mandatory)][string]$Action, [int]$TimeoutSeconds = 95)
    Remove-Item $statusPath -Force -ErrorAction SilentlyContinue
    Set-Content -Path $actionFlagPath -Value $Action -Encoding ASCII -NoNewline
    Start-ScheduledTask -TaskName $elevatedTaskName -ErrorAction Stop

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path $statusPath) {
            # The file can exist a moment before it's fully written.
            try { return Get-Content $statusPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { }
        }
        Start-Sleep -Milliseconds 500
    }
    return [pscustomobject]@{ success = $false; error = "The elevated '$Action' step didn't finish in time. Check Task Scheduler history for '$elevatedTaskName'." }
}

# --- Step 1: virtual display (enabled, extended, 4K) + Sunshine ---
$displayChanged = $false

try {
    if (-not (Test-VddEnabled)) {
        $r = Invoke-ElevatedAction 'enable-vdd'
        if (-not $r.success) {
            Show-TvModeWarning "Couldn't enable the virtual 4K display: $($r.error)"
            exit 1
        }
        $displayChanged = $true
    }

    if (-not (Get-VirtualDisplayMonitor)) {
        # Covers "PC screen only" (set by Quit) and "Duplicate" alike - in
        # both, the virtual display isn't its own desktop area yet.
        & $displaySwitch /extend
        $deadline = (Get-Date).AddSeconds(15)
        while (-not (Get-VirtualDisplayMonitor) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
        if (-not (Get-VirtualDisplayMonitor)) {
            Show-TvModeWarning "Switched Windows to Extend mode, but the virtual 4K display never appeared as its own screen."
            exit 1
        }
        $displayChanged = $true
    }

    $vmon = Get-VirtualDisplayMonitor
    if ($vmon.Width -ne 3840 -or $vmon.Height -ne 2160) {
        [void][VDisplay]::SetResolution('Virtual Display Driver', 3840, 2160, 60)
        Start-Sleep -Milliseconds 800
        $vmon = Get-VirtualDisplayMonitor
        if ($vmon.Width -ne 3840 -or $vmon.Height -ne 2160) {
            Show-TvModeWarning "The virtual display is at $($vmon.Width)x$($vmon.Height) and couldn't be set to 3840x2160."
            exit 1
        }
        $displayChanged = $true
    }

    if ($displayChanged -or -not (Test-SunshineUp)) {
        $r = Invoke-ElevatedAction 'restart-sunshine'
        if (-not $r.success) {
            # The elevated helper's own patience may have run out moments
            # before Sunshine finished binding its port.
            $graceDeadline = (Get-Date).AddSeconds(20)
            while (-not (Test-SunshineUp) -and (Get-Date) -lt $graceDeadline) { Start-Sleep -Milliseconds 500 }
            if (-not (Test-SunshineUp)) {
                Show-TvModeWarning "Couldn't get Sunshine running: $($r.error)`n`nCheck 4K-TV-Setup/README.md."
                exit 1
            }
        }
    }
} catch {
    Show-TvModeWarning "Setting up the virtual TV display / Sunshine failed: $($_.Exception.Message)`n`nCheck 4K-TV-Setup/README.md."
    exit 1
}

# --- Step 2: Magpie in "TV 4K" mode ---
$magpieConfigPath = Join-Path $env:LOCALAPPDATA 'Magpie\config\v2\config.json'
$targetModeName = 'TV 4K'

$cfg = Get-Content $magpieConfigPath -Raw | ConvertFrom-Json
$currentIndex = $cfg.profiles[0].scalingMode
$currentModeName = if ($currentIndex -ge 0 -and $currentIndex -lt $cfg.scalingModes.Count) { $cfg.scalingModes[$currentIndex].name } else { $null }
$magpieProc = Get-Process Magpie -ErrorAction SilentlyContinue

if ($currentModeName -ne $targetModeName) {
    if ($magpieProc) {
        Stop-Process -Id $magpieProc.Id -Force
        Start-Sleep -Seconds 1
        $magpieProc = $null
    }
    $targetIndex = -1
    for ($i = 0; $i -lt $cfg.scalingModes.Count; $i++) {
        if ($cfg.scalingModes[$i].name -eq $targetModeName) { $targetIndex = $i; break }
    }
    if ($targetIndex -lt 0) {
        Show-TvModeWarning "Magpie scaling mode '$targetModeName' wasn't found in its config. Has it been renamed?"
        exit 1
    }
    $cfg.profiles[0].scalingMode = $targetIndex
    $cfg | ConvertTo-Json -Depth 20 | Set-Content -Path $magpieConfigPath -Encoding UTF8

    # Verify by reading back, not just assuming the write took - Magpie's
    # config has silently reverted edits made while it was running before.
    $verify = Get-Content $magpieConfigPath -Raw | ConvertFrom-Json
    if ($verify.profiles[0].scalingMode -ne $targetIndex) {
        Show-TvModeWarning "Wrote the 'TV 4K' mode to Magpie's config, but it didn't stick on readback."
        exit 1
    }
}

if (-not $magpieProc) {
    & (Join-Path $PSScriptRoot 'Start-MagpieHidden.ps1')
}

# --- Step 3/4: default browser + marvel.com/comics/issue tab ---
$browserExe = Get-DefaultBrowserExe
$monitor = Get-VirtualDisplayMonitor
if (-not $monitor) {
    Show-TvModeWarning "Couldn't find the virtual 4K display's monitor geometry."
    exit 1
}

$procs = Get-BrowserProcesses -ExePath $browserExe
$result = if ($procs) { Find-MarvelOrBlankBrowserWindow -Processes $procs } else { @{ Marvel = $null; Blank = $null; AllWindows = @() } }

# Every keystroke below goes through Assert-Focused, which throws rather
# than typing into some other app if the browser can't be brought to the
# front. A failure here warns but still falls through to the tray icon,
# since the display/Sunshine/Magpie are already up and Quit should exist.
try {
    if ($result.Marvel) {
        Move-WindowToVirtualDisplayAndFullscreen -Hwnd $result.Marvel.Handle -Monitor $monitor
    } else {
        if ($result.Blank) {
            $targetHwnd = $result.Blank.Handle
        } else {
            if ($result.AllWindows.Count -gt 0) {
                $targetHwnd = $result.AllWindows[0].Handle
            } else {
                Start-Process -FilePath $browserExe
                $deadline = (Get-Date).AddSeconds(8)
                $win = $null
                do {
                    Start-Sleep -Milliseconds 400
                    $freshProcs = Get-BrowserProcesses -ExePath $browserExe
                    if ($freshProcs) {
                        $pidSet = New-Object 'System.Collections.Generic.HashSet[uint32]'
                        foreach ($p in $freshProcs) { [void]$pidSet.Add([uint32]$p.Id) }
                        $win = [TVMode]::GetTopLevelWindowsForProcesses($pidSet) | Select-Object -First 1
                    }
                } while (-not $win -and (Get-Date) -lt $deadline)
                if (-not $win) { throw "The default browser didn't open a window in time." }
                $targetHwnd = $win.Handle
                Start-Sleep -Milliseconds 500
            }
            Assert-Focused -Hwnd $targetHwnd
            [TVMode]::SendKeyCombo(@([TVMode]::VK_CONTROL, [TVMode]::VK_T))
            Start-Sleep -Milliseconds 600
        }

        Assert-Focused -Hwnd $targetHwnd
        [System.Windows.Forms.SendKeys]::SendWait('marvel0 ')
    }
} catch {
    Show-TvModeWarning $_.Exception.Message
}

if (-not $result.Marvel) {
    # Left on the laptop screen on purpose - you finish typing the actual
    # issue yourself. This watcher notices when you press F11 and moves it
    # to the TV display at that point, then exits.
    $watcherScript = Join-Path $PSScriptRoot 'Watch-BrowserFullscreen.ps1'
    Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$watcherScript`"", '-BrowserExe', "`"$browserExe`""
    )
}

# --- Step 5: tray icon, right-click > Quit tears TV mode back down ---
# A named mutex means a repeat double-click of the launcher (e.g. to jump
# to a different issue) just does steps 1-4 above again and exits, rather
# than piling up a second icon - only the first still-running instance
# keeps holding this and stays around to host it.
$mutex = New-Object System.Threading.Mutex($false, 'Global\ComicUpscaleTVModeTrayIcon')
if ($mutex.WaitOne(0)) {
    Add-Type -AssemblyName System.Drawing

    $bmp = New-Object System.Drawing.Bitmap 32, 32
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::FromArgb(255, 20, 20, 24))
    $g.FillRectangle([System.Drawing.Brushes]::White, 2, 2, 28, 28)
    $g.FillRectangle((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 20, 20, 24))), 4, 4, 24, 24)
    $font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $g.DrawString('4K', $font, [System.Drawing.Brushes]::White, 2.0, 9.0)
    $hIcon = $bmp.GetHicon()
    $icon = [System.Drawing.Icon]::FromHandle($hIcon)

    $trayIcon = New-Object System.Windows.Forms.NotifyIcon
    $trayIcon.Icon = $icon
    $trayIcon.Text = 'Marvel Comics - 4K TV Mode'
    $trayIcon.Visible = $true

    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $quitItem = New-Object System.Windows.Forms.ToolStripMenuItem 'Quit'
    $quitItem.add_Click({
        $trayIcon.Visible = $false

        Get-Process Magpie -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

        # Stops Sunshine, then disables the virtual display - both need
        # admin rights, so they go through the same silent elevated task.
        # Usually ~7s, but one observed run took ~58s; the icon is already
        # gone, so a generous wait costs nothing visible and keeps the
        # "PC screen only" step reliably AFTER the display is disabled.
        try { $null = Invoke-ElevatedAction 'teardown' 90 } catch { }

        # Then back to "PC screen only". Passing /internal when it's
        # already the active mode is a harmless no-op, so this doubles as
        # the "check, and fix only if needed" step.
        & $displaySwitch /internal

        [System.Windows.Forms.Application]::Exit()
    })
    [void]$menu.Items.Add($quitItem)
    $trayIcon.ContextMenuStrip = $menu

    [System.Windows.Forms.Application]::Run()

    $trayIcon.Visible = $false
    $trayIcon.Dispose()
    $mutex.ReleaseMutex()
}
$mutex.Dispose()
