@echo off
where pwsh >nul 2>nul
if %errorlevel%==0 (
    pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0cursor-overlay.ps1" -Uninstall
) else (
    powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0cursor-overlay.ps1" -Uninstall
)
echo Uninstalled. You can delete this folder.
pause
