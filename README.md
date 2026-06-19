# AI Usage Overlays

Always-on-top Windows HUDs that show live usage stats for Claude Code and Cursor IDE. Clone `master` to get both panels, or clone a specific branch for just one.

![Both overlays side by side](docs/preview.png)

## Branches

| Branch | What you get |
|---|---|
| **`master`** (this branch) | Both overlays — Claude + Cursor |
| [`claude`](../../tree/claude) | Claude Code overlay only |
| [`cursor`](../../tree/cursor) | Cursor IDE overlay only |

## What Each Overlay Shows

**Claude Code**
- 5-hour session %, weekly limit %, Sonnet %, overage spend, lifetime tokens

**Cursor IDE**
- On-demand spend (hero), included requests with OVER detection, agent edits, top model, sessions

## Requirements

- Windows 10/11 (PowerShell is built in — no separate install needed)
- Claude Code CLI signed in (`claude auth login`)
- Cursor IDE signed in

## Install

```bat
Install.bat
```

Registers a single login startup entry (`AIUsageOverlay.lnk`) and launches both panels immediately. Each overlay installs to its own `%LOCALAPPDATA%` folder.

## Usage

| Action | How |
|---|---|
| Show / hide Claude panel | Left-click the **C** tray icon |
| Show / hide Cursor panel | Left-click the **Cu** tray icon |
| Options, themes, opacity | Right-click either tray icon |
| Quit | Right-click → Quit |

Each overlay saves its own position, opacity, and theme independently.

## Uninstall

```bat
Uninstall.bat
```

## Features

- **Always on top** — stays visible over all other windows
- **4 color themes** — Global Shop, Deep Space, Ocean, Mono (right-click → Theme)
- **Drag to reposition** — position saved between restarts
- **Opacity control** — right-click → Opacity
- **Snap to corners** — right-click → Snap to corner
- **GSS branding** — Global Shop Solutions identity in the footer

## How It Works

Both overlays are PowerShell/WPF scripts that read auth tokens from local app storage and call the respective usage APIs with your existing session. No credentials stored separately, no elevated permissions required. Cursor stats are read from a bundled `sqlite3.exe` — no Python needed.
