' Launches the unified AI Usage Overlay with no console window.
' Requires PowerShell 7 (pwsh).
Dim fso, dir, sh

Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
Set sh = CreateObject("WScript.Shell")

Function FindPwsh()
    Dim candidates, i, p
    FindPwsh = "pwsh.exe"
    candidates = Array( _
        sh.ExpandEnvironmentStrings("%ProgramFiles%\PowerShell\7\pwsh.exe"), _
        sh.ExpandEnvironmentStrings("%ProgramFiles(x86)%\PowerShell\7\pwsh.exe"), _
        sh.ExpandEnvironmentStrings("%LocalAppData%\Microsoft\WindowsApps\pwsh.exe"))
    For i = 0 To UBound(candidates)
        p = candidates(i)
        If Len(p) > 0 And fso.FileExists(p) Then
            FindPwsh = p
            Exit Function
        End If
    Next
End Function

sh.Run "conhost.exe --headless """ & FindPwsh() & """ -STA -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -File """ & dir & "\unified-overlay.ps1"" -Background", 0, False
