# Cursor Usage Overlay

Always-on-top Windows HUD for Cursor IDE usage. Shows live request counts and on-demand spend from your Cursor account.

## What It Shows

- **Included requests** — used / limit with OVER alert when exceeded, reset countdown
- **On-demand spend** — dollars charged beyond included requests this billing cycle
- **Agent edits** — all-time and today's edits from local tracking database
- **Top model** — most-used model with usage percentage
- **Sessions** — total conversation count

## Requirements

- Windows 10/11
- PowerShell 7+
- Python 3 (reads Cursor's SQLite databases)
- Cursor IDE installed and signed in

## Install

```bat
Install.bat
```

Registers a login startup shortcut and starts the overlay immediately.

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
