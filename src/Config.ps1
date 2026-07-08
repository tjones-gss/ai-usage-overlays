# Config.ps1 - shared constants, pricing table, color themes, and default settings

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
$script:PollSeconds    = 180
$script:TickSeconds    = 30
$script:BarTrackWidth  = 250.0
$script:WarnPct        = 80
$script:CritPct        = 95
$script:AppVersion     = '0.2.0'
$script:RepoOwner      = 'tjones-gss'
$script:RepoName       = 'ai-usage-overlays'
$script:UpdateChannel  = 'release'

if ($script:AppDir) {
    $script:AppVersionPath = Join-Path $script:AppDir 'app-version.txt'
    if (Test-Path $script:AppVersionPath) {
        try {
            $versionText = (Get-Content $script:AppVersionPath -Raw).Trim()
            if ($versionText) { $script:AppVersion = $versionText }
        } catch { }
    }
}

# ---------------------------------------------------------------------------
# Pricing table
# ---------------------------------------------------------------------------
$script:PricesAsOf = '2026-06-01'
$script:Prices = @{
    fable  = @{ in = 10.0; out = 50.0; cw = 12.50; cr = 1.00 }
    opus   = @{ in = 15.0; out = 75.0; cw = 18.75; cr = 1.50 }
    sonnet = @{ in = 3.0;  out = 15.0; cw = 3.75;  cr = 0.30 }
    haiku  = @{ in = 1.0;  out = 5.0;  cw = 1.25;  cr = 0.10 }
}

$script:CodexPricesAsOf = '2026-06-26'
$script:CodexPrices = @{
    'gpt-5.5' = @{ in = 5.00; cachedIn = 0.50; out = 30.00 }
    default   = @{ in = 5.00; cachedIn = 0.50; out = 30.00 }
}

# ---------------------------------------------------------------------------
# User-Agent detection
# ---------------------------------------------------------------------------
$script:UA = 'claude-code/2.1.0'
try { $v = (& claude --version) 2>$null; if ($v -match '(\d+\.\d+\.\d+)') { $script:UA = "claude-code/$($matches[1])" } } catch { }

# ---------------------------------------------------------------------------
# Color themes
# ---------------------------------------------------------------------------
$script:Themes = [ordered]@{
    'Deep Space' = @{
        BgC1 = '#0F172A'; BgC2 = '#080C18'; BorderC1 = '#1E3A5F'; GssLabelFg = '#5C8AAA'
        FivehColors = '#0369A1','#38BDF8'
        WeekColors  = '#C2410C','#FB923C'
        FabColors   = '#6D28D9','#C084FC'
        OpusColors  = '#92400E','#FDE047'
        FivehFg     = '#38BDF8'
        WeekFg      = '#FB923C'
        FabFg       = '#C084FC'
        OpusFg      = '#FDE047'
        Stripe      = '#38BDF8','#818CF8','#E879F9','#FB923C'
    }
    'Global Shop' = @{
        BgC1 = '#081508'; BgC2 = '#040C06'; BorderC1 = '#1A5C2A'; GssLabelFg = '#3DC95A'
        FivehColors = '#1A5C2A','#2D9F48'
        WeekColors  = '#1A5C2A','#4AE068'
        FabColors   = '#166534','#86EFAC'
        OpusColors  = '#92400E','#FDE047'
        FivehFg     = '#2D9F48'
        WeekFg      = '#4AE068'
        FabFg       = '#86EFAC'
        OpusFg      = '#FDE047'
        Stripe      = '#1A5C2A','#2D9F48','#4AE068','#86EFAC'
    }
    'Ocean' = @{
        BgC1 = '#0F1F2E'; BgC2 = '#091420'; BorderC1 = '#1A4060'; GssLabelFg = '#5C8AAA'
        FivehColors = '#0F766E','#2DD4BF'
        WeekColors  = '#9D174D','#FB7185'
        FabColors   = '#1E40AF','#93C5FD'
        OpusColors  = '#92400E','#FCD34D'
        FivehFg     = '#2DD4BF'
        WeekFg      = '#FB7185'
        FabFg       = '#93C5FD'
        OpusFg      = '#FCD34D'
        Stripe      = '#2DD4BF','#93C5FD','#FB7185','#FCD34D'
    }
    'Mono' = @{
        BgC1 = '#111111'; BgC2 = '#080808'; BorderC1 = '#2A2A2A'; GssLabelFg = '#909090'
        FivehColors = '#1E3A5F','#94A3B8'
        WeekColors  = '#1E3A5F','#94A3B8'
        FabColors   = '#1E3A5F','#94A3B8'
        OpusColors  = '#1E3A5F','#94A3B8'
        FivehFg     = '#94A3B8'
        WeekFg      = '#94A3B8'
        FabFg       = '#94A3B8'
        OpusFg      = '#94A3B8'
        Stripe      = '#334155','#64748B','#94A3B8','#64748B'
    }
    'Black & White' = @{
        BgC1 = '#0A0A0A'; BgC2 = '#000000'; BorderC1 = '#2A2A2A'; GssLabelFg = '#B0B0B0'
        FivehColors = '#3A3A3A','#E8E8E8'
        WeekColors  = '#3A3A3A','#E8E8E8'
        FabColors   = '#3A3A3A','#E8E8E8'
        OpusColors  = '#3A3A3A','#9A9A9A'
        FivehFg     = '#E8E8E8'
        WeekFg      = '#E8E8E8'
        FabFg       = '#E8E8E8'
        OpusFg      = '#E8E8E8'
        Stripe      = '#E8E8E8','#B0B0B0','#7A7A7A','#4A4A4A'
    }
}

# ---------------------------------------------------------------------------
# Default config
# ---------------------------------------------------------------------------
$script:Cfg = @{
    Left        = $null
    Top         = $null
    Opacity     = 1.0
    StartHidden = $false
    ShowStats   = $true
    Theme       = 'Deep Space'
    ShowAlerts  = $true    # NEW: enable threshold balloon alerts
    ShowGraph   = $false   # NEW: show history sparkline (off by default to keep panel compact)
    AutoCheckUpdates = $true
    LastNotifiedUpdateVersion = $null
}
