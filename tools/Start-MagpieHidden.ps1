<#
  Starts Magpie and hides its settings window - fully hidden via SW_HIDE
  (excluded from the taskbar too), not just minimized. Magpie's own tray
  icon stays available near the clock.

  How, and why this way:
    - Launched with Magpie's own "-t" switch (what its start-with-Windows
      option uses). Sometimes that brings the settings window up minimized
      rather than open, but it's not reliable (observed both), so nothing
      depends on it.
    - Hiding starts once Magpie has FINISHED starting up (its own tray icon
      window exists), and only hides the window when it's actually showing
      - no tight fight loop. An earlier version re-hid it every 80ms from
      the moment Magpie launched; that churn coincided with Magpie dropping
      out of upscaling.
    - Magpie re-shows its window once, somewhere in its first ~10-15s even
      after that (observed), so this keeps watching until the window has
      stayed hidden for a solid 5s and at least 15s have passed. After
      that a hide sticks (verified: no re-show in the following 20s).
    - Only ever touches the window of class "Magpie_Main" (the settings
      window). An earlier version hid whatever Windows reported as
      Magpie's "main window" - which, once upscaling starts, is Magpie's
      upscaling window itself (and, on a failed start, its error box).

  If Magpie is ALREADY running, this script leaves its window alone -
  in case you opened it on purpose from the tray icon.
#>

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Win {
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    // Window name deliberately an IntPtr, passed as IntPtr.Zero: PowerShell
    // turns $null into "" for a string argument, which makes FindWindow look
    // for an EMPTY title and never match Magpie's windows (observed - the
    // hide silently never happened).
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindow(string lpClassName, IntPtr lpWindowName);
    public static IntPtr FindByClass(string className) { return FindWindow(className, IntPtr.Zero); }
}
'@ -ErrorAction SilentlyContinue

$SW_HIDE = 0
$SETTINGS_WINDOW_CLASS = 'Magpie_Main'
$TRAY_ICON_WINDOW_CLASS = 'Magpie_NotifyIcon'   # exists once Magpie is fully up
$magpieExe = Join-Path $PSScriptRoot '..\Magpie\Magpie.exe'

if (Get-Process Magpie -ErrorAction SilentlyContinue) { exit 0 }
if (-not (Test-Path $magpieExe)) { exit 1 }

$launchedAt = Get-Date
Start-Process -FilePath $magpieExe -ArgumentList '-t'

# Wait for Magpie to finish starting (or give up quietly - e.g. if it hit
# a startup error, its error box must stay visible, and this never touches
# that anyway).
$deadline = (Get-Date).AddSeconds(20)
while ([Win]::FindByClass($TRAY_ICON_WINDOW_CLASS) -eq [IntPtr]::Zero -and (Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 200
}

$deadline = (Get-Date).AddSeconds(30)
$hiddenSince = $null
while ((Get-Date) -lt $deadline) {
    $hwnd = [Win]::FindByClass($SETTINGS_WINDOW_CLASS)
    if ($hwnd -ne [IntPtr]::Zero -and [Win]::IsWindowVisible($hwnd)) {
        [void][Win]::ShowWindow($hwnd, $SW_HIDE)
        $hiddenSince = $null
    } elseif (-not $hiddenSince) {
        $hiddenSince = Get-Date
    }
    if ($hiddenSince -and ((Get-Date) - $hiddenSince).TotalSeconds -ge 5 -and ((Get-Date) - $launchedAt).TotalSeconds -ge 15) { break }
    Start-Sleep -Milliseconds 250
}
