# AI Usage Overlays

Always-on-top Windows HUDs that show live usage stats for Claude Code and Cursor IDE. Both overlays sit in the system tray and display a compact panel you can drag anywhere on screen.

![Both overlays side by side](docs/preview.png)

## Overlays

| Overlay | Shows |
|---|---|
| **[ClaudeUsageOverlay](ClaudeUsageOverlay/)** | 5-hour session %, weekly limit %, Sonnet %, overage spend, lifetime tokens |
| **[CursorUsageOverlay](CursorUsageOverlay/)** | Included requests (with OVER detection), on-demand spend, agent edits, top model |

## Requirements

- Windows 10/11
- PowerShell 7+ (`winget install Microsoft.PowerShell`)
- Python 3 (for reading SQLite databases — usually already installed)

## Quick Install

Run `Install.bat` inside each overlay folder. It registers a login startup shortcut and launches immediately.

```
ClaudeUsageOverlay\Install.bat
CursorUsageOverlay\Install.bat
```

## Features

- **Always on top** — stays visible over all other windows
- **System tray icon** — left-click to show/hide, right-click for menu
- **4 color themes** — Cursor Green, Deep Space, Neon, Mono (right-click → Theme)
- **Drag to reposition** — position is saved between restarts
- **Opacity control** — right-click → Opacity
- **Snap to corners** — right-click → Snap to corner
- **Single-instance guard** — PID file prevents duplicate tray icons

## How It Works

Both overlays are standalone PowerShell scripts that:
1. Read auth tokens from local app storage (no credentials stored separately)
2. Call the respective usage APIs with your existing session cookie
3. Display data in a WPF window with WinForms tray icon

No external dependencies, no installers, no elevated permissions required.

## Uninstall

```
ClaudeUsageOverlay\Uninstall.bat
```

Or right-click the tray icon → Quit, then delete the folder.
