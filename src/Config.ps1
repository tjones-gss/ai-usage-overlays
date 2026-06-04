# Config.ps1 — shared constants, pricing table, color themes, and default settings

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
$script:PollSeconds    = 180
$script:TickSeconds    = 30
$script:BarTrackWidth  = 250.0
$script:WarnPct        = 80
$script:CritPct        = 95

# ---------------------------------------------------------------------------
# Pricing table
# ---------------------------------------------------------------------------
$script:PricesAsOf = '2026-06-01'
$script:Prices = @{
    opus   = @{ in = 15.0; out = 75.0; cw = 18.75; cr = 1.50 }
    sonnet = @{ in = 3.0;  out = 15.0; cw = 3.75;  cr = 0.30 }
    haiku  = @{ in = 1.0;  out = 5.0;  cw = 1.25;  cr = 0.10 }
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
        FivehColors = '#0369A1','#38BDF8'
        WeekColors  = '#C2410C','#FB923C'
        SonColors   = '#6D28D9','#C084FC'
        OpusColors  = '#92400E','#FDE047'
        FivehFg     = '#38BDF8'
        WeekFg      = '#FB923C'
        SonFg       = '#C084FC'
        OpusFg      = '#FDE047'
        Stripe      = '#38BDF8','#818CF8','#E879F9','#FB923C'
    }
    'Ocean' = @{
        FivehColors = '#0F766E','#2DD4BF'
        WeekColors  = '#9D174D','#FB7185'
        SonColors   = '#1E40AF','#93C5FD'
        OpusColors  = '#92400E','#FCD34D'
        FivehFg     = '#2DD4BF'
        WeekFg      = '#FB7185'
        SonFg       = '#93C5FD'
        OpusFg      = '#FCD34D'
        Stripe      = '#2DD4BF','#93C5FD','#FB7185','#FCD34D'
    }
    'Neon' = @{
        FivehColors = '#BE185D','#F472B6'
        WeekColors  = '#15803D','#4ADE80'
        SonColors   = '#1D4ED8','#60A5FA'
        OpusColors  = '#B45309','#FDE047'
        FivehFg     = '#F472B6'
        WeekFg      = '#4ADE80'
        SonFg       = '#60A5FA'
        OpusFg      = '#FDE047'
        Stripe      = '#F472B6','#4ADE80','#60A5FA','#FDE047'
    }
    'Mono' = @{
        FivehColors = '#1E3A5F','#94A3B8'
        WeekColors  = '#1E3A5F','#94A3B8'
        SonColors   = '#1E3A5F','#94A3B8'
        OpusColors  = '#1E3A5F','#94A3B8'
        FivehFg     = '#94A3B8'
        WeekFg      = '#94A3B8'
        SonFg       = '#94A3B8'
        OpusFg      = '#94A3B8'
        Stripe      = '#334155','#64748B','#94A3B8','#64748B'
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
}
