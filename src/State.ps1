# State.ps1 — settings persistence (overlay-state.json), window positioning, and Copy-Stats

function Save-State {
    try {
        $script:Cfg.Left = $script:window.Left
        $script:Cfg.Top  = $script:window.Top
        $script:Cfg | ConvertTo-Json | Set-Content -Path $script:StatePath -Encoding UTF8
    } catch { Write-Log "Save-State failed: $($_.Exception.Message)" }
}

function Load-State {
    try {
        if (-not (Test-Path $script:StatePath)) { return }
        $s = Get-Content $script:StatePath -Raw | ConvertFrom-Json
        foreach ($k in @('Left','Top','Opacity','StartHidden','ShowStats','Theme','ShowAlerts','ShowGraph')) {
            if ($null -ne $s.$k) { $script:Cfg[$k] = $s.$k }
        }
    } catch { Write-Log "Load-State failed: $($_.Exception.Message)" }
}

function Apply-Settings {
    $script:window.Opacity = [double]$script:Cfg.Opacity
    $vis = if ($script:Cfg.ShowStats) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    $sp = $script:window.FindName('statsPanel'); if ($sp) { $sp.Visibility = $vis }
    # Show/hide the sparkline row based on ShowGraph setting
    $sparkVis = if ($script:Cfg.ShowGraph) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    $sparkRow = $script:window.FindName('sparkRow'); if ($sparkRow) { $sparkRow.Visibility = $sparkVis }
    Apply-Theme $script:Cfg.Theme
}

function Clamp-Position {
    $wa = [System.Windows.SystemParameters]::WorkArea
    $w  = $script:window.ActualWidth
    $h  = $script:window.ActualHeight
    $script:window.Left = [math]::Max($wa.Left, [math]::Min($script:window.Left, $wa.Right  - $w))
    $script:window.Top  = [math]::Max($wa.Top,  [math]::Min($script:window.Top,  $wa.Bottom - $h))
}

function Snap-ToCorner([string]$corner) {
    $wa = [System.Windows.SystemParameters]::WorkArea
    $w  = $script:window.ActualWidth;  $h = $script:window.ActualHeight
    switch ($corner) {
        'TR' { $script:window.Left = $wa.Right - $w - 16; $script:window.Top = $wa.Top    + 16 }
        'TL' { $script:window.Left = $wa.Left  + 16;      $script:window.Top = $wa.Top    + 16 }
        'BR' { $script:window.Left = $wa.Right - $w - 16; $script:window.Top = $wa.Bottom - $h - 16 }
        'BL' { $script:window.Left = $wa.Left  + 16;      $script:window.Top = $wa.Bottom - $h - 16 }
    }
    Save-State
}

function Position-Window {
    if ($script:Positioned) { return }
    $script:Positioned = $true
    if ($null -ne $script:Cfg.Left) {
        $script:window.Left = [double]$script:Cfg.Left
        $script:window.Top  = [double]$script:Cfg.Top
        Clamp-Position
    } else {
        Snap-ToCorner 'TR'
    }
}

function Copy-Stats {
    $d = $script:State.Data; $s = $script:Stats
    $lines = @("Claude Code Usage — $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
    if ($d) {
        $lines += "5-hour:  $([math]::Round(100-[double]$d.five_hour.utilization))% remaining  ($(Format-Reset $d.five_hour.resets_at))"
        $lines += "Weekly:  $([math]::Round(100-[double]$d.seven_day.utilization))% remaining  ($(Format-Reset $d.seven_day.resets_at))"
        if ($d.seven_day_sonnet) { $lines += "Sonnet:  $([math]::Round(100-[double]$d.seven_day_sonnet.utilization))% remaining" }
        if ($d.seven_day_opus)   { $lines += "Opus:    $([math]::Round(100-[double]$d.seven_day_opus.utilization))% remaining" }
    }
    if ($s) {
        $lines += "Est. API value: ~$(Fmt-Money $s.ValueUSD) all-time"
        $lines += "Tokens: $(Fmt-Tok $s.InTokens) in / $(Fmt-Tok $s.OutTokens) out"
        $lines += "Lifetime: $($s.Sessions) sessions / $(Fmt-Tok $s.Messages) msgs"
    }
    [System.Windows.Clipboard]::SetText(($lines -join "`n"))
}
