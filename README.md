# AI Usage Overlays

Always-on-top Windows HUDs that show live usage stats for Claude Code and Cursor IDE. Both overlays sit in the system tray and display a compact panel you can drag anywhere on screen.

![Both overlays side by side](docs/preview.png)

## Overlays

Each overlay lives on its own branch — clone only what you need.

| Overlay | Branch | Shows |
|---|---|---|
| **Claude Code** | [`claude`](../../tree/claude) | 5-hour session %, weekly limit %, Sonnet %, overage spend, lifetime tokens |
| **Cursor IDE** | [`cursor`](../../tree/cursor) | Included requests (with OVER detection), on-demand spend, agent edits, top model |

## Requirements

- Windows 10/11 (PowerShell is built in — no separate install needed)
- Cursor overlay: Cursor IDE signed in
- Claude overlay: Claude Code CLI signed in (`claude auth login`)

## Quick Install

Clone the branch for the overlay you want, then run `Install.bat`.

```
# Claude overlay
git clone -b claude https://github.com/tjones-gss/ai-usage-overlays.git ClaudeUsageOverlay
ClaudeUsageOverlay\Install.bat

# Cursor overlay
git clone -b cursor https://github.com/tjones-gss/ai-usage-overlays.git CursorUsageOverlay
CursorUsageOverlay\Install.bat
```

## Features

- **Always on top** — stays visible over all other windows
- **System tray icon** — left-click to show/hide, right-click for menu
- **4 color themes** — Global Shop, Deep Space, Ocean, Mono (right-click → Theme)
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

Run `Uninstall.bat` from `%LOCALAPPDATA%\CursorUsageOverlay` or `%LOCALAPPDATA%\ClaudeUsageOverlay`, or right-click the tray icon → Quit.
