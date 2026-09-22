<#
  Starts Magpie and hides its main window - fully hidden via SW_HIDE
  (excluded from the taskbar too), not just minimized.

  WinUI3 apps re-show/re-activate their window during their own async
  startup, which can undo a single early hide. So this keeps re-applying
  SW_HIDE for a few seconds after first detecting the window, until it
  stays hidden on its own.

  If Magpie is ALREADY running, this script leaves its window alone -
  in case you opened it on purpose from the tray icon.
#>

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Win {
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
}
'@ -ErrorAction SilentlyContinue

$SW_HIDE = 0
$magpieExe = Join-Path $PSScriptRoot '..\Magpie\Magpie.exe'

if (Get-Process Magpie -ErrorAction SilentlyContinue) { exit 0 }
if (-not (Test-Path $magpieExe)) { exit 1 }

Start-Process -FilePath $magpieExe

# Keep re-hiding for several seconds after the window first appears, to
# beat the app's own async startup re-showing itself. Stop once it has
# stayed hidden for a solid stretch, not just on the first success.
$deadline    = (Get-Date).AddSeconds(10)
$stableSince = $null
$requiredStableMs = 700

while ((Get-Date) -lt $deadline) {
    $p = Get-Process Magpie -ErrorAction SilentlyContinue
    if ($p -and $p.MainWindowHandle -ne [IntPtr]::Zero) {
        $hwnd = $p.MainWindowHandle
        if ([Win]::IsWindowVisible($hwnd)) {
            [void][Win]::ShowWindow($hwnd, $SW_HIDE)
            $stableSince = $null            # visibility fought back - reset the clock
        } else {
            if (-not $stableSince) { $stableSince = Get-Date }
            if (((Get-Date) - $stableSince).TotalMilliseconds -ge $requiredStableMs) {
                break                        # been hidden continuously - done
            }
        }
    }
    Start-Sleep -Milliseconds 80
}
