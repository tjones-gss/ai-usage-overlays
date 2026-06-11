@echo off
echo Installing Cursor Usage Overlay...
where pwsh >nul 2>nul
if %errorlevel%==0 (
    pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0cursor-overlay.ps1" -Install
) else (
    powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0cursor-overlay.ps1" -Install
)
echo.
echo Done. Look for the green "Cu" icon in your system tray.
echo.
pause
