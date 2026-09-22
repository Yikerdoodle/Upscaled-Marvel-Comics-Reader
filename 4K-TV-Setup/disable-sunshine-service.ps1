$log = "E:\ComicUpscale\4K-TV-Setup\disable-sunshine-service.log"
"=== stopping service ===" | Out-File $log
Stop-Service SunshineService -Force -ErrorAction SilentlyContinue 2>&1 | Out-File $log -Append
Start-Sleep -Seconds 1
Get-Process sunshine -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

"=== setting startup type to disabled ===" | Out-File $log -Append
Set-Service SunshineService -StartupType Disabled -ErrorAction SilentlyContinue 2>&1 | Out-File $log -Append

"=== confirming ===" | Out-File $log -Append
Get-Service SunshineService | Select-Object Status, StartType | Out-File $log -Append
"done" | Out-File $log -Append
