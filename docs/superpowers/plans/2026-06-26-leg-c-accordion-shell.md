# Leg C — Accordion Shell Implementation Plan

> **For agentic workers:** Implement this plan in `src/Shell.ps1` ONLY. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A single WPF window (`$xaml`) with three collapsible accordion sections (Claude, Codex, Cursor), animated `Window.Height` on toggle, theme application across all sections, and three `Update-*Section` render functions plus orchestration.

**Architecture:** One `[XamlReader]::Parse`-able Window string with `SizeToContent="Width"` (width auto; height explicit + animatable). Each section = an always-visible clickable header (with chevron) + a collapsible `StackPanel` body. Claude's body reuses `src/Ui.ps1` element names verbatim so its `Update-UI` body ports directly; Codex/Cursor bodies use `codex*`/`cursor*`-prefixed names so every `x:Name` is globally unique. Toggling a section flips its body `Visibility`, swaps the chevron glyph, persists via `Save-UnifiedState`, and animates `root.Height` with a `DoubleAnimation` (~180ms CubicEase EaseOut).

**Tech Stack:** PowerShell 7 (pwsh), WPF (PresentationFramework/PresentationCore/WindowsBase), XAML.

## Global Constraints

- Run/verify everything with `pwsh` 7 at `C:\Users\nweerasinghe\AppData\Local\Microsoft\WindowsApps\pwsh.exe` — never `powershell.exe`.
- Save `src/Shell.ps1` UTF-8 **no BOM**. Chevron glyphs must render under pwsh 7.
- Edit ONLY `src/Shell.ps1`. Touch nothing else. Do NOT run git.
- Lint clean: `Invoke-ScriptAnalyzer -Path ./src/Shell.ps1 -Severity Error` → none.
- Do not lower the 37/37 Pester baseline.
- Consume these speculatively (assume they exist; do NOT define): `$script:Themes` (Leg F, incl. 'Black & White'); `Fmt-Tok,Fmt-Money,Format-Reset,NewBrush,New-GradientBrush,New-GradientBrush2`, `$script:State,$script:Stats,$script:BarTrackWidth,$script:WarnPct,$script:CritPct` (Claude modules); `$script:CodexStats` keyed `ValueUSD,InTokens,OutTokens,Sessions,Messages,TodayTok,LastComputed` (Leg A); `$script:LiveData,$script:LocalData,$script:SummaryData,$script:AuthState,$script:CursorErrMsg,$script:CursorLastFetch,Fmt-Num` (Leg B); `$script:window,Save-UnifiedState` (Leg E). Guard `Save-UnifiedState` with `Get-Command`.

---

## File Structure

- `src/Shell.ps1` — the only file. Sections in order:
  1. `$xaml` here-string (the merged accordion window).
  2. Theme helpers reused/local: `Apply-UnifiedTheme`.
  3. Accordion mechanics: `Set-Section`, `Toggle-Section`.
  4. Per-section renderers: `Update-ClaudeSection`, `Update-CodexSection`, `Update-CursorSection`.
  5. Orchestrator: `Update-AllSections`.

---

### Task 1: The `$xaml` accordion window string

**Files:**
- Create: `src/Shell.ps1`

**Interfaces:**
- Produces: `$xaml` (string). Required global-unique `x:Name`s:
  - Root + chrome: `root` (Window), `mainBorder`, `accentStripe`, `gssPath`, `gssLabel`, `statusDot`, `timeText`.
  - Headers: `claudeHeader`,`codexHeader`,`cursorHeader`; chevrons `claudeChevron`,`codexChevron`,`cursorChevron`.
  - Bodies: `claudeBody`,`codexBody`,`cursorBody` (StackPanels).
  - claudeBody reuses Ui.ps1 names verbatim: `fivehBar,fivehPct,fivehSub,fivehReset,fivehLabel,weekBar,weekPct,weekSub,weekReset,weekLabel,sonBar,sonPct,sonSub,sonReset,sonLabel,opusRow,opusBar,opusPct,opusSub,opusReset,opusLabel,valText,tokText,todayText,lifeText,statsPanel,extraRow,extraVal`.
  - codexBody: `codexCostText,codexTokText,codexTodayText,codexModelText,codexSessText,codexBar,codexBudgetText`.
  - cursorBody: `reqBar,barTrack,reqCount,reqReset,overPill,onDemandText,onDemandLabel,editsText,cursorTodayText,cursorModelText,cursorSessText,reqLabel`.

- [ ] **Step 1: Write the `$xaml` here-string**

Root `Window x:Name="root"` with `SizeToContent="Width"` (NOT WidthAndHeight — height must stay animatable), `WindowStyle="None" AllowsTransparency="True" Background="Transparent" Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize" WindowStartupLocation="Manual"`. Inside: outer `Grid Margin="12"` → `Border x:Name="mainBorder"` (gradient bg, rounded) → `DockPanel` → `accentStripe` (Top) + a single `StackPanel Width="250"` containing chrome header (statusDot + "AI USAGE" + timeText), then the three accordion section groups, then GSS footer (gssPath + gssLabel).

Each accordion section is:
```xml
<StackPanel Margin="0,0,0,6">
  <Border x:Name="claudeHeader" Background="#11FFFFFF" CornerRadius="6" Padding="6,4" Margin="0,0,0,4" Cursor="Hand">
    <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <TextBlock x:Name="claudeChevron" Grid.Column="0" Text="v" Foreground="#7B9EC4" FontSize="11" FontFamily="Consolas" VerticalAlignment="Center" Margin="0,0,7,0"/>
      <TextBlock Grid.Column="1" Text="CLAUDE" Foreground="#E2E8F0" FontSize="12" FontFamily="Bahnschrift SemiBold" VerticalAlignment="Center"/>
    </Grid>
  </Border>
  <StackPanel x:Name="claudeBody"> ... section content ... </StackPanel>
</StackPanel>
```
- The chevron glyph: use `v` (expanded) / `>` (collapsed) — plain ASCII, guaranteed to render. (Document this assumption.)
- claudeBody content = copy the metric/stats blocks from `src/Ui.ps1` lines 68-239 verbatim (5h/week/sonnet/opus bars + statsPanel + extraRow), keeping every `x:Name`. Drop the sparkRow/spark canvases (optional per contract; omit to keep render logic simple — `Update-ClaudeSection` will not call Set-Spark).
- codexBody content (mirror Claude's stats-grid style, accent #10B981):
```xml
<StackPanel x:Name="codexBody">
  <Grid Margin="0,0,0,3">
    <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
    <TextBlock Grid.Column="0" Text="EST. COST" Foreground="#34D399" FontSize="10" FontFamily="Bahnschrift SemiBold" VerticalAlignment="Bottom"/>
    <TextBlock Grid.Column="1" x:Name="codexCostText" Text="--" Foreground="#F1F5F9" FontSize="20" FontFamily="Bahnschrift Bold" VerticalAlignment="Bottom"/>
  </Grid>
  <Border Height="7" CornerRadius="3.5" Background="#131F33" Width="250" HorizontalAlignment="Left">
    <Border x:Name="codexBar" Height="7" CornerRadius="3.5" HorizontalAlignment="Left" Width="0">
      <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
        <GradientStop Color="#065F46" Offset="0"/><GradientStop Color="#34D399" Offset="1"/>
      </LinearGradientBrush></Border.Background>
    </Border>
  </Border>
  <TextBlock x:Name="codexBudgetText" Text="" Foreground="#5C7A96" FontSize="9" FontFamily="Bahnschrift SemiBold" Margin="0,1,0,6"/>
  <Grid Margin="0,0,0,2"><Grid.ColumnDefinitions><ColumnDefinition Width="78"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
    <TextBlock Grid.Column="0" Text="TOKENS" Foreground="#7BA8C8" FontSize="10" FontFamily="Bahnschrift SemiBold"/>
    <TextBlock Grid.Column="1" x:Name="codexTokText" Text="--" Foreground="#94A3B8" FontSize="12" FontFamily="Consolas"/></Grid>
  <Grid Margin="0,0,0,2"><Grid.ColumnDefinitions><ColumnDefinition Width="78"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
    <TextBlock Grid.Column="0" Text="TODAY" Foreground="#7BA8C8" FontSize="10" FontFamily="Bahnschrift SemiBold"/>
    <TextBlock Grid.Column="1" x:Name="codexTodayText" Text="--" Foreground="#94A3B8" FontSize="12" FontFamily="Consolas"/></Grid>
  <Grid Margin="0,0,0,2"><Grid.ColumnDefinitions><ColumnDefinition Width="78"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
    <TextBlock Grid.Column="0" Text="MODEL" Foreground="#7BA8C8" FontSize="10" FontFamily="Bahnschrift SemiBold"/>
    <TextBlock Grid.Column="1" x:Name="codexModelText" Text="--" Foreground="#94A3B8" FontSize="12" FontFamily="Consolas"/></Grid>
  <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="78"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
    <TextBlock Grid.Column="0" Text="SESSIONS" Foreground="#7BA8C8" FontSize="10" FontFamily="Bahnschrift SemiBold"/>
    <TextBlock Grid.Column="1" x:Name="codexSessText" Text="--" Foreground="#94A3B8" FontSize="12" FontFamily="Consolas"/></Grid>
</StackPanel>
```
- cursorBody content = copy the cursor-overlay.ps1 body (lines 389-505) but RENAME dup names: `todayText`→`cursorTodayText`, `modelText`→`cursorModelText`, `sessText`→`cursorSessText`. Drop the cursor `headerLabel`/`statusDot`/`timeText`/`gssPath`/`gssLabel` (chrome lives at root). Keep `reqBar,barTrack,reqCount,reqReset,overPill,onDemandText,onDemandLabel,editsText,reqLabel`.

- [ ] **Step 2: Verify the XAML parses and names resolve**

Run:
```
pwsh -NoProfile -STA -Command "Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase; . ./src/Config.ps1; . ./src/Shell.ps1; \$w=[Windows.Markup.XamlReader]::Parse(\$xaml); foreach(\$n in 'root','claudeHeader','codexHeader','cursorHeader','claudeBody','codexBody','cursorBody','codexCostText','cursorTodayText'){ if(-not \$w.FindName(\$n)){ throw \"missing \$n\" } }; 'xaml ok'"
```
Expected: `xaml ok`. (Config.ps1 lacking 'Black & White' is fine here.)

---

### Task 2: `Apply-UnifiedTheme`

**Interfaces:**
- Consumes: `$script:Themes[$name]` (key shape: `BgC1,BgC2,BorderC1,GssLabelFg,FivehColors,WeekColors,SonColors,OpusColors,FivehFg,WeekFg,SonFg,OpusFg,Stripe`), `NewBrush`, `New-GradientBrush`, `New-GradientBrush2`, `$script:window`.
- Produces: `function Apply-UnifiedTheme([string]$name)`.

- [ ] **Step 1: Port `Apply-Theme` from Ui.ps1, extend to codex/cursor**

Mirror Ui.ps1 `Apply-Theme` (lines 275-339): set mainBorder bg/border, gssLabel/gssPath, the four Claude bars/labels/subs, accentStripe gradient, themeItems checkmarks. THEN extend:
- Codex: `codexBar.Background = New-GradientBrush $t.SonColors[0] $t.SonColors[1]` (reuse an existing theme key so greyscale 'Black & White' stays safe); color codex labels via `$t.SonFg` where a label exists.
- Cursor: `reqBar.Background = New-GradientBrush $t.FivehColors[0] $t.FivehColors[1]`; `reqLabel.Foreground = NewBrush $t.FivehFg`; leave overPill/onDemand amber as-is.
- Guard every `FindName` with `if ($el)`. Do not throw if a theme key or element is absent.

- [ ] **Step 2: Verify Apply-UnifiedTheme does not throw for a present theme**

Run:
```
pwsh -NoProfile -STA -Command "Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase; . ./src/Config.ps1; . ./src/Format.ps1; . ./src/Shell.ps1; \$script:window=[Windows.Markup.XamlReader]::Parse(\$xaml); Apply-UnifiedTheme 'Deep Space'; 'theme ok'"
```
Expected: `theme ok`.

---

### Task 3: `Set-Section` and `Toggle-Section` (animated resize)

**Interfaces:**
- Consumes: `$script:window`, `Save-UnifiedState` (guard with `Get-Command`).
- Produces: `function Set-Section([string]$key,[bool]$expanded)`, `function Toggle-Section([string]$key)`.

- [ ] **Step 1: Write `Set-Section` (non-animated, startup restore)**

```powershell
function Set-Section([string]$key, [bool]$expanded) {
    $body = $script:window.FindName($key + 'Body')
    $chev = $script:window.FindName($key + 'Chevron')
    if (-not $body) { return }
    $body.Visibility = if ($expanded) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    if ($chev) { $chev.Text = if ($expanded) { 'v' } else { '>' } }
}
```

- [ ] **Step 2: Write `Toggle-Section` with `DoubleAnimation` on `HeightProperty`**

Approach: flip visibility/chevron via the same logic, force a layout pass with `SizeToContent="Width"` keeping width, read the new desired height, then animate `root.Height` from current `ActualHeight` to that target.

```powershell
function Toggle-Section([string]$key) {
    $body = $script:window.FindName($key + 'Body')
    if (-not $body) { return }
    $expanded = ($body.Visibility -ne [System.Windows.Visibility]::Visible)  # target state
    $root = $script:window

    $from = $root.ActualHeight
    Set-Section $key $expanded                      # apply visibility + chevron
    $root.UpdateLayout()
    $root.Measure([System.Windows.Size]::new($root.ActualWidth, [double]::PositiveInfinity))
    $to = $root.DesiredSize.Height
    if ($to -le 0) { $to = $root.ActualHeight }

    # Pin height so SizeToContent does not fight the animation, then animate.
    $anim = New-Object System.Windows.Media.Animation.DoubleAnimation
    $anim.From = $from
    $anim.To   = $to
    $anim.Duration = [System.Windows.Duration]([TimeSpan]::FromMilliseconds(180))
    $ease = New-Object System.Windows.Media.Animation.CubicEase
    $ease.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
    $anim.EasingMode = $ease
    $root.BeginAnimation([System.Windows.Window]::HeightProperty, $anim)

    if (Get-Command Save-UnifiedState -ErrorAction SilentlyContinue) { Save-UnifiedState }
}
```
Notes to honor: `$anim.EasingMode` is the wrong property name — `DoubleAnimation` has `.EasingFunction`. Use `$anim.EasingFunction = $ease`. (Fix in the actual code; this step's pseudo had the bug intentionally flagged.)

- [ ] **Step 3: Verify both functions are defined and reference DoubleAnimation/HeightProperty**

Run:
```
pwsh -NoProfile -Command "\$e=\$null;[void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path ./src/Shell.ps1),[ref]\$null,[ref]\$e); if(\$e.Count){throw \$e}; 'parsed'"
```
Then grep-check (manual): file contains `DoubleAnimation`, `HeightProperty`, `CubicEase`, `BeginAnimation`.

---

### Task 4: `Update-ClaudeSection`

**Interfaces:**
- Consumes: `$script:State`, `$script:Stats`, `$script:window`, `Set-Bar`/`Fmt-Tok`/`Fmt-Money` (from Claude modules), `$script:notify` (optional).
- Produces: `function Update-ClaudeSection`.

- [ ] **Step 1: Port Ui.ps1 `Update-UI` body, minus chrome dot/time (handled by Update-AllSections) and minus sparklines**

Copy Ui.ps1 `Update-UI` (lines 401-467) into `Update-ClaudeSection` but: remove the `$dot`/`$time` chrome block (now global, set in Update-AllSections), remove the two `Set-Spark` calls, keep the bar/stats logic verbatim. Keep `Set-Bar` calls (Set-Bar is a Claude helper from Ui.ps1 — but Ui.ps1 is NOT dot-sourced by the unified app per Leg E order). **Assumption to document:** Leg E dot-sources Claude `src/*` but the contract lists Config/Format/Pricing/History/Data/State, NOT Ui.ps1. Therefore `Set-Bar` may be unavailable. Define a local private `Set-SectionBar` helper inside Shell.ps1 replicating Ui.ps1's `Set-Bar` (lines 345-363) so Claude bars render without depending on Ui.ps1. Use it in this function.

- [ ] **Step 2: Verify parse**

Run the parse-check from Task 3 Step 3. Expected `parsed`.

---

### Task 5: `Update-CodexSection`

**Interfaces:**
- Consumes: `$script:CodexStats` (`ValueUSD,InTokens,OutTokens,Sessions,Messages,TodayTok,LastComputed`), `Fmt-Tok`, `Fmt-Money`, `$script:window`.
- Produces: `function Update-CodexSection`.

- [ ] **Step 1: Fill codex elements; guard null stats**

```powershell
function Update-CodexSection {
    $s = $script:CodexStats
    if (-not $s) {
        $script:window.FindName('codexCostText').Text = '--'
        $script:window.FindName('codexTokText').Text  = '--'
        return
    }
    $script:window.FindName('codexCostText').Text  = Fmt-Money $s.ValueUSD
    $script:window.FindName('codexTokText').Text   = ('{0} in / {1} out' -f (Fmt-Tok $s.InTokens), (Fmt-Tok $s.OutTokens))
    $script:window.FindName('codexTodayText').Text = ('{0} tok' -f (Fmt-Tok $s.TodayTok))
    $script:window.FindName('codexSessText').Text  = ('{0} sessions  {1} msgs' -f $s.Sessions, (Fmt-Tok $s.Messages))
    $bud = $script:window.FindName('codexBudgetText'); if ($bud) { $bud.Text = "as of $($s.LastComputed)" }
}
```
`codexModelText` has no field in the Codex stats contract (model is per-session, not aggregated) — leave its XAML default `--` or set to `''`. Document this gap for merge.

- [ ] **Step 2: Verify parse.** Run the Task 3 Step 3 parse-check. Expected `parsed`.

---

### Task 6: `Update-CursorSection`

**Interfaces:**
- Consumes: `$script:LiveData` (`.'gpt-4'.numRequests/.maxRequestUsage`, `.startOfMonth`), `$script:LocalData` (`total,today,topModel,topPct,convos`), `$script:SummaryData` (`.individualUsage.onDemand.used`), `$script:AuthState`, `$script:CursorErrMsg`, `$script:CursorLastFetch`, `Fmt-Num`, `Format-Reset`, `$script:window`, `$script:BarTrackWidth`.
- Produces: `function Update-CursorSection`.

- [ ] **Step 1: Port cursor-overlay.ps1 `Update-UI` body, renamed elements + namespaced vars**

Copy cursor-overlay.ps1 `Update-UI` (lines 551-636) but: drop the `$dot` chrome block; rename `todayText`→`cursorTodayText`, `modelText`→`cursorModelText`, `sessText`→`cursorSessText`; replace `$script:ErrMsg`→`$script:CursorErrMsg`, `$script:LastFetch`→`$script:CursorLastFetch`; do not set `$time` (global). For the over-pill bar-color restore, use a fixed theme bar gradient (`New-GradientBrush '#065F46' '#34D399'`) instead of `$script:Themes[...].BarC1/BarC2` (those keys belong to the cursor-only theme table, absent in the unified `$script:Themes`). Document this.

- [ ] **Step 2: Verify parse.** Run the Task 3 Step 3 parse-check. Expected `parsed`.

---

### Task 7: `Update-AllSections` (orchestrator + chrome)

**Interfaces:**
- Consumes: `$script:State` (Claude status/lastfetch), `$script:window`, the three `Update-*Section`.
- Produces: `function Update-AllSections`.

- [ ] **Step 1: Set statusDot + timeText, then call the three renderers**

```powershell
function Update-AllSections {
    $dot  = $script:window.FindName('statusDot')
    $time = $script:window.FindName('timeText')
    $status = if ($script:State) { $script:State.Status } else { 'init' }
    switch ($status) {
        'ok'    { $dot.Fill = NewBrush '#4ADE80' }
        'stale' { $dot.Fill = NewBrush '#FBBF24' }
        'auth'  { $dot.Fill = NewBrush '#F87171' }
        'error' { $dot.Fill = NewBrush '#F87171' }
        default { $dot.Fill = NewBrush '#4B6A8A' }
    }
    if ($script:State) {
        $time.Text = if ($script:State.Status -eq 'ok') { $script:State.LastFetch } else { $script:State.Message }
    }
    Update-ClaudeSection
    Update-CodexSection
    Update-CursorSection
}
```

- [ ] **Step 2: Final full smoke (STA WPF)**

Run:
```
pwsh -NoProfile -STA -Command "Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase; . ./src/Config.ps1; . ./src/Format.ps1; . ./src/Shell.ps1; \$script:window=[Windows.Markup.XamlReader]::Parse(\$xaml); foreach(\$n in 'root','claudeHeader','codexHeader','cursorHeader','claudeBody','codexBody','cursorBody','codexCostText'){ if(-not \$script:window.FindName(\$n)){ throw \"missing \$n\" } }; Apply-UnifiedTheme 'Deep Space'; Set-Section 'codex' \$false; Update-AllSections; 'all ok'"
```
Expected: `all ok` (renderers tolerate null data).

- [ ] **Step 3: Lint**

Run: `pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path ./src/Shell.ps1 -Severity Error"` → no output (no errors).

---

## Self-Review checklist

- [ ] Every `x:Name` in `$xaml` is globally unique (Claude originals, `codex*`, `cursor*`).
- [ ] `root` Window uses `SizeToContent="Width"` (not WidthAndHeight) so height animates.
- [ ] `Toggle-Section` uses `DoubleAnimation` on `[System.Windows.Window]::HeightProperty` via `root.BeginAnimation`, with `.EasingFunction` set to a `CubicEase`/EaseOut (NOT `.EasingMode` on the animation).
- [ ] `Set-SectionBar` local helper replicates Ui.ps1 `Set-Bar` (no dependency on Ui.ps1).
- [ ] All renderers guard null data and missing elements.
- [ ] File saved UTF-8 no BOM; chevron glyphs are ASCII `v`/`>`.
</content>
</invoke>
