# Test harness: capture the laptop screen with Magpie upscaling a chosen mode.
# Dot-source it, then call Restart-MagpieInMode / Capture-Upscaled (see README).
. (Join-Path $PSScriptRoot '..\TVModeCommon.ps1')
Add-Type -AssemblyName System.Drawing

$script:CfgPath = Join-Path $env:LOCALAPPDATA 'Magpie\config\v2\config.json'
$script:OutDir = Join-Path $PSScriptRoot 'captures'; New-Item -ItemType Directory -Force $script:OutDir | Out-Null

function Get-LaptopMonitor { [TVMode]::GetMonitors() | Where-Object { $_.Primary } | Select-Object -First 1 }

function Get-ComicWindow {
    $procs = Get-BrowserProcesses -ExePath (Get-DefaultBrowserExe)
    $pidSet = New-Object 'System.Collections.Generic.HashSet[uint32]'; foreach ($p in $procs) { [void]$pidSet.Add([uint32]$p.Id) }
    $mon = Get-LaptopMonitor
    [TVMode]::GetTopLevelWindowsForProcesses($pidSet) | Where-Object { $_.Left -eq $mon.Left -and $_.Top -eq $mon.Top -and $_.Right -eq $mon.Right -and $_.Bottom -eq $mon.Bottom } | Select-Object -First 1
}

function Save-Screen([string]$name) {
    [TVMode]::EnsureDpiAware()
    $mon = Get-LaptopMonitor
    $bmp = New-Object System.Drawing.Bitmap $mon.Width, $mon.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($mon.Left, $mon.Top, 0, 0, $bmp.Size)
    $path = Join-Path $script:OutDir "$name.png"
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    return $path
}

function Restart-MagpieInMode([string]$modeName) {
    $running = @(Get-Process Magpie -ErrorAction SilentlyContinue); $running | Stop-Process -Force; foreach ($p in $running) { $p.WaitForExit(10000) | Out-Null }
    $cfg = Get-Content $script:CfgPath -Raw | ConvertFrom-Json
    $idx = [array]::IndexOf(($cfg.scalingModes | ForEach-Object { $_.name }), $modeName)
    if ($idx -lt 0) { throw "No mode named '$modeName'" }
    Set-MagpieDefaultScalingMode -ConfigPath $script:CfgPath -Index $idx
    & (Join-Path $PSScriptRoot '..\Start-MagpieHidden.ps1')
    if (-not (Wait-MagpieReady -TimeoutSeconds 15)) { throw "Magpie didn't start cleanly in '$modeName'" }
    $deadline = (Get-Date).AddSeconds(15)
    while (-not (Test-MagpieListening) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
}

# Upscale the comic window, wait for it to render, capture, switch upscaling off.
function Capture-Upscaled([string]$name, [int]$settleSeconds = 6) {
    $w = Get-ComicWindow
    if (-not $w) { throw 'Comic window is not fullscreen on the laptop screen.' }
    $mon = Get-LaptopMonitor
    if (-not (Start-MagpieScaling -Hwnd $w.Handle -Monitor $mon)) { throw "Upscaling didn't start for '$name'" }
    Start-Sleep -Seconds $settleSeconds
    $path = Save-Screen $name
    Assert-Focused -Hwnd $w.Handle
    [TVMode]::SendKeyCombo((Get-MagpieScaleHotkey).Keys)   # toggle back off
    Start-Sleep -Milliseconds 800
    return $path
}

function Focus-Claude {
    $c = Get-Process -Name Claude -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if ($c) { [void][TVMode]::Focus($c.MainWindowHandle) }
}
