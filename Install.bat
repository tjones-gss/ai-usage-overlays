@echo off
echo Installing Cursor Usage Overlay...
echo.

where pwsh >nul 2>nul
if %errorlevel%==0 (
    echo Using PowerShell 7+
    pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0cursor-overlay.ps1" -Install
) else (
    where powershell >nul 2>nul
    if %errorlevel%==0 (
        echo Using Windows PowerShell ^(built-in^)
        powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0cursor-overlay.ps1" -Install
    ) else (
        echo ERROR: PowerShell not found. Windows 10/11 should have it built in.
        echo Please run Windows Update or install PowerShell from:
        echo https://github.com/PowerShell/PowerShell/releases
        pause
        exit /b 1
    )
)

echo.
echo Done. Look for the green "Cu" icon in your system tray.
echo.
pause
