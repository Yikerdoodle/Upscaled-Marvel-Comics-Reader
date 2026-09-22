' Double-click this file. Nothing visible pops up - no console window.
' It silently: makes sure the virtual 4K display and Sunshine are both up
' (fixing them if needed, via a pre-approved elevated task - see
' 4K-TV-Setup/README.md for the one-time setup that makes that silent),
' switches Magpie to its "TV 4K" scaling mode, and either jumps straight
' to an already-open marvel.com/comics/issue tab (moving+fullscreening it
' on the TV display) or preps a "marvel0 " search box on your laptop
' screen for you to finish - in which case it also starts watching in the
' background for you to press F11 yourself, and moves the window over to
' the TV the instant you do.
'
' A warning popup only appears if something couldn't be fixed automatically.

Dim shell, scriptDir
Set shell = CreateObject("WScript.Shell")
scriptDir = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)

Dim cmd
cmd = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & _
      scriptDir & "\Start-ComicMode-TV.ps1"""

shell.Run cmd, 0, False
