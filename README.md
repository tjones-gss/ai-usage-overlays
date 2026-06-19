# Cursor Usage Overlay

Always-on-top Windows HUD for Cursor IDE usage. Shows live request counts and on-demand spend from your Cursor account.

## What It Shows

- **Included requests** — used / limit with OVER alert when exceeded, reset countdown
- **On-demand spend** — dollars charged beyond included requests this billing cycle
- **Agent edits** — all-time and today's edits from local tracking database
- **Top model** — most-used model with usage percentage
- **Sessions** — total conversation count

## Requirements

- Windows 10/11 (PowerShell is built in — no separate install needed)
- Cursor IDE installed and signed in

## Install

### Option A — Download zip (recommended for internal use)

1. Download `CursorUsageOverlay.zip` from the internal link
2. Extract anywhere (e.g. Downloads)
3. Run `Install.bat`

The installer copies everything to `%LOCALAPPDATA%\CursorUsageOverlay` and
registers a login startup shortcut. You can delete the zip and extracted folder
after install.

### Option B — One-liner (when hosted on an internal URL)

```powershell
iwr -useb https://<internal-url>/install.ps1 | iex
```

## Uninstall

Run `Uninstall.bat` from `%LOCALAPPDATA%\CursorUsageOverlay` (or the original
download folder — either works).

## Auth

Reads your session token from Cursor's local SQLite database at:
```
%APPDATA%\Cursor\User\globalStorage\state.vscdb
```
No separate login required — uses your existing Cursor session.

## APIs Used

| Endpoint | Data |
|---|---|
| `cursor.com/api/usage` | Included request count and limit |
| `cursor.com/api/usage-summary` | On-demand spend in cents |

Both are called with your existing Cursor session cookie. Refreshes every 5 minutes.

Local agent edit stats are read from `~\.cursor\ai-tracking\ai-code-tracking.db`.
