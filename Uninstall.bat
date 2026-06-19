@echo off
setlocal enabledelayedexpansion
set "DEST=%LOCALAPPDATA%\CursorUsageOverlay"
set "PIDFILE=%DEST%\cursor-overlay.pid"

echo Uninstalling Cursor Usage Overlay...
echo.

:: 1. Kill the running process using the PID file
if exist "%PIDFILE%" (
    set /p OVL_PID=<"%PIDFILE%"
    echo Stopping overlay process...
    taskkill /PID !OVL_PID! /F >nul 2>nul
    timeout /t 1 /nobreak >nul
)

:: 2. Remove the startup shortcut via the script's -Uninstall flag
if exist "%DEST%\cursor-overlay.ps1" (
    where pwsh >nul 2>nul
    if %errorlevel%==0 (
        pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%DEST%\cursor-overlay.ps1" -Uninstall
    ) else (
        powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%DEST%\cursor-overlay.ps1" -Uninstall
    )
)

:: 3. Remove the installed directory entirely
if exist "%DEST%" (
    echo Removing installed files from %DEST%...
    rd /S /Q "%DEST%"
)

echo.
echo Cursor Usage Overlay has been uninstalled.
echo.
pause
