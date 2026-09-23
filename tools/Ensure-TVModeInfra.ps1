<#
  Elevated helper for TV mode. Runs ONLY via the pre-approved
  "ComicUpscale-TVMode-ElevatedHelper" scheduled task (see
  Setup-TVModeElevationTask.ps1) - never launched directly by the
  double-click launcher itself, which is why it can do admin-only work
  (pnputil enable/disable-device, Start-Service/Stop-Service) without a
  UAC prompt.

  The action to perform is chosen by a flag file, since a Scheduled
  Task's own Action arguments are fixed at registration time - this is
  how one already-registered, already-ACL-opened task serves every
  elevated step without a second one needing the same manual setup:
    - "enable-vdd":       enable the virtual 4K display device.
    - "restart-sunshine": (re)start the Sunshine service and wait for its
                          web port - always a full restart, since Sunshine
                          only enumerates displays once at its own startup.
    - "teardown":         the tray icon's Quit action - stop Sunshine
                          completely, then disable the virtual display.
    - "ensure" (default when no flag file exists, e.g. triggered by hand
      from Task Scheduler): enable the virtual display if needed, and
      restart Sunshine if that happened or it isn't running.

  Deliberately does NOT touch Windows' display topology (Win+P "Project"
  mode) - DisplaySwitch.exe acts on the interactive desktop session, and
  this runs as an S4U logon with no interactive desktop. The non-elevated
  launcher handles that part itself, sequenced between these actions.

  Writes a status JSON file the non-elevated launcher polls for, since
  Scheduled Tasks triggered via Start-ScheduledTask don't return output
  directly.
#>

$statusPath = Join-Path $PSScriptRoot '.tv-infra-status.json'
$actionFlagPath = Join-Path $PSScriptRoot '.tv-mode-action'
$status = [ordered]@{
    timestamp            = $null
    action               = $null
    success              = $false
    vddWasEnabled        = $false
    vddWasDisabled       = $false
    sunshineWasRestarted = $false
    error                = $null
}

$action = 'ensure'
if (Test-Path $actionFlagPath) {
    $action = (Get-Content $actionFlagPath -Raw -ErrorAction SilentlyContinue).Trim()
    Remove-Item $actionFlagPath -Force -ErrorAction SilentlyContinue
}
$status.action = $action

function Get-VddDevice {
    # Direct filtered CIM query (~2s) rather than Get-PnpDevice, which
    # enumerates every device on the machine first (~7s here).
    # ConfigManagerErrorCode: 0 = working, 22 = disabled.
    $vdd = Get-CimInstance Win32_PnPEntity -Filter 'DeviceID LIKE "ROOT\\DISPLAY\\%"' | Select-Object -First 1
    if (-not $vdd) { throw "Virtual Display Driver device not found (no ROOT\DISPLAY\* instance). See 4K-TV-Setup/README.md." }
    return $vdd
}

function Enable-Vdd {
    $vdd = Get-VddDevice
    if ($vdd.ConfigManagerErrorCode -eq 0) { return $false }
    pnputil /enable-device $vdd.DeviceID | Out-Null
    $deadline = (Get-Date).AddSeconds(25)
    do {
        Start-Sleep -Milliseconds 500
        $vdd = Get-VddDevice
    } while ($vdd.ConfigManagerErrorCode -ne 0 -and (Get-Date) -lt $deadline)
    if ($vdd.ConfigManagerErrorCode -ne 0) { throw "Virtual display did not come up after enabling (ConfigManagerErrorCode $($vdd.ConfigManagerErrorCode))." }
    return $true
}

function Stop-Sunshine {
    Stop-Service SunshineService -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    Get-Process sunshine -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

function Restart-Sunshine {
    if ((Get-Service SunshineService -ErrorAction Stop).Status -ne 'Stopped') {
        Stop-Sunshine
        Start-Sleep -Seconds 1
    }
    Start-Service SunshineService

    # Sunshine's normal startup (NVENC capability probing across
    # H.264/HEVC/AV1) takes ~30s every time per its own log - not just on
    # cold boots - so this wait is deliberately generous.
    $deadline = (Get-Date).AddSeconds(75)
    $up = $false
    do {
        Start-Sleep -Milliseconds 500
        $up = Test-NetConnection -ComputerName localhost -Port 47990 -WarningAction SilentlyContinue -InformationLevel Quiet
    } while (-not $up -and (Get-Date) -lt $deadline)
    if (-not $up) { throw "Sunshine service started but never bound port 47990." }
}

try {
    switch ($action) {
        'enable-vdd' {
            $status.vddWasEnabled = Enable-Vdd
        }
        'restart-sunshine' {
            Restart-Sunshine
            $status.sunshineWasRestarted = $true
        }
        'teardown' {
            Stop-Sunshine
            $vdd = Get-VddDevice
            if ($vdd.ConfigManagerErrorCode -eq 0) {
                pnputil /disable-device $vdd.DeviceID | Out-Null
                $status.vddWasDisabled = $true
            }
        }
        'ensure' {
            $status.vddWasEnabled = Enable-Vdd
            if ($status.vddWasEnabled -or (Get-Service SunshineService).Status -ne 'Running') {
                Restart-Sunshine
                $status.sunshineWasRestarted = $true
            }
        }
        default { throw "Unknown action '$action'." }
    }
    $status.success = $true
} catch {
    $status.error = $_.Exception.Message
}

$status.timestamp = (Get-Date).ToString('o')
$status | ConvertTo-Json | Set-Content -Path $statusPath -Encoding UTF8
