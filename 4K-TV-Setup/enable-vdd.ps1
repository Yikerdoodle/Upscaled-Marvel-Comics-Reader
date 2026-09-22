$log = "E:\ComicUpscale\4K-TV-Setup\enable-vdd.log"
pnputil /enable-device "ROOT\DISPLAY\0000" 2>&1 | Out-File $log
"done" | Out-File $log -Append
