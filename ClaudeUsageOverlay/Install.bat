@echo off
REM ============================================================
REM  Claude Usage Overlay - installer
REM  Adds login auto-start and launches the overlay to the tray.
REM ============================================================
echo Installing Claude Usage Overlay...
where pwsh >nul 2>nul
if %errorlevel%==0 (
    pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0overlay.ps1" -Install
) else (
    powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0overlay.ps1" -Install
)
echo.
echo Done. Look for the overlay at the top-right of your screen, and the
echo clay "C" icon in your system tray (click it to show/hide the overlay).
echo.
pause
