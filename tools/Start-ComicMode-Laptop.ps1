<#
  Orchestrator behind START-COMIC-MODE.vbs (laptop-screen reading).
  Runs fully hidden. Before starting Magpie, it makes sure Magpie is set
  up with the best laptop settings, and fixes anything that isn't:

    - Scaling mode "AntiJaggy 8.5x NoSharp" is the active mode, and its
      effect chain matches the reference in magpie-scaling-modes-
      snapshot.json (restored from there if it's missing or was changed).
      The TV launcher switches Magpie to "TV 4K", and nothing used to
      switch it back - so laptop reading silently ran the TV chain.
    - No ONNX model.json is active in the Magpie folder (the AI models
      tried earlier were rejected; the shader chain is the chosen path).
    - Magpie.exe is pinned to the GTX 1650 (Windows' per-app GPU
      preference) - the laptop panel hangs off the Intel iGPU, and
      upscaling there would be far slower.
    - Magpie's config has no byte-order mark (Magpie refuses to start
      with one).

  Magpie is restarted only if a setting actually had to change, since it
  reads its config at startup and reverts edits made while running.

  If TV mode is running (its "4K" tray icon is up), this does nothing but
  warn: switching Magpie to the laptop chain would break the TV stream,
  and the laptop chain on a 3840px-wide source would blow past the 16384px
  GPU texture limit.
#>

. (Join-Path $PSScriptRoot 'TVModeCommon.ps1')

$ModeName = 'AntiJaggy 8.5x NoSharp'
$ReferencePath = Join-Path $PSScriptRoot '..\magpie-scaling-modes-snapshot.json'
$ConfigPath = Join-Path $env:LOCALAPPDATA 'Magpie\config\v2\config.json'
$MagpieDir = Join-Path $PSScriptRoot '..\Magpie'
$MagpieExe = (Resolve-Path (Join-Path $MagpieDir 'Magpie.exe')).Path
$GpuPrefKey = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
$HighPerformanceGpu = 'GpuPreference=2;'

function Show-LaptopModeWarning($message) {
    [System.Windows.Forms.MessageBox]::Show($message, 'Read Marvel Comics - Laptop Mode', 'OK', 'Warning') | Out-Null
}

if (Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*TVModeTray.ps1*' }) {
    Show-LaptopModeWarning "4K TV mode is running. Right-click its '4K' tray icon and choose Quit first, then start laptop mode again."
    exit 1
}

$changes = New-Object System.Collections.Generic.List[string]

# --- GPU preference (per-user app setting; takes effect on Magpie's next start) ---
$gpu = $null
try { $gpu = Get-ItemPropertyValue -Path $GpuPrefKey -Name $MagpieExe -ErrorAction Stop } catch { }
if ($gpu -ne $HighPerformanceGpu) {
    if (-not (Test-Path $GpuPrefKey)) { New-Item -Path $GpuPrefKey -Force | Out-Null }
    Set-ItemProperty -Path $GpuPrefKey -Name $MagpieExe -Value $HighPerformanceGpu
    $changes.Add('GPU preference')
}

# --- No ONNX model active ---
$modelJson = Join-Path $MagpieDir 'model.json'
$modelActive = Test-Path $modelJson

# --- Scaling mode: present, matching the reference, and active ---
$reference = (Get-Content $ReferencePath -Raw | ConvertFrom-Json).scalingModes | Where-Object { $_.name -eq $ModeName } | Select-Object -First 1
if (-not $reference) {
    Show-LaptopModeWarning "The reference settings file doesn't contain '$ModeName'. Nothing was changed."
    exit 1
}
$cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$index = -1
for ($i = 0; $i -lt $cfg.scalingModes.Count; $i++) { if ($cfg.scalingModes[$i].name -eq $ModeName) { $index = $i; break } }
$chainOk = $index -ge 0 -and
    (($cfg.scalingModes[$index] | ConvertTo-Json -Depth 20 -Compress) -eq ($reference | ConvertTo-Json -Depth 20 -Compress))
$modeActive = $index -ge 0 -and $cfg.profiles[0].scalingMode -eq $index
$hasBom = Test-FileHasUtf8Bom $ConfigPath

if ($modelActive -or -not $chainOk -or -not $modeActive -or $hasBom) {
    $running = @(Get-Process Magpie -ErrorAction SilentlyContinue)
    if ($running) {
        # Magpie reverts config edits made while it's running, so stop it
        # first - and wait until it's really gone.
        $running | Stop-Process -Force
        foreach ($p in $running) { $p.WaitForExit(10000) | Out-Null }
    }

    if ($modelActive) {
        Move-Item $modelJson (Join-Path $MagpieDir "model.json.disabled-$(Get-Date -Format yyyyMMdd-HHmmss)")
        $changes.Add('ONNX model disabled')
    }

    if (-not $chainOk) {
        # Rare path (the chain was changed or lost): rewrite the whole file.
        # Written without a BOM, which Magpie rejects.
        if ($index -ge 0) { $cfg.scalingModes[$index] = $reference }
        else { $cfg.scalingModes = @($cfg.scalingModes) + $reference; $index = $cfg.scalingModes.Count - 1 }
        $cfg.profiles[0].scalingMode = $index
        [System.IO.File]::WriteAllText($ConfigPath, ($cfg | ConvertTo-Json -Depth 20), (New-Object System.Text.UTF8Encoding($false)))
        $changes.Add("'$ModeName' chain restored")
    } elseif (-not $modeActive -or $hasBom) {
        # Common path: just switch the active mode, leaving the rest of
        # Magpie's file untouched.
        Set-MagpieDefaultScalingMode -ConfigPath $ConfigPath -Index $index
        $changes.Add("'$ModeName' made active")
    }

    $verify = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    if ($verify.scalingModes[$verify.profiles[0].scalingMode].name -ne $ModeName -or (Test-FileHasUtf8Bom $ConfigPath)) {
        Show-LaptopModeWarning "Tried to switch Magpie to '$ModeName', but it didn't stick on readback."
        exit 1
    }
}

$startedMagpie = -not (Get-Process Magpie -ErrorAction SilentlyContinue)
& (Join-Path $PSScriptRoot 'Start-MagpieHidden.ps1')
if ($startedMagpie -and -not (Wait-MagpieReady -TimeoutSeconds 30)) {
    Show-LaptopModeWarning "Magpie started but is showing an error instead of running, so nothing will be upscaled. Its log is in E:\ComicUpscale\Magpie\logs\magpie.log."
}

$logLine = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') laptop mode: " + $(if ($changes.Count) { "fixed: $($changes -join ', ')" } else { 'all settings already correct' })
try { Add-Content -Path (Join-Path $PSScriptRoot 'laptop-mode.log') -Value $logLine -Encoding ASCII } catch { }
