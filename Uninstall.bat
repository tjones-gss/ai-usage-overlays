@echo off
REM ============================================================
REM  Unified AI Usage Overlay - uninstaller
REM ============================================================
echo Removing login auto-start...
set "PS_EXE="
if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" set "PS_EXE=%ProgramFiles%\PowerShell\7\pwsh.exe"
if not defined PS_EXE if exist "%ProgramFiles(x86)%\PowerShell\7\pwsh.exe" set "PS_EXE=%ProgramFiles(x86)%\PowerShell\7\pwsh.exe"
if not defined PS_EXE if exist "%LocalAppData%\Microsoft\WindowsApps\pwsh.exe" set "PS_EXE=%LocalAppData%\Microsoft\WindowsApps\pwsh.exe"
if not defined PS_EXE (
    where pwsh >nul 2>nul && set "PS_EXE=pwsh"
)
if not defined PS_EXE (
    set "PS_EXE=powershell.exe"
)
"%PS_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0unified-overlay.ps1" -Uninstall

if exist "%~dp0unified-overlay.pid" (
    echo Stopping running overlay...
    for /f "usebackq" %%p in ("%~dp0unified-overlay.pid") do taskkill /PID %%p /T /F >nul 2>nul
    del "%~dp0unified-overlay.pid" >nul 2>nul
)
echo.
echo Auto-start removed. The unified overlay has been stopped if it was running.
echo (Deleting this folder removes everything.)
echo.
pause
