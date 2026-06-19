@echo off
REM ============================================================
REM  AI Usage Overlay (Claude + Cursor) - uninstaller
REM ============================================================
echo Removing login auto-start...
where pwsh >nul 2>nul
if %errorlevel%==0 (
    pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0combined-overlay.ps1" -Uninstall
) else (
    powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0combined-overlay.ps1" -Uninstall
)
echo.
echo Auto-start removed. Right-click each tray icon and choose Quit to stop the overlays.
echo (Deleting this folder removes everything.)
echo.
pause
