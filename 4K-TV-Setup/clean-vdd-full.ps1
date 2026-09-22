$log = "E:\ComicUpscale\4K-TV-Setup\clean-vdd-full.log"
"=== removing all ghost device instances ===" | Out-File $log
foreach ($id in @("ROOT\DISPLAY\0000", "ROOT\DISPLAY\0001", "ROOT\DISPLAY\0002")) {
    "--- $id ---" | Out-File $log -Append
    pnputil /remove-device "$id" 2>&1 | Out-File $log -Append
}

"=== confirming none remain ===" | Out-File $log -Append
Get-PnpDevice | Where-Object { $_.InstanceId -like "ROOT\DISPLAY*" } | Out-File $log -Append

"=== installing exactly one fresh instance via devcon directly ===" | Out-File $log -Append
$devcon = "E:\ComicUpscale\4K-TV-Setup\VDD-Control\Dependencies\devcon.exe"
$inf = "E:\ComicUpscale\4K-TV-Setup\VDD-Control\SignedDrivers\x86\VDD\MttVDD.inf"
& $devcon install $inf "Root\MttVDD" 2>&1 | Out-File $log -Append

Start-Sleep -Seconds 2
"=== resulting device instances ===" | Out-File $log -Append
Get-PnpDevice | Where-Object { $_.InstanceId -like "ROOT\DISPLAY*" } | Out-File $log -Append
