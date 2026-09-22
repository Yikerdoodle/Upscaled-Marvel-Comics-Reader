$log = "E:\ComicUpscale\4K-TV-Setup\enable-and-test.log"
"=== killing any interactive sunshine.exe ===" | Out-File $log
Get-Process sunshine -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

"=== re-enabling service startup type ===" | Out-File $log -Append
Set-Service SunshineService -StartupType Automatic -ErrorAction SilentlyContinue 2>&1 | Out-File $log -Append

"=== installing latest conf ===" | Out-File $log -Append
Copy-Item -Path "E:\ComicUpscale\4K-TV-Setup\sunshine.conf" -Destination "C:\Program Files\Sunshine\config\sunshine.conf" -Force
Write-Output ("copied, new size: " + (Get-Item "C:\Program Files\Sunshine\config\sunshine.conf").Length + " bytes") | Out-File $log -Append

"=== starting service ===" | Out-File $log -Append
Start-Service SunshineService -ErrorAction SilentlyContinue 2>&1 | Out-File $log -Append

"done" | Out-File $log -Append
