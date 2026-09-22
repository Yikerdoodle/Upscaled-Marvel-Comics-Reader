$log = "E:\ComicUpscale\4K-TV-Setup\clean-restart.log"
"=== stopping service ===" | Out-File $log
Stop-Service SunshineService -Force -ErrorAction SilentlyContinue 2>&1 | Out-File $log -Append
Start-Sleep -Seconds 1

"=== killing any remaining sunshine.exe ===" | Out-File $log -Append
Get-Process sunshine -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
$remaining = Get-Process sunshine -ErrorAction SilentlyContinue
"remaining processes: $($remaining.Count)" | Out-File $log -Append

"=== confirming service stopped ===" | Out-File $log -Append
(Get-Service SunshineService).Status | Out-File $log -Append

"=== clearing old log so the next run is unambiguous ===" | Out-File $log -Append
Remove-Item "C:\Program Files\Sunshine\config\sunshine.log*" -Force -ErrorAction SilentlyContinue
"done" | Out-File $log -Append
