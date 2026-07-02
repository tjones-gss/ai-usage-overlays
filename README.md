# AI Usage Overlay

Always-on-top Windows HUD for Claude Code, Codex, and Cursor IDE usage in one tray app.

![Unified overlay preview](docs/preview.png)

## What It Shows

**Claude Code**
- Live 5-hour session and weekly quota usage
- Optional Fable and Opus weekly quota rows when Anthropic returns them
- Extra usage / overage spend when enabled
- Local transcript totals: estimated API-equivalent value, tokens, sessions, and messages

**Codex**
- Local session tokens from `~\.codex\sessions`
- Estimated API-equivalent value
- Session and message counts
- Today's tokens and messages
- 5-hour and weekly Codex rate-limit percentages when present in session logs

**Cursor IDE**
- On-demand spend
- Included request usage with OVER detection
- 30-day agent edits, today's edits, accepted lines, and top model

## Install

**One-liner** - paste this into PowerShell, or hand it to your Claude / Cursor agent:

```powershell
irm https://raw.githubusercontent.com/tjones-gss/ai-usage-overlays/master/install.ps1 | iex
```

That's it. No git, no Python, no admin rights. Downloads, installs, and launches the unified overlay automatically.

**Let your AI agent do it** - paste this into Claude Code or Cursor chat:
> Run this in PowerShell to install the AI usage overlay: `irm https://raw.githubusercontent.com/tjones-gss/ai-usage-overlays/master/install.ps1 | iex`

**Manual install** - clone the repo and run `Install.bat`. Login autostart uses `Start-Unified.vbs`.

## Requirements

- Windows 10/11
- PowerShell 7 (`pwsh`)
- Claude Code CLI signed in (`claude auth login`)
- Codex installed if you want Codex stats; sessions are read from `~\.codex\sessions`
- Cursor IDE signed in if you want Cursor usage and analytics

Each provider is optional. If one source is unavailable, the overlay keeps showing the other sections.

## Usage

| Action | How |
|---|---|
| Show / hide overlay | Left-click the **AI** tray icon |
| Show / hide Claude, Codex, or Cursor section | Right-click -> Show/Hide provider |
| Expand / collapse a section | Click its section header |
| Refresh usage immediately | Right-click -> Refresh now |
| Copy current stats | Right-click -> Copy stats to clipboard |
| Open Claude usage page | Right-click -> Open claude.ai/usage |
| Change theme or opacity | Right-click -> Theme / Opacity |
| Snap to a screen corner | Right-click -> Snap to corner |
| Start at login | Right-click -> Open at login |
| Start hidden | Right-click -> Start hidden to tray |
| Toggle alerts or graph | Right-click -> Threshold alerts / Show history graph |
| Quit | Right-click -> Quit |

The overlay saves its position, opacity, theme, start-hidden setting, graph/alert preferences, and visible provider sections.

## Uninstall

```bat
Uninstall.bat
```

## Features

- **Always on top** - stays visible over other windows
- **Unified providers** - Claude Code, Codex, and Cursor in one process and one tray icon
- **Customizable sections** - hide providers you do not use, and expand/collapse individual sections
- **Fast startup** - cached transcript/session parsing makes warm starts quick
- **Async refresh jobs** - provider data loads in background jobs so the HUD can appear immediately
- **Color themes** - Global Shop, Deep Space, Ocean, Mono, and Black & White
- **Drag to reposition** - position is saved between restarts
- **Opacity control** - 100%, 80%, 60%, or 40%
- **Snap to corners** - top-left, top-right, bottom-left, or bottom-right
- **Threshold alerts** - warning and critical notifications for Claude quota thresholds
- **History graph** - optional sparkline for recent Claude quota movement
- **GSS branding** - Global Shop Solutions identity in the footer

## How It Works

The overlay is a PowerShell 7/WPF app that reads existing local credentials and usage artifacts:

- Claude live quota comes from Anthropic's OAuth usage endpoint using the Claude Code token stored under `~\.claude`.
- Claude local stats are computed from JSONL transcripts under `~\.claude\projects`.
- Codex stats are computed from JSONL sessions under `~\.codex\sessions`.
- Cursor usage is read from Cursor's local auth database and Cursor dashboard APIs.
- Cursor SQLite reads use the bundled `sqlite3.exe`.

No separate credentials are stored by the overlay, and no elevated permissions are required.

## Runtime Files

The app writes a few local state/cache files next to the scripts:

- `unified-overlay-state.json` - window position and UI preferences
- `overlay-history.json` - recent Claude quota samples for alerts and graphing
- `stats-cache.json` - Claude transcript parse cache
- `codex-cache.json` - Codex session parse cache
- `unified-overlay-error.log` - diagnostic log
- `unified-overlay.pid` - running process id used by uninstall/cleanup

These files are local runtime data and are not required in git.

## Development

Run the Pester test suite from the repo root:

```powershell
pwsh -NoLogo -NoProfile -Command "Invoke-Pester -Path tests"
```

The default branch is `master`. The old provider-specific branches have been retired; current development happens against the unified overlay on `master`.
