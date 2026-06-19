@echo off
setlocal enabledelayedexpansion
set "DEST=%LOCALAPPDATA%\ClaudeUsageOverlay"

echo Installing Claude Usage Overlay...
echo.

if not exist "%DEST%" mkdir "%DEST%"

echo Copying files to %DEST%...
copy /Y "%~dp0overlay.ps1"          "%DEST%\" >nul
copy /Y "%~dp0Start-Overlay.vbs"    "%DEST%\" >nul
copy /Y "%~dp0Install.bat"          "%DEST%\" >nul
copy /Y "%~dp0Uninstall.bat"        "%DEST%\" >nul
if exist "%~dp0src" xcopy /E /Y /Q "%~dp0src\" "%DEST%\src\" >nul

where pwsh >nul 2>nul
if %errorlevel%==0 (
    echo Using PowerShell 7+
    pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%DEST%\overlay.ps1" -Install
) else (
    where powershell >nul 2>nul
    if !errorlevel!==0 (
        echo Using Windows PowerShell ^(built-in^)
        powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%DEST%\overlay.ps1" -Install
    ) else (
        echo ERROR: PowerShell not found.
        pause
        exit /b 1
    )
)

echo.
echo Done. Look for the Claude overlay in your system tray.
echo Right-click it for options. It will start automatically on login.
echo.
pause
