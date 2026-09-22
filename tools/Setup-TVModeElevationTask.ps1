<#
  Registers a Scheduled Task that runs Ensure-TVModeInfra.ps1 with admin
  rights, using S4U logon - this runs as the "Admin" account WITHOUT ever
  storing or being given its password (unlike LogonType Password, which
  Windows 10 Home's Task Scheduler GUI rejected here even entered
  correctly, because Home lacks the Local Security Policy editor needed to
  manage "Log on as a batch job" the normal way). S4U uses a different
  local logon mechanism that Administrators-group accounts are granted by
  default on every Windows edition, Home included.

  Re-runnable safely - Register-ScheduledTask -Force just replaces the
  existing definition. This script itself needs to run elevated once.
#>

$logPath = Join-Path $PSScriptRoot 'setup-elevation-task.log'
Start-Transcript -Path $logPath -Force | Out-Null

$taskName = 'ComicUpscale-TVMode-ElevatedHelper'
$scriptPath = Join-Path $PSScriptRoot 'Ensure-TVModeInfra.ps1'

if (-not (Test-Path $scriptPath)) {
    Write-Output "ERROR: Ensure-TVModeInfra.ps1 not found next to this script at $scriptPath"
    Stop-Transcript | Out-Null
    exit 1
}

$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""

$principal = New-ScheduledTaskPrincipal -UserId "$env:COMPUTERNAME\Admin" -LogonType S4U -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 2) `
    -MultipleInstances IgnoreNew

$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddYears(-1)

try {
    Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings -Trigger $trigger -Force -ErrorAction Stop | Out-Null
    Write-Output "Registered scheduled task '$taskName' with S4U logon."
    Get-ScheduledTask -TaskName $taskName | Select-Object TaskName, State

    Write-Output "=== Testing it right now via Start-ScheduledTask ==="
    $statusFile = Join-Path $PSScriptRoot '.tv-infra-status.json'
    Remove-Item $statusFile -Force -ErrorAction SilentlyContinue
    Start-ScheduledTask -TaskName $taskName
    $deadline = (Get-Date).AddSeconds(20)
    while (-not (Test-Path $statusFile) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
    if (Test-Path $statusFile) {
        Write-Output "SUCCESS - status file appeared:"
        Get-Content $statusFile | Write-Output
    } else {
        Write-Output "FAILED - status file never appeared. Task info:"
        Get-ScheduledTaskInfo -TaskName $taskName | Format-List *
    }
} catch {
    Write-Output "ERROR: $($_.Exception.Message)"
    Write-Output $_.Exception.ToString()
}

Stop-Transcript | Out-Null
