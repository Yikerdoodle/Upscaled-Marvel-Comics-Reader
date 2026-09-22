<#
  Orchestrator behind "Read Marvel Comics Upscaled - 4K TV Mode.vbs".
  Runs fully hidden (no console window) - see that .vbs for the launch
  wrapper, same pattern as the existing laptop-mode launcher.

  Order of operations, and why:
    1. Make sure the virtual 4K display and Sunshine are both actually up.
       Only touches anything (which needs the elevated helper task) if one
       of them is off - the common case (both already fine, which should
       be true almost all the time once left alone) costs nothing.
    2. Make sure Magpie is running in the "TV 4K" scaling mode specifically
       - closing and relaunching it if it's running in some OTHER mode,
       since Magpie only reads its config at startup and silently reverts
       live edits otherwise (learned the hard way earlier in this project).
    3. Find the default browser (whatever it currently is, not hardcoded),
       and look for a currently-open tab already on a marvel.com/comics/
       issue page. If found, move+fullscreen it on the TV display right
       away and turn Magpie's upscaling on for it.
    4. Otherwise, get a blank tab ready (reusing one if already open) with
       "marvel0 " typed in - your Series/Issue search shortcut - and leave
       it on the laptop screen for you to finish, then hand off to
       Watch-BrowserFullscreen.ps1 to notice when you press F11 yourself
       and move it over at that point.
#>

. (Join-Path $PSScriptRoot 'TVModeCommon.ps1')

$statusPath = Join-Path $PSScriptRoot '.tv-infra-status.json'
$elevatedTaskName = 'ComicUpscale-TVMode-ElevatedHelper'

function Test-InfraReady {
    $vdd = Get-PnpDevice | Where-Object { $_.InstanceId -like 'ROOT\DISPLAY\*' } | Select-Object -First 1
    $vddOk = $vdd -and $vdd.Status -eq 'OK'
    $sunshineOk = Test-NetConnection -ComputerName localhost -Port 47990 -WarningAction SilentlyContinue -InformationLevel Quiet
    return [bool]($vddOk -and $sunshineOk)
}

function Show-TvModeWarning($message) {
    [System.Windows.Forms.MessageBox]::Show($message, 'Read Marvel Comics Upscaled - 4K TV Mode', 'OK', 'Warning') | Out-Null
}

# --- Step 1: virtual display + Sunshine ---
# Only reached (and only triggers the elevated helper) on the rare
# occasion one of these is actually off - e.g. right after a reboot. The
# common case (both already fine, which is normal once left alone) never
# touches this at all. The helper runs via a pre-registered Scheduled Task
# (S4U logon as the Admin account, no stored password, its own ACL opened
# up to let this everyday account trigger it) - so even this rare path
# stays fully silent, no UAC prompt.
if (-not (Test-InfraReady)) {
    if (Test-Path $statusPath) { Remove-Item $statusPath -Force -ErrorAction SilentlyContinue }
    try {
        Start-ScheduledTask -TaskName $elevatedTaskName -ErrorAction Stop
    } catch {
        Show-TvModeWarning "Couldn't start the elevated setup task ('$elevatedTaskName'). See 4K-TV-Setup/README.md.`n`n$($_.Exception.Message)"
        exit 1
    }

    $deadline = (Get-Date).AddSeconds(30)
    while (-not (Test-Path $statusPath) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }

    if (-not (Test-Path $statusPath)) {
        Show-TvModeWarning "The virtual display / Sunshine setup task didn't finish in time. Check Task Scheduler history for '$elevatedTaskName'."
        exit 1
    }
    $result = Get-Content $statusPath -Raw | ConvertFrom-Json
    if (-not $result.success -or -not (Test-InfraReady)) {
        Show-TvModeWarning "Couldn't get the virtual TV display and Sunshine both ready: $($result.error)`n`nCheck 4K-TV-Setup/README.md."
        exit 1
    }
}

# --- Step 2: Magpie in "TV 4K" mode ---
$magpieConfigPath = Join-Path $env:LOCALAPPDATA 'Magpie\config\v2\config.json'
$magpieExe = 'E:\ComicUpscale\Magpie\Magpie.exe'
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

if ($result.Marvel) {
    Move-WindowToVirtualDisplayAndFullscreen -Hwnd $result.Marvel.Handle -Monitor $monitor
} else {
    if ($result.Blank) {
        $targetHwnd = $result.Blank.Handle
        [TVMode]::Focus($targetHwnd)
        Start-Sleep -Milliseconds 300
    } elseif ($result.AllWindows.Count -gt 0) {
        $targetHwnd = $result.AllWindows[0].Handle
        [TVMode]::Focus($targetHwnd)
        Start-Sleep -Milliseconds 300
        [TVMode]::SendKeyCombo(@([TVMode]::VK_CONTROL, [TVMode]::VK_T))
        Start-Sleep -Milliseconds 600
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
        if (-not $win) {
            Show-TvModeWarning "The default browser didn't open a window in time."
            exit 1
        }
        $targetHwnd = $win.Handle
        [TVMode]::Focus($targetHwnd)
        Start-Sleep -Milliseconds 500
        [TVMode]::SendKeyCombo(@([TVMode]::VK_CONTROL, [TVMode]::VK_T))
        Start-Sleep -Milliseconds 600
    }

    [TVMode]::Focus($targetHwnd)
    Start-Sleep -Milliseconds 200
    [System.Windows.Forms.SendKeys]::SendWait('marvel0 ')

    # Left on the laptop screen on purpose - you finish typing the actual
    # issue yourself. This watcher notices when you press F11 and moves it
    # to the TV display at that point, then exits.
    $watcherScript = Join-Path $PSScriptRoot 'Watch-BrowserFullscreen.ps1'
    Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$watcherScript`"", '-BrowserExe', "`"$browserExe`""
    )
}
