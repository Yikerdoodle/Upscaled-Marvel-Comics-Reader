<#
  The "4K" tray icon for TV mode, and the one place that turns Magpie's
  upscaling on. Started by the launcher .vbs FIRST, before any setup
  work, as its own process - so the icon shows up immediately while the
  slower setup (virtual display, Sunshine, Magpie, browser) runs in
  parallel in Start-ComicMode-TV.ps1.

  Auto-upscale: every 1.5s it checks whether a browser window is
  fullscreen on the virtual 4K display with Magpie ready but not
  upscaling. If so, it presses Magpie's scale hotkey and confirms
  upscaling actually started.

  Magpie stops upscaling on its own whenever another window takes focus
  and overlaps the upscaled screen by 8px or more - and every maximized
  window on the laptop does (its invisible borders reach ~11px into the
  TV display next door at 150% scaling; Windows won't allow a gap between
  screens, so no layout avoids it). So after that kind of stop it turns
  upscaling back on: immediately if the comic window is in front again
  (e.g. you clicked it through Moonlight), or - taking focus itself -
  only once this PC has had no keyboard/mouse input for a while, i.e.
  you've headed down to the TV. It never takes focus from someone
  actively using the laptop.

  If you switch upscaling off yourself (Magpie's hotkey while the comic
  is in front), that's respected until the window or Magpie changes.

  Right-click > Quit tears TV mode back down: stops a launch that's still
  in progress and any F11 watcher (plus its on-screen reminder), closes
  Magpie, stops Sunshine and disables the virtual display (elevated), then
  sets Windows back to "PC screen only".

  A named mutex keeps it to one icon: a repeat double-click of the
  launcher starts this again, finds the icon already there, and exits.
#>

$mutex = New-Object System.Threading.Mutex($false, 'Global\ComicUpscaleTVModeTrayIcon')
if (-not $mutex.WaitOne(0)) { $mutex.Dispose(); exit 0 }

# Draw and show the icon before anything else, so it appears right away.
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$bmp = New-Object System.Drawing.Bitmap 32, 32
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([System.Drawing.Color]::FromArgb(255, 20, 20, 24))
$g.FillRectangle([System.Drawing.Brushes]::White, 2, 2, 28, 28)
$g.FillRectangle((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 20, 20, 24))), 4, 4, 24, 24)
$font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$g.DrawString('4K', $font, [System.Drawing.Brushes]::White, 2.0, 9.0)
$icon = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())

$trayIcon = New-Object System.Windows.Forms.NotifyIcon
$trayIcon.Icon = $icon
$trayIcon.Text = 'Marvel Comics - 4K TV Mode'
$trayIcon.Visible = $true

# Now the shared helpers (a second or two to load; the icon is already up).
. (Join-Path $PSScriptRoot 'TVModeCommon.ps1')
$browserExe = Get-DefaultBrowserExe

# --- Auto-upscale watch loop ---
# How long the PC must go without keyboard/mouse input before this will
# pull the comic window to the front itself to re-enable upscaling.
$IdleSecondsBeforeTakingFocus = 90

$script:UpscaleOffByUser = $null   # "<window>|<Magpie pid>" you switched off yourself
$script:UpscaleAttempts = 0
$script:WasUpscaling = $false
$script:ComicWasInFront = $false
$script:TrayLogPath = Join-Path $PSScriptRoot 'tv-mode-tray.log'

function Write-TrayLog([string]$message) {
    try { Add-Content -Path $script:TrayLogPath -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') $message" -Encoding ASCII } catch { }
}
Write-TrayLog "tray started (pid $PID), browser: $browserExe"

$upscaleTimer = New-Object System.Windows.Forms.Timer
$upscaleTimer.Interval = 1500
$upscaleTimer.add_Tick({
    try {
        $monitor = Get-VirtualDisplayMonitor
        $magpie = Get-Process Magpie -ErrorAction SilentlyContinue | Select-Object -First 1
        $window = if ($monitor) { Get-BrowserWindowOnMonitor -BrowserExe $browserExe -Monitor $monitor } else { $null }

        if (-not $window -or -not $magpie) {
            # Nothing on the TV display to upscale (or no Magpie) - reset.
            $script:UpscaleOffByUser = $null
            $script:UpscaleAttempts = 0
            $script:WasUpscaling = $false
            $script:ComicWasInFront = $false
            return
        }

        $key = "$($window.Handle)|$($magpie.Id)"
        if ($script:UpscaleOffByUser -and $script:UpscaleOffByUser -ne $key) { $script:UpscaleOffByUser = $null }

        $upscaling = Test-MagpieScalingOn -Monitor $monitor
        $comicInFront = ([TVMode]::GetForegroundWindowInfo()).Handle -eq $window.Handle

        # Went off while the comic stayed in front the whole time = you
        # pressed Magpie's hotkey yourself. (Magpie's own automatic stop
        # only happens when some OTHER window takes focus.)
        if ($script:WasUpscaling -and -not $upscaling) {
            if ($script:ComicWasInFront -and $comicInFront) {
                $script:UpscaleOffByUser = $key
                Write-TrayLog "upscaling switched off by you - leaving it off ($key)"
            } else {
                Write-TrayLog "upscaling stopped by Magpie (another window took focus) - will turn it back on ($key)"
            }
        }
        $script:WasUpscaling = $upscaling
        $script:ComicWasInFront = $comicInFront

        if ($upscaling) { $script:UpscaleAttempts = 0; return }
        if ($script:UpscaleOffByUser -eq $key) { return }

        # Still starting up: windows not there yet, or hotkey not registered
        # yet (presses sent before that are silently lost) - try next tick.
        if (-not (Wait-MagpieReady -TimeoutSeconds 0)) { return }
        if (-not (Test-MagpieListening)) { return }

        # Magpie's hotkey acts on the window in front. Bring the comic
        # forward only if it's already there, or nobody's been using this PC
        # for a while - never out from under someone using the laptop.
        $idle = [TVMode]::GetIdleSeconds()
        if (-not $comicInFront -and $idle -lt $IdleSecondsBeforeTakingFocus) { return }

        $script:UpscaleAttempts++
        $magpieAge = [int]((Get-Date) - $magpie.StartTime).TotalSeconds
        $ok = Start-MagpieScaling -Hwnd $window.Handle -Monitor $monitor
        Write-TrayLog "attempt $($script:UpscaleAttempts) ($key, Magpie up ${magpieAge}s, idle $([int]$idle)s, comic was in front: $comicInFront): upscaling on=$ok, focus: $([TVMode]::LastFocusDiagnostic)"
        if ($ok) {
            $script:UpscaleAttempts = 0
            $script:WasUpscaling = $true
            $script:ComicWasInFront = $true
        } elseif ($script:UpscaleAttempts -ge 3) {
            # Stop pressing a toggle blindly; picks up again if the window
            # or Magpie changes.
            Write-TrayLog "giving up for $key"
            $script:UpscaleOffByUser = $key
            $script:UpscaleAttempts = 0
        }
    } catch {
        Write-TrayLog "error: $($_.Exception.Message)"
    }
})
$upscaleTimer.Start()

# --- Quit ---
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$quitItem = New-Object System.Windows.Forms.ToolStripMenuItem 'Quit'
$quitItem.add_Click({
    $upscaleTimer.Stop()
    $trayIcon.Visible = $false

    # First, anything that could otherwise re-enable things after the
    # teardown below: a launch still mid-setup, and the F11 watcher.
    Stop-TVModeHelperProcesses -ScriptNames 'Start-ComicMode-TV.ps1', 'Watch-BrowserFullscreen.ps1'

    Get-Process Magpie -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    # Stops Sunshine, then disables the virtual display - both need admin
    # rights, so they go through the same silent elevated task. Usually
    # ~5s; the generous wait (the icon is already gone, so it costs
    # nothing visible) keeps "PC screen only" reliably AFTER the display
    # is disabled.
    try { $null = Invoke-ElevatedAction 'teardown' 90 } catch { }

    # Then back to "PC screen only". Passing /internal when it's already
    # the active mode is a harmless no-op, so this doubles as the "check,
    # and fix only if needed" step.
    & $script:TVDisplaySwitchExe /internal

    [System.Windows.Forms.Application]::Exit()
})
[void]$menu.Items.Add($quitItem)
$trayIcon.ContextMenuStrip = $menu

[System.Windows.Forms.Application]::Run()

$upscaleTimer.Dispose()
$trayIcon.Visible = $false
$trayIcon.Dispose()
$mutex.ReleaseMutex()
$mutex.Dispose()
