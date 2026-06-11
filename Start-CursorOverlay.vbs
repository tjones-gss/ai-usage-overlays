Dim fso, dir, sh
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
Set sh = CreateObject("WScript.Shell")
sh.Run "pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "\cursor-overlay.ps1"" -Background", 0, False
