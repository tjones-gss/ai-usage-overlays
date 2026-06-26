@echo off
REM ============================================================
REM  Unified AI Usage Overlay - uninstaller
REM ============================================================
echo Removing login auto-start...
where pwsh >nul 2>nul
if errorlevel 1 (
    echo PowerShell 7 (pwsh) is required.
    echo.
    pause
    exit /b 1
)
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0unified-overlay.ps1" -Uninstall

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
