# Claude Usage Overlay

Always-on-top Windows HUD for Claude Code usage. Shows live limits from `claude.ai/settings/limits`.

![Claude overlay](docs/preview.png)

## What It Shows

- **5-hour session** — % used with time-to-reset countdown
- **Weekly limit** — % used with days-to-reset
- **Fable weekly** — % used, the weekly cap for the Fable model
- **Opus weekly** — shown only when you have Opus usage
- **Est. cost** — API-equivalent value of all usage (informational; not charged on flat-rate plans)
- **Overage** — real spend beyond your plan limit, if usage-based billing is enabled
- **Tokens** — all-time input / output token counts
- **Lifetime** — total sessions and messages

## Requirements

- Windows 10/11
- PowerShell 7+
- Claude Code CLI logged in (`claude auth login`)

## Install

```bat
Install.bat
```

Registers a login startup shortcut and starts the overlay immediately.

## Auth

Reads your access token from `~\.claude\.credentials.json` (written by `claude auth login`). No separate login required.

## API

Calls `https://api.anthropic.com/api/oauth/usage` with your OAuth token. Refreshes every 3 minutes.
Local stats (tokens, sessions, messages) are read from `~\.claude\stats-cache.json` which Claude Code updates periodically.

## Uninstall

```bat
Uninstall.bat
```
