$log = "E:\ComicUpscale\4K-TV-Setup\disable-vdd.log"
"=== disabling all ROOT\DISPLAY instances ===" | Out-File $log
foreach ($id in @("ROOT\DISPLAY\0000", "ROOT\DISPLAY\0001", "ROOT\DISPLAY\0002", "ROOT\DISPLAY\0003", "ROOT\DISPLAY\0004")) {
    "--- $id ---" | Out-File $log -Append
    pnputil /disable-device "$id" 2>&1 | Out-File $log -Append
}
"done" | Out-File $log -Append
