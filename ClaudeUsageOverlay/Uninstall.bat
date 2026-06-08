@echo off
REM ============================================================
REM  Claude Usage Overlay - uninstaller (removes login auto-start)
REM ============================================================
echo Removing login auto-start...
where pwsh >nul 2>nul
if %errorlevel%==0 (
    pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0overlay.ps1" -Uninstall
) else (
    powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0overlay.ps1" -Uninstall
)
echo.
echo Auto-start removed. To stop the overlay now, right-click its tray icon and choose Quit.
echo (Deleting this folder removes it completely.)
echo.
pause
