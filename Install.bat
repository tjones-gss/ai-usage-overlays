@echo off
REM ============================================================
REM  Unified AI Usage Overlay - installer
REM  Adds login auto-start and launches the unified overlay.
REM ============================================================
echo Installing unified AI Usage Overlay...
where pwsh >nul 2>nul
if errorlevel 1 (
    echo PowerShell 7 ^(pwsh^) is required.
    echo Install PowerShell 7, then run this installer again.
    echo.
    pause
    exit /b 1
)
pwsh -STA -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0unified-overlay.ps1" -Install
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
