' Launches the Claude Usage Overlay with no console window, hidden to the tray.
' Prefers PowerShell 7 (pwsh) when present, falls back to Windows PowerShell 5.1
' (powershell.exe) so it runs on any Windows 10/11 machine without PowerShell 7.
Dim fso, dir, sh

Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
Set sh = CreateObject("WScript.Shell")

' --- Locate a PowerShell interpreter ----------------------------------------
' pwsh.exe is not guaranteed; powershell.exe (5.1) is built into every Win10/11.
Function FindPwsh()
    Dim pf, pf86, candidates, i, p
    FindPwsh = ""
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

Dim psExe
psExe = FindPwsh()
If Len(psExe) = 0 Then psExe = "powershell.exe"   ' 5.1 fallback, always present

' --- Launch hidden via conhost --headless -----------------------------------
' conhost --headless is required: -WindowStyle Hidden alone is ignored by Windows Terminal.
sh.Run "conhost.exe --headless """ & psExe & """ -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "\overlay.ps1"" -Background", 0, False
