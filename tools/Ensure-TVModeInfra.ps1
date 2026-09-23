<#
  Elevated helper for TV mode. Runs ONLY via the pre-approved
  "ComicUpscale-TVMode-ElevatedHelper" scheduled task (see
  Setup-TVModeElevationTask.ps1) - never launched directly by the
  double-click launcher itself, which is why it can do admin-only work
  (pnputil enable-device, Start-Service/Stop-Service) without a UAC
  prompt firing on every read.

  Two modes, chosen by an action flag file (since a Scheduled Task's own
  Action arguments are fixed at registration time - this is how the same
  already-registered, already-ACL-opened task serves both without
  needing a second one set up the same painful way):
    - default / "ensure" (no flag file, or it says "ensure"): only
      touches anything if the virtual display is off or Sunshine isn't
      already running - the common case (both already fine) exits fast.
    - "stop-sunshine": the tray icon's Quit action - stops Sunshine
      completely (service + any lingering process). Does NOT touch the
      virtual display - nobody asked for that, and leaving it enabled is
      the established low-risk steady state.

  Writes a status JSON file the non-elevated launcher polls for, since
  Scheduled Tasks triggered via Start-ScheduledTask don't return output
  directly.
#>

$statusPath = Join-Path $PSScriptRoot '.tv-infra-status.json'
$actionFlagPath = Join-Path $PSScriptRoot '.tv-mode-action'
$status = [ordered]@{
    timestamp            = $null
    success              = $false
    vddWasEnabled        = $false
    sunshineWasRestarted = $false
    error                = $null
}

$action = 'ensure'
if (Test-Path $actionFlagPath) {
    $action = (Get-Content $actionFlagPath -Raw -ErrorAction SilentlyContinue).Trim()
    Remove-Item $actionFlagPath -Force -ErrorAction SilentlyContinue
}

if ($action -eq 'stop-sunshine') {
    try {
        Stop-Service SunshineService -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
        Get-Process sunshine -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        $status.success = $true
    } catch {
        $status.error = $_.Exception.Message
    }
    $status.timestamp = (Get-Date).ToString('o')
    $status | ConvertTo-Json | Set-Content -Path $statusPath -Encoding UTF8
    exit 0
}

try {
    $vdd = Get-PnpDevice | Where-Object { $_.InstanceId -like 'ROOT\DISPLAY\*' } | Select-Object -First 1
    if (-not $vdd) { throw "Virtual Display Driver device not found (no ROOT\DISPLAY\* instance). See 4K-TV-Setup/README.md." }

    if ($vdd.Status -ne 'OK') {
        pnputil /enable-device $vdd.InstanceId | Out-Null
        $status.vddWasEnabled = $true
        $deadline = (Get-Date).AddSeconds(25)
        do {
            Start-Sleep -Milliseconds 500
            $vdd = Get-PnpDevice -InstanceId $vdd.InstanceId
        } while ($vdd.Status -ne 'OK' -and (Get-Date) -lt $deadline)
        if ($vdd.Status -ne 'OK') { throw "Virtual display did not come up after enabling (status: $($vdd.Status))." }
    }

    $svc = Get-Service SunshineService -ErrorAction Stop
    $needsRestart = $status.vddWasEnabled -or ($svc.Status -ne 'Running')

    if ($needsRestart) {
        if ($svc.Status -eq 'Running') {
            Stop-Service SunshineService -Force
            Start-Sleep -Seconds 1
            Get-Process sunshine -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
        }
        Start-Service SunshineService
        $status.sunshineWasRestarted = $true

        # Generous on purpose - a cold-boot scenario (this whole thing
        # tends to get triggered right after a reboot, since that's when
        # the virtual display / Sunshine are actually likely to be off)
        # means competing with the rest of Windows' own startup, and
        # Sunshine's own NVENC capability probing alone has been observed
        # taking 15-20+ seconds even on a warm start.
        $deadline = (Get-Date).AddSeconds(75)
        $up = $false
        do {
            Start-Sleep -Milliseconds 500
            $up = Test-NetConnection -ComputerName localhost -Port 47990 -WarningAction SilentlyContinue -InformationLevel Quiet
        } while (-not $up -and (Get-Date) -lt $deadline)
        if (-not $up) { throw "Sunshine service started but never bound port 47990." }
    }

    $status.success = $true
} catch {
    $status.error = $_.Exception.Message
}

$status.timestamp = (Get-Date).ToString('o')
$status | ConvertTo-Json | Set-Content -Path $statusPath -Encoding UTF8
