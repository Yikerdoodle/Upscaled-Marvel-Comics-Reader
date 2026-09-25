<#
  One-shot background watcher, spawned by Start-ComicMode-TV.ps1 only when
  it couldn't find an already-open marvel.com/comics/issue tab and instead
  left a "marvel0 " search box open on the laptop's own screen for you to
  finish typing into.

  Shows a small always-on-top reminder (bottom-right, never takes keyboard
  focus away from the browser - see TVModePrompt.cs), then waits for you
  to press F11 in that browser. The moment it goes fullscreen, the
  reminder closes and the window moves to the virtual 4K display with
  Magpie's upscaling turned on. Dismissing the reminder with its x only
  hides the message - the F11 watching carries on.

  Exits quietly if the browser closes before that ever happens. The tray
  icon's Quit also ends this process (and so the reminder).
#>
param(
    [Parameter(Mandatory)][string]$BrowserExe,
    [switch]$SearchTyped
)

. (Join-Path $PSScriptRoot 'TVModeCommon.ps1')
Add-Type -Path (Join-Path $PSScriptRoot 'TVModePrompt.cs') -ReferencedAssemblies System.Windows.Forms, System.Drawing -WarningAction SilentlyContinue -ErrorAction Stop

# Create the reminder while this thread is system-DPI-aware so it renders
# sharp at the laptop's display scaling. The geometry checks below switch
# the thread to per-monitor awareness afterward, which doesn't affect an
# already-created window.
[TVMode]::UseSystemDpiAwareness()
$body = if ($SearchTyped) {
    "Your marvel0 search is waiting in your browser. Open the issue you want, then press F11 once you're on the reading page - it'll jump to the TV and upscale automatically."
} else {
    "Open the issue you want in your browser, then press F11 once you're on the reading page - it'll jump to the TV and upscale automatically."
}
$prompt = New-Object TVModePrompt('Ready when you are', $body)
$prompt.Show()

$baseName = [System.IO.Path]::GetFileNameWithoutExtension($BrowserExe)
$maxRuntime = (Get-Date).AddHours(6)   # safety valve only, not an expected end state

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 600
$timer.add_Tick({
    $procs = Get-Process -Name $baseName -ErrorAction SilentlyContinue
    if (-not $procs -or (Get-Date) -gt $maxRuntime) {
        # Browser closed without ever going fullscreen - nothing left to do.
        $timer.Stop()
        [System.Windows.Forms.Application]::Exit()
        return
    }

    $fg = [TVMode]::GetForegroundWindowInfo()
    if (-not $fg -or ($fg.ProcessId -notin $procs.Id)) { return }

    if (Test-WindowIsFullscreenOnItsMonitor -WinInfo $fg) {
        $timer.Stop()
        if (-not $prompt.IsDisposed) { $prompt.Close() }
        # No virtual display (e.g. it was switched off meanwhile) - nothing to move to.
        $monitor = Get-VirtualDisplayMonitor
        if ($monitor) {
            try { Move-WindowToVirtualDisplayAndFullscreen -Hwnd $fg.Handle -Monitor $monitor } catch { }
        }
        [System.Windows.Forms.Application]::Exit()
    }
})
$timer.Start()

[System.Windows.Forms.Application]::Run()

$timer.Dispose()
if (-not $prompt.IsDisposed) { $prompt.Dispose() }
