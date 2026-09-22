<#
.SYNOPSIS
  Sizes a browser window so its CLIENT AREA is an exact number of REAL screen
  pixels, so Magpie gets a clean integer upscale factor.

.DESCRIPTION
  Two things make this fiddly by hand, and both are handled here:

    1. Window chrome. Dragging a window to "960x540" sizes the OUTER frame.
       The content area ends up smaller by the title bar and borders, so your
       upscale factor is never the integer you wanted. This measures the
       chrome delta and compensates.

    2. DPI scaling. This machine runs at 150%, so a process that is not
       DPI-aware has its coordinates silently multiplied by 1.5 by Windows.
       This script declares itself per-monitor DPI-aware first, so every
       number below is a true device pixel.

  Magpie also refuses to scale a maximised window, so this restores it first.

.EXAMPLE
  .\Set-ReaderWindow.ps1 -Width 960 -Height 540 -Center
  Exact 2x to a 1920x1080 screen. Pair with a 2x upscaling model.

.EXAMPLE
  .\Set-ReaderWindow.ps1 -Width 640 -Height 360 -Center
  Exact 3x. More work for the model, less for the browser's bilinear filter.

.EXAMPLE
  .\Set-ReaderWindow.ps1 -Width 480 -Height 270 -Center -Process chrome
  Exact 4x. Pair with a 4x model. Reader UI may go mobile at this size.
#>
[CmdletBinding()]
param(
    [int]   $Width   = 960,
    [int]   $Height  = 540,
    [string]$Process = 'firefox',
    [switch]$Center
)

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential)]
public struct RECT { public int Left, Top, Right, Bottom; }

public static class Win {
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int t, bool repaint);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern int  GetSystemMetrics(int i);
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
}
'@ -ErrorAction SilentlyContinue

# Per-monitor DPI aware v2 (-4). Falls back to system-DPI-aware on older builds.
try   { [void][Win]::SetProcessDpiAwarenessContext([IntPtr](-4)) }
catch { try { [void][Win]::SetProcessDPIAware() } catch { } }

$proc = Get-Process -Name $Process -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 } |
        Select-Object -First 1

if (-not $proc) {
    Write-Error "No visible '$Process' window found. Start it first, then re-run."
    exit 1
}
$h = $proc.MainWindowHandle

[void][Win]::ShowWindow($h, 9)          # SW_RESTORE - un-maximise
Start-Sleep -Milliseconds 200

# A browser in F11 fullscreen cannot be resized: SW_RESTORE does not exit it,
# because that is an application mode, not a window state. Detect it (the window
# exactly covers the screen AND has no chrome) and send F11 to leave it.
$probeW = New-Object RECT; $probeC = New-Object RECT
[void][Win]::GetWindowRect($h, [ref]$probeW)
[void][Win]::GetClientRect($h, [ref]$probeC)
$noChrome  = ((($probeW.Right - $probeW.Left) - ($probeC.Right - $probeC.Left)) -le 2)
$fillsScrn = (($probeW.Right - $probeW.Left) -ge [Win]::GetSystemMetrics(0)) -and `
             (($probeW.Bottom - $probeW.Top) -ge [Win]::GetSystemMetrics(1))
if ($noChrome -and $fillsScrn) {
    Write-Host "  detected F11 fullscreen - sending F11 to exit it..." -ForegroundColor Yellow
    [void][Win]::SetForegroundWindow($h)
    Start-Sleep -Milliseconds 250
    [Win]::keybd_event(0x7A, 0, 0, [UIntPtr]::Zero)          # F11 down
    [Win]::keybd_event(0x7A, 0, 2, [UIntPtr]::Zero)          # F11 up
    Start-Sleep -Milliseconds 900
    [void][Win]::ShowWindow($h, 9)
    Start-Sleep -Milliseconds 300
}

$wr = New-Object RECT
$cr = New-Object RECT
[void][Win]::GetWindowRect($h, [ref]$wr)
[void][Win]::GetClientRect($h, [ref]$cr)

$chromeW = ($wr.Right - $wr.Left) - ($cr.Right - $cr.Left)
$chromeH = ($wr.Bottom - $wr.Top) - ($cr.Bottom - $cr.Top)

$outerW = $Width  + $chromeW
$outerH = $Height + $chromeH

$x = $wr.Left
$y = $wr.Top
if ($Center) {
    $x = [int](([Win]::GetSystemMetrics(0) - $outerW) / 2)
    $y = [int](([Win]::GetSystemMetrics(1) - $outerH) / 2)
}

[void][Win]::MoveWindow($h, $x, $y, $outerW, $outerH, $true)
[void][Win]::SetForegroundWindow($h)

Start-Sleep -Milliseconds 150
[void][Win]::GetClientRect($h, [ref]$cr)
$gotW = $cr.Right - $cr.Left
$gotH = $cr.Bottom - $cr.Top

$screenW = [Win]::GetSystemMetrics(0)
$screenH = [Win]::GetSystemMetrics(1)

Write-Host ''
Write-Host ("  process       : {0} (pid {1})" -f $proc.ProcessName, $proc.Id)
Write-Host ("  chrome delta  : {0} x {1} px" -f $chromeW, $chromeH)
Write-Host ("  target client : {0} x {1} device px" -f $Width, $Height)
Write-Host ("  actual client : {0} x {1} device px" -f $gotW, $gotH) -ForegroundColor (
    $(if ($gotW -eq $Width -and $gotH -eq $Height) { 'Green' } else { 'Yellow' }))
Write-Host ("  screen        : {0} x {1}" -f $screenW, $screenH)
Write-Host ("  Magpie factor : {0:N2}x horizontal, {1:N2}x vertical" -f ($screenW / $gotW), ($screenH / $gotH))
Write-Host ''

if ($gotW -ne $Width -or $gotH -ne $Height) {
    Write-Warning "Browser clamped the size (it enforces a minimum window width). Try a larger target."
}
