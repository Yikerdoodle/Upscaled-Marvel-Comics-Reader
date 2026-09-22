$log = "E:\ComicUpscale\4K-TV-Setup\pnputil-cycle.log"
"=== disable ===" | Out-File $log
pnputil /disable-device "ROOT\DISPLAY\0000" 2>&1 | Out-File $log -Append
Start-Sleep -Seconds 2
"=== enable ===" | Out-File $log -Append
pnputil /enable-device "ROOT\DISPLAY\0000" 2>&1 | Out-File $log -Append
