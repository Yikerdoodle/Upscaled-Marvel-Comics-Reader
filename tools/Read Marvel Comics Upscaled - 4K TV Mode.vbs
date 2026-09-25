' Double-click this file. Nothing visible pops up - no console window.
'
' First, the "4K" tray icon appears (right-click > Quit tears everything
' back down). Then, in parallel, it silently: makes sure the virtual 4K
' display and Sunshine are both up (fixing them if needed, via a
' pre-approved elevated task - see 4K-TV-Setup/README.md), switches Magpie
' to its "TV 4K" scaling mode, and either jumps straight to an
' already-open marvel.com/comics/issue tab (moving+fullscreening it on the
' TV display) or preps a "marvel0 " search box on your laptop screen for
' you to finish - with an always-on-top reminder to press F11 when you're
' ready, which moves the window over to the TV the instant you do.
'
' A warning popup only appears if something couldn't be fixed automatically.

Dim shell, scriptDir
Set shell = CreateObject("WScript.Shell")
scriptDir = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)

Function PowerShellFile(name)
    PowerShellFile = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & _
                     scriptDir & "\" & name & """"
End Function

' The tray icon goes first, as its own process, so it shows up right away
' and stays responsive while the slower setup runs. If one is already
' there (repeat double-click), this second copy exits immediately.
shell.Run PowerShellFile("TVModeTray.ps1"), 0, False
shell.Run PowerShellFile("Start-ComicMode-TV.ps1"), 0, False
