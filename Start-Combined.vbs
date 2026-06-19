' Detached launcher for the combined AI Usage Overlay (Claude + Cursor).
' Detects PowerShell 7 (pwsh); falls back to Windows PowerShell 5.1.
Dim objShell, objFso, pwsh, scriptPath, args

Set objShell = CreateObject("WScript.Shell")
Set objFso   = CreateObject("Scripting.FileSystemObject")

scriptPath = """" & Replace(WScript.ScriptFullName, "Start-Combined.vbs", "combined-overlay.ps1") & """"

Dim pwshPaths(2)
pwshPaths(0) = "C:\Program Files\PowerShell\7\pwsh.exe"
pwshPaths(1) = objShell.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\Microsoft\WindowsApps\pwsh.exe"
pwshPaths(2) = "C:\Program Files\PowerShell\7-preview\pwsh.exe"

pwsh = "powershell.exe"
Dim i
For i = 0 To UBound(pwshPaths)
    If objFso.FileExists(pwshPaths(i)) Then
        pwsh = """" & pwshPaths(i) & """"
        Exit For
    End If
Next

args = " -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -File " & scriptPath & " -Background"
objShell.Run pwsh & args, 0, False
