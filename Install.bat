@echo off
setlocal enabledelayedexpansion
set "DEST=%LOCALAPPDATA%\CursorUsageOverlay"

echo Installing Cursor Usage Overlay...
echo.

:: Create or update destination directory
if not exist "%DEST%" mkdir "%DEST%"

:: Copy all overlay files to the stable install location
echo Copying files to %DEST%...
copy /Y "%~dp0cursor-overlay.ps1"      "%DEST%\" >nul
copy /Y "%~dp0sqlite3.exe"             "%DEST%\" >nul
copy /Y "%~dp0Start-CursorOverlay.vbs" "%DEST%\" >nul
copy /Y "%~dp0Install.bat"             "%DEST%\" >nul
copy /Y "%~dp0Uninstall.bat"           "%DEST%\" >nul

:: Run -Install from the destination so $PSScriptRoot = DEST
:: (the startup shortcut will point to DEST automatically)
where pwsh >nul 2>nul
if %errorlevel%==0 (
    echo Using PowerShell 7+
    pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%DEST%\cursor-overlay.ps1" -Install
) else (
    where powershell >nul 2>nul
    if !errorlevel!==0 (
        echo Using Windows PowerShell ^(built-in^)
        powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%DEST%\cursor-overlay.ps1" -Install
    ) else (
        echo ERROR: PowerShell not found.
        echo Windows 10/11 should have it built in. Run Windows Update or visit:
        echo https://github.com/PowerShell/PowerShell/releases
        pause
        exit /b 1
    )
)

echo.
echo Done. Look for the green "Cu" icon in your system tray.
echo Right-click it for options. It will start automatically on login.
echo.
pause
