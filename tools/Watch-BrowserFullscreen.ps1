<#
  One-shot background watcher, spawned by Start-ComicMode-TV.ps1 only when
  it couldn't find an already-open marvel.com/comics/issue tab and instead
  left a fresh "marvel0 " search box open on the laptop's own screen for
  you to finish typing into. Polls quietly (no visible window) until you
  press F11 on that browser, then moves the now-fullscreened window to the
  virtual 4K display and turns Magpie's upscaling on for it - then exits.

  Gives up quietly (no error, no popup) if the browser closes before that
  ever happens - nothing to do at that point, you clearly handled it
  yourself or changed your mind.
#>
param(
    [Parameter(Mandatory)][string]$BrowserExe
)

. (Join-Path $PSScriptRoot 'TVModeCommon.ps1')

$baseName = [System.IO.Path]::GetFileNameWithoutExtension($BrowserExe)
$maxRuntime = (Get-Date).AddHours(6)   # safety valve only, not an expected end state

while ((Get-Date) -lt $maxRuntime) {
    Start-Sleep -Milliseconds 600

    $procs = Get-Process -Name $baseName -ErrorAction SilentlyContinue
    if (-not $procs) { break }   # browser closed without ever fullscreening - nothing left to watch

    $fg = [TVMode]::GetForegroundWindowInfo()
    if (-not $fg -or ($fg.ProcessId -notin $procs.Id)) { continue }

    if (Test-WindowIsFullscreenOnItsMonitor -WinInfo $fg) {
        # No virtual display (e.g. Quit was used meanwhile) - nothing to do.
        $monitor = Get-VirtualDisplayMonitor
        if ($monitor) {
            Move-WindowToVirtualDisplayAndFullscreen -Hwnd $fg.Handle -Monitor $monitor
        }
        break
    }
}
