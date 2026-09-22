Copy-Item -Path "E:\ComicUpscale\4K-TV-Setup\sunshine.conf" -Destination "C:\Program Files\Sunshine\config\sunshine.conf" -Force
Write-Output ("copied, new size: " + (Get-Item "C:\Program Files\Sunshine\config\sunshine.conf").Length + " bytes")
