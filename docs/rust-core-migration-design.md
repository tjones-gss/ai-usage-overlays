# Staged Rust Core Migration Design

Issue: #15, "Explore staged Rust core migration without a full rewrite"

## Goal

Introduce a native Rust data core as an optional helper while keeping the existing PowerShell/WPF overlay as the UI shell until the helper proves it can improve reliability, startup cost, typed parsing, and packaging without regressing current behavior.

This is a design-note/POC deliverable. It does not replace runtime PowerShell files and does not require the overlay to call Rust yet.

## Current Shape

The app is already split into a practical shell/core boundary:

- `unified-overlay.ps1` owns process startup, autostart, `-Json` snapshot mode, WPF boot, refresh jobs, and dispatcher handoff.
- `src\Shell.ps1` owns XAML, section rendering, resize behavior, and provider-specific UI updates.
- `src\UnifiedTray.ps1` owns tray icon, context menu, alerts, update menu entries, and quit/minimize behavior.
- `src\UnifiedState.ps1` owns user settings, section visibility, window positioning, and clipboard export.
- `src\Data.ps1` owns Claude live usage/profile reads plus Claude transcript aggregation.
- `src\CodexData.ps1` owns Codex JSONL parsing, cache management, rate-limit extraction, and cost aggregation.
- `src\CursorData.ps1` owns Cursor token discovery, SQLite helper calls, dashboard API reads, and Cursor stat aggregation.
- `src\Update.ps1` and `packaging\` own GitHub release update checks and installer behavior.

The existing `unified-overlay.ps1 -Json` mode is the natural POC baseline because it already emits one machine-readable snapshot without launching the HUD.

## Proposed Helper

Prototype a single binary:

```powershell
ai-usage-core.exe snapshot --json --provider claude
```

The helper should be pure data plumbing. It should not create windows, own tray controls, mutate overlay UI settings, install autostart entries, or decide how sections are rendered. It should return a versioned JSON snapshot and exit with a predictable code.

Initial responsibilities:

- Read Claude Code credentials from the same local file the PowerShell code already uses.
- Fetch Claude usage and profile endpoints with typed response models.
- Normalize Claude limits into a stable schema that preserves `five_hour`, `seven_day`, scoped weekly limits such as Fable/Opus, extra usage, identity, status, and errors.
- Implement conservative timeout, retry, and backoff behavior inside the helper.
- Emit JSON to stdout and human diagnostics to stderr.
- Avoid writing provider caches in the first POC unless the cache format is explicitly versioned.

Later responsibilities, only after the Claude POC is accepted:

- Parse Claude transcript JSONL files and emit local aggregate stats.
- Parse Codex session JSONL files, including token counts, model detection, message dates, and latest rate limits.
- Replace the bundled `sqlite3.exe` call path for Cursor local reads if Rust can safely read Cursor SQLite databases in read-only mode.
- Optionally provide a long-running watch/poll mode if one-shot process startup becomes the bottleneck.

## Boundary

Keep PowerShell/WPF responsible for:

- Window creation, XAML rendering, dispatcher-thread updates, resize/animation behavior, and section visibility.
- Tray icon, context menu, balloon alerts, manual refresh, update menu, quit/minimize, and autostart shortcuts.
- User preferences in `unified-overlay-state.json`.
- History graph rendering and local display formatting.
- GitHub release update checks until packaging explicitly includes the helper binary.
- Fallback behavior when the helper is missing, exits non-zero, or returns an unsupported schema version.

Move to Rust gradually:

- Provider API clients and typed response parsing.
- JSONL parsing and aggregation where PowerShell currently pays repeated parse cost.
- Backoff, timeout, and retry policy for provider reads.
- Optional file watching or incremental cache invalidation.
- Stable command-line JSON contract.

The PowerShell boundary should consume Rust through a narrow command invocation, not through direct DLL loading. That keeps rollback simple: skip the helper and call the existing PowerShell functions.

## Snapshot Contract

Use a versioned top-level envelope. The first Rust-compatible version should be named `ai-usage.snapshot.v1` even if the PowerShell `-Json` output keeps extra fields during transition.

```json
{
  "schema": "ai-usage.snapshot.v1",
  "generatedAt": "2026-07-06T15:30:00.0000000-05:00",
  "appVersion": "0.1.2",
  "source": {
    "name": "ai-usage-core",
    "version": "0.1.0-poc",
    "mode": "snapshot"
  },
  "providers": {
    "claude": {
      "status": "ok",
      "message": "",
      "lastFetch": "15:30",
      "identity": {
        "email": "user@example.com",
        "organization": "Example Org",
        "organizationId": "org_123",
        "display": "user@example.com / Example Org"
      },
      "limits": {
        "fiveHour": {
          "usedPercent": 42.5,
          "resetsAt": "2026-07-06T18:00:00.0000000-05:00"
        },
        "weekly": {
          "usedPercent": 68.0,
          "resetsAt": "2026-07-09T00:00:00.0000000-05:00"
        },
        "scopedWeekly": [
          {
            "key": "fable",
            "displayName": "Fable",
            "usedPercent": 12.0,
            "resetsAt": "2026-07-09T00:00:00.0000000-05:00"
          }
        ]
      },
      "extraUsage": {
        "enabled": true,
        "currency": "USD",
        "usedCredits": 1234,
        "monthlyLimit": 5000
      },
      "stats": {
        "valueUsd": 14.21,
        "inputTokens": 1200000,
        "outputTokens": 350000,
        "sessions": 91,
        "messages": 412,
        "todayTokens": 64000,
        "todayMessages": 18,
        "lastComputed": "2026-07-06 15:30"
      },
      "errors": []
    }
  }
}
```

Field rules:

- `schema` is required. PowerShell should reject unsupported major versions and fall back to native functions.
- `generatedAt` uses ISO 8601 with offset.
- Provider `status` values are `ok`, `stale`, `auth`, `error`, or `unavailable`.
- Missing optional provider data should be `null` or an empty array, not a changed object shape.
- Token counts and credits are integers. Money estimates are decimal numbers in USD.
- `usedPercent` remains "used", matching the existing UI bar and alert behavior.
- Raw provider payloads should not be required for rendering. They may be exposed behind an explicit debug flag later.

## PowerShell Consumption POC

Do not replace all refresh jobs at once. Add a small adapter later, for example:

```powershell
function Get-CoreSnapshot {
    param([string]$Provider = 'claude')

    $exe = Join-Path $script:AppDir 'ai-usage-core.exe'
    if (-not (Test-Path $exe)) { return $null }

    $raw = & $exe snapshot --json --provider $Provider 2>> $script:ErrLog
    if ($LASTEXITCODE -ne 0 -or -not $raw) { return $null }

    $snapshot = $raw | ConvertFrom-Json -ErrorAction Stop
    if ($snapshot.schema -ne 'ai-usage.snapshot.v1') { return $null }

    return $snapshot
}
```

The adapter should translate from the schema into the existing script variables rather than forcing `src\Shell.ps1` to learn a second data shape:

- Claude live usage maps into `$script:State.Data`, `$script:State.Status`, `$script:State.Message`, and `$script:ClaudeIdentity`.
- Claude local stats map into `$script:Stats`.
- Codex stats map into `$script:CodexStats`.
- Cursor usage, summary, and local metrics map into `$script:LiveData`, `$script:SummaryData`, `$script:LocalData`, `$script:AuthState`, and `$script:CursorErrMsg`.

That keeps rendering untouched and makes helper use reversible per provider.

## Staged Plan

Stage 0: Contract alignment

- Keep `unified-overlay.ps1 -Json` as the observed reference output.
- Add a schema fixture once implementation begins.
- Decide whether `-Json` should eventually emit the normalized `providers` envelope or continue to emit the current PowerShell-native object.

Stage 1: Claude live usage/profile helper

- Implement `ai-usage-core.exe snapshot --json --provider claude`.
- Fetch usage and profile only.
- Normalize top-level limits plus scoped weekly limits.
- Return auth/rate-limit/network failures as structured provider status and error entries.
- Compare helper output with `unified-overlay.ps1 -Json` for the same account.

Stage 2: Optional PowerShell adapter

- Add a feature-gated call path such as `-UseCore` or an internal `$script:UseCoreHelper`.
- Keep the existing PowerShell path as fallback.
- Update only the refresh job that currently calls `Get-Usage` and `Get-ClaudeProfile`.
- Verify the HUD, tray text, alerts, and copy-to-clipboard output behave the same.

Stage 3: Claude transcript aggregation

- Move JSONL parsing and cost aggregation if the helper proves faster and easier to test.
- Keep cache format separate from `stats-cache.json` until compatibility is intentional.
- Compare aggregate totals against `Measure-Stats` tests and representative transcript fixtures.

Stage 4: Codex JSONL aggregation

- Port `src\CodexData.ps1` parsing once the Claude path is stable.
- Preserve model fallback behavior, latest rate-limit selection, per-file cache stamp semantics, and today's message/token counts.
- Decide whether Rust owns `codex-cache.json` or writes a new `codex-core-cache-v1.json`.

Stage 5: Cursor and packaging review

- Consider Cursor only after the helper has a clear packaging story and a read-only SQLite strategy.
- Keep Cursor dashboard API changes easy to patch; those endpoints are more likely to drift.
- Package `ai-usage-core.exe` in the installer only when fallback and update behavior are tested.

Stage 6: UI decision

- Revisit native Rust UI only if the helper has provider parity, installer support, tests, and a clear reason to leave WPF.
- Until then, PowerShell/WPF remains the supported UI.

## Decision Points

Continue after Stage 1 only if:

- Claude helper output matches the existing overlay for core limits and identity.
- Cold one-shot latency is acceptable or measurably better than PowerShell.
- Failure states are no worse than the existing `auth`, `stale`, and `error` behavior.
- The helper binary can be built reproducibly for Windows x64.

Continue after Stage 2 only if:

- The overlay can fall back automatically when the helper is missing or incompatible.
- The UI does not need provider-specific schema branches.
- Pester tests can cover schema translation without launching WPF.

Move Codex only if:

- Rust parsing materially improves startup/refresh cost or testability.
- Cache ownership is explicit.
- Totals match existing fixtures.

Move Cursor only if:

- Read-only SQLite access is safe against Cursor's live database.
- API drift can still be patched quickly.
- Auth/token handling remains local and does not introduce stored overlay credentials.

Consider native UI only if:

- Provider data parity is complete.
- Installer, autostart, update, tray, hidden startup, DPI/window-position behavior, and alerts have equivalent coverage.
- Maintaining two UI stacks becomes more expensive than completing the migration.

## Testing and Verification for a Future POC

Design-level verification for this note:

- Confirm it is docs-only.
- Confirm no runtime files are changed.
- Run `git diff --check`.

Implementation verification when a helper exists:

- `ai-usage-core.exe snapshot --json --provider claude | ConvertFrom-Json`
- `pwsh -NoLogo -NoProfile -File .\unified-overlay.ps1 -Json | ConvertFrom-Json`
- Compare Claude `usedPercent`, reset timestamps, identity display, and extra usage.
- Add Pester tests for schema-to-existing-variable translation.
- Run the existing Pester suite.
- Manually launch the HUD and verify refresh, alerts, tray text, copy stats, hidden startup, and update menu fallback.

## Open Questions

- Should `unified-overlay.ps1 -Json` become the normalized schema, or remain a PowerShell-native diagnostic snapshot?
- Should Rust own provider caches immediately, or should Stage 1 stay stateless?
- Should helper selection be an explicit user/developer switch first, or an automatic "use if present" path?
- Which Rust release profile and signing story should the installer use?
- Does the project want a `docs/schema/` fixture directory once implementation begins?
