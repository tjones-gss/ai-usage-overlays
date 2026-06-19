@echo off
setlocal enabledelayedexpansion
set "DEST=%LOCALAPPDATA%\ClaudeUsageOverlay"
set "PIDFILE=%DEST%\overlay.pid"

echo Uninstalling Claude Usage Overlay...
echo.

if exist "%PIDFILE%" (
    set /p OVL_PID=<"%PIDFILE%"
    echo Stopping overlay process...
    taskkill /PID !OVL_PID! /F >nul 2>nul
    timeout /t 1 /nobreak >nul
)

if exist "%DEST%\overlay.ps1" (
    where pwsh >nul 2>nul
    if %errorlevel%==0 (
        pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%DEST%\overlay.ps1" -Uninstall
    ) else (
        powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%DEST%\overlay.ps1" -Uninstall
    )
)

if exist "%DEST%" (
    echo Removing installed files from %DEST%...
    rd /S /Q "%DEST%"
)

echo.
echo Claude Usage Overlay has been uninstalled.
echo.
pause
