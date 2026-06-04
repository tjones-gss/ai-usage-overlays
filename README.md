# Claude Usage Overlay

A tiny always-on-top desktop widget for Windows that shows your **live Claude Code
limits** at a glance — the same numbers as the `/usage` command — plus historical
usage stats. Closes to a system-tray icon; click the icon to bring it back.

```
┌─────────────────────────────────┐
│ ● Claude Usage            08:11  │
│                                  │
│ 5h     ▓▓▓▓▓▓░░░  66%   4h38m    │
│ Week   ▓░░░░░░░░   9%   7d 21h   │
│ Sonnet ░░░░░░░░░   0%   7d 21h   │
│ ─────────────────────────────── │
│ Value    ~$8,174 all-time        │
│ Extra    $376 / $20,000          │
│ Tokens   2.8M in / 14.3M out     │
│ Today    0 tok / 0 msg           │
│ Lifetime 177 sessions / 63.8k    │
└─────────────────────────────────┘
```

## Requirements

- **Windows 10/11**
- **PowerShell 7+** (`pwsh`) *or* Windows PowerShell 5.1 (built into Windows — used
  automatically as a fallback)
- **Claude Code**, signed in (the overlay reuses its login — no separate auth)

## Install

1. Put this folder anywhere (e.g. `Documents\ClaudeUsageOverlay`).
2. **Double-click `Install.bat`.**

That adds a login auto-start entry and launches the overlay (top-right of your screen
+ a clay-colored **C** icon in the system tray). That's it.

> Prefer the command line? `pwsh -File overlay.ps1 -Install`

## Using it

| Action | How |
| --- | --- |
| **Reopen after closing** | Left-click the **C** tray icon (toggles show/hide) |
| **Move it** | Drag the panel anywhere — it remembers the position |
| **Refresh now** | Right-click tray icon → *Refresh now* |
| **Toggle auto-start** | Right-click tray icon → *Open at login* |
| **Quit completely** | Right-click tray icon → *Quit* |

Closing the panel with the mouse only **hides** it — the app keeps running in the tray.
There is **no console window** to keep open; it runs as a hidden background process.

## What the numbers mean

**Live limits** (from Claude's usage endpoint, refreshed every 3 minutes):
- **5h** — current 5-hour session window (% used, time until reset)
- **Week** — combined weekly limit
- **Sonnet / Opus** — per-model weekly limits (Opus row appears only when used)

Bars turn **amber at ≥80%** and **red at ≥95%**. The header dot is green when data is
fresh, amber if stale/rate-limited, red if your login expired.

**Historical stats** (from Claude Code's local cache, recomputed periodically):
- **Value** — *estimated* pay-as-you-go API dollar value of your usage (your plan is
  flat-rate, so this is "what it would've cost on the API," not a real charge)
- **Extra** — real extra-usage spend beyond your plan
- **Tokens** — all-time input / output tokens
- **Today** — today's tokens / messages (fills in when Claude Code refreshes its cache)
- **Lifetime** — total sessions / messages

## Uninstall

- Double-click **`Uninstall.bat`** (removes login auto-start), then **Quit** from the tray.
- Delete the folder to remove it entirely.

## How it works (and privacy)

- Reads your OAuth token **locally** from `%USERPROFILE%\.claude\.credentials.json` on each
  refresh (so token refreshes are picked up automatically). The token never leaves your
  machine except in the request to Anthropic's own usage endpoint.
- The live numbers come from `https://api.anthropic.com/api/oauth/usage` — an **undocumented**
  endpoint the `/usage` command uses. It's polled at a safe 3-minute interval with the
  required headers. If Anthropic ever changes it, the overlay degrades gracefully (shows a
  red/amber dot and last-known values) instead of crashing.
- Everything is in one script: **`overlay.ps1`**. No build step, no dependencies.

## Files

| File | Purpose |
| --- | --- |
| `overlay.ps1` | The entire app |
| `Start-Overlay.vbs` | Silent launcher used by login auto-start |
| `Install.bat` / `Uninstall.bat` | One-click setup / removal |
| `overlay-state.json` | Saved window position (created at runtime) |

## Troubleshooting

- **Red dot / "Auth expired"** — run any Claude Code command once to refresh the login.
- **Amber dot / "Rate limited"** — the usage endpoint is touchy; it self-recovers. Don't
  lower the 180-second poll interval.
- **Nothing appears** — check `overlay-error.log` in this folder.
