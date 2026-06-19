Dim fso, dir, sh, psExe
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
Set sh = CreateObject("WScript.Shell")

' Try pwsh (PowerShell 7+) first; fall back to powershell (5.1 built-in)
psExe = "pwsh"
If sh.Run("cmd /c where pwsh >nul 2>nul", 0, True) <> 0 Then
    psExe = "powershell"
End If

sh.Run psExe & " -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "\cursor-overlay.ps1"" -Background", 0, False
