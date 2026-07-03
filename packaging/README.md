# Packaging

This folder contains the first-pass Windows installer scaffolding for AI Usage Overlay.

## Current Behavior Captured

- Install target stays per-user at `%LOCALAPPDATA%\AIUsageOverlay`, matching `install.ps1`.
- Install copies the existing PowerShell app files, including `unified-overlay.ps1`, `Start-Unified.vbs`, `sqlite3.exe`, and `src\*.ps1`.
- Install verifies PowerShell 7 (`pwsh`) is available, then runs `unified-overlay.ps1 -Install`.
- `unified-overlay.ps1 -Install` creates or updates the Startup-folder shortcut at `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\AIUsageOverlay.lnk`.
- Startup and Start Menu launches use `wscript.exe Start-Unified.vbs`, which starts `pwsh` through `conhost.exe --headless` so no console window remains visible.
- Install and upgrade relaunch behavior is delegated to `unified-overlay.ps1 -Install`, which stops the previous background instance and starts a fresh hidden one.
- Uninstall removes the Startup shortcut by running `unified-overlay.ps1 -Uninstall`, then stops the running overlay by PID and command-line matching.
- Windows Apps & Features uninstall is provided by the Inno Setup uninstall entry.
- GitHub release updates use `AIUsageOverlaySetup.exe` from the latest release asset and hand off to the same installer path.

## Build Locally

Install Inno Setup 6, then run:

```powershell
pwsh -NoLogo -NoProfile -File packaging\build-installer.ps1
```

The setup executable is written to `dist\AIUsageOverlaySetup.exe`.
