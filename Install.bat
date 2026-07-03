@echo off
REM ============================================================
REM  Unified AI Usage Overlay - installer
REM  Adds login auto-start and launches the unified overlay.
REM ============================================================
echo Installing unified AI Usage Overlay...
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
"%PS_EXE%" -STA -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0unified-overlay.ps1" -Install
if errorlevel 1 (
    echo.
    echo Install failed. See unified-overlay-error.log for details.
    echo.
    pause
    exit /b 1
)
echo.
echo Done. The unified overlay is running in the system tray.
echo Left-click the AI tray icon to show or hide the panel.
echo.
pause
