# AI Usage Overlay — Combined (Claude + Cursor)

Runs both the Claude Code and Cursor usage overlays in a single process. Each overlay gets its own always-on-top panel and system-tray icon. For people who use both subscriptions.

![Both overlays side by side](docs/preview.png)

For standalone installs see the [`claude`](../../tree/claude) or [`cursor`](../../tree/cursor) branch.

## Requirements

- Windows 10/11 (PowerShell is built in — no separate install needed)
- Claude Code CLI signed in (`claude auth login`)
- Cursor IDE signed in

## Install

```bat
Install.bat
```

Registers a single login startup entry and launches both overlays immediately.

## Usage

| Action | How |
|---|---|
| **Show / hide Claude panel** | Left-click the **C** tray icon |
| **Show / hide Cursor panel** | Left-click the **Cu** tray icon |
| **Options for each overlay** | Right-click its tray icon or panel |
| **Quit both** | Right-click either tray icon → Quit (exits that overlay only) |

Each overlay saves its own position, opacity, and theme independently.

## Uninstall

```bat
Uninstall.bat
```

Then right-click each tray icon and choose **Quit**.

## How it works

`combined-overlay.ps1` starts `overlay.ps1` and `cursor-overlay.ps1` each in a dedicated STA thread (runspace) so they run with full isolation — separate WPF dispatchers, separate tray icons, no shared state.
