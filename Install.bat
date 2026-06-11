@echo off
REM ============================================================
REM  AI Usage Overlay (Claude + Cursor) - installer
REM  Adds login auto-start and launches both overlays.
REM ============================================================
echo Installing AI Usage Overlay (Claude + Cursor)...
where pwsh >nul 2>nul
if %errorlevel%==0 (
    pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0combined-overlay.ps1" -Install
) else (
    powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0combined-overlay.ps1" -Install
)
echo.
echo Done. Both overlays are running in the system tray.
echo Left-click the C or Cu tray icon to show/hide each panel.
echo.
pause
