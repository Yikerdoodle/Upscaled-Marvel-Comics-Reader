' Double-click this file. Nothing visible pops up - no console window, no
' Magpie window, nothing in the taskbar. Magpie's tray icon still appears
' near the clock as usual; right-click it any time for Settings or Exit.
'
' Before starting Magpie it checks Magpie is on the best laptop settings
' ("AntiJaggy 8.5x NoSharp", GPU pinned to the GTX 1650, no AI model) and
' quietly fixes anything that isn't - e.g. after using 4K TV mode.
'
' Routine once it's running: put Firefox in FULLSCREEN (F11), click the
' Firefox window, press Win+Shift+A to toggle upscaling on/off.

Dim shell, scriptDir
Set shell = CreateObject("WScript.Shell")
scriptDir = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)

Dim cmd
cmd = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & _
      scriptDir & "\Start-ComicMode-Laptop.ps1"""

' windowStyle 0 = hidden, waitOnReturn False = return immediately, don't
' block the double-click. Belt-and-suspenders with -WindowStyle Hidden
' above: this is what actually guarantees zero visible console flash.
shell.Run cmd, 0, False
