# UnifiedState.ps1 - settings persistence, window positioning, and clipboard export

$script:UnifiedSectionKeys = @('claude', 'codex', 'cursor')

if (-not $script:Cfg) { $script:Cfg = @{} }

$script:UnifiedCfgDefaults = @{
    Left        = $null
    Top         = $null
    Opacity     = 1.0
    StartHidden = $false
    ShowStats   = $true
    Theme       = 'Deep Space'
    ShowAlerts  = $true
    ShowGraph   = $false
    AutoCheckUpdates = $true
    LastNotifiedUpdateVersion = $null
}

function ConvertTo-UnifiedSectionsMap($value) {
    $sections = @{}
    foreach ($key in $script:UnifiedSectionKeys) { $sections[$key] = $true }

    if ($null -eq $value) { return $sections }

    if ($value -is [System.Collections.IDictionary]) {
        foreach ($key in $script:UnifiedSectionKeys) {
            if ($value.Contains($key)) { $sections[$key] = [bool]$value[$key] }
        }
        return $sections
    }

    foreach ($key in $script:UnifiedSectionKeys) {
        $prop = $value.PSObject.Properties[$key]
        if ($prop) { $sections[$key] = [bool]$prop.Value }
    }
    return $sections
}

function Initialize-UnifiedCfg {
    foreach ($key in $script:UnifiedCfgDefaults.Keys) {
        if (-not $script:Cfg.ContainsKey($key)) {
            $script:Cfg[$key] = $script:UnifiedCfgDefaults[$key]
        }
    }
    $script:Cfg['Sections'] = ConvertTo-UnifiedSectionsMap $script:Cfg['Sections']
}

Initialize-UnifiedCfg

function Save-UnifiedState {
    try {
        Initialize-UnifiedCfg
        if ($script:window) {
            $script:Cfg.Left = $script:window.Left
            $script:Cfg.Top  = $script:window.Top
        }
        $script:Cfg | ConvertTo-Json -Depth 6 | Set-Content -Path $script:StatePath -Encoding UTF8
    } catch {
        try { Write-Log "Save-UnifiedState failed: $($_.Exception.Message)" } catch { }
    }
}

function Load-UnifiedState {
    try {
        Initialize-UnifiedCfg
        if (-not (Test-Path $script:StatePath)) { return }

        $s = Get-Content $script:StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($key in @('Left', 'Top', 'Opacity', 'StartHidden', 'ShowStats', 'Theme', 'ShowAlerts', 'ShowGraph', 'AutoCheckUpdates', 'LastNotifiedUpdateVersion')) {
            $prop = $s.PSObject.Properties[$key]
            if ($prop -and $null -ne $prop.Value) { $script:Cfg[$key] = $prop.Value }
        }

        $sectionsProp = $s.PSObject.Properties['Sections']
        if ($sectionsProp) {
            $script:Cfg['Sections'] = ConvertTo-UnifiedSectionsMap $sectionsProp.Value
        }
        Initialize-UnifiedCfg
    } catch {
        try { Write-Log "Load-UnifiedState failed: $($_.Exception.Message)" } catch { }
    }
}

function Apply-UnifiedSettings {
    Initialize-UnifiedCfg

    if ($script:window) {
        $script:window.Opacity = [double]$script:Cfg.Opacity

        $statsPanel = $script:window.FindName('statsPanel')
        if ($statsPanel) {
            $statsPanel.Visibility = if ($script:Cfg.ShowStats) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
        }

        $sparkRow = $script:window.FindName('sparkRow')
        if ($sparkRow) {
            $sparkRow.Visibility = if ($script:Cfg.ShowGraph) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
        }
    }

    foreach ($key in $script:UnifiedSectionKeys) {
        Set-SectionVisible $key ([bool]$script:Cfg.Sections[$key])
    }

    Apply-UnifiedTheme $script:Cfg.Theme
}

function Test-FiniteNumber($value) {
    if ($null -eq $value) { return $false }
    try {
        $d = [double]$value
        return -not [double]::IsNaN($d) -and -not [double]::IsInfinity($d)
    } catch {
        return $false
    }
}

function Get-WindowDimension([string]$name) {
    $actualName = "Actual$name"
    $candidates = @(
        $script:window.$actualName,
        $script:window.$name,
        $script:window.RenderSize.$name,
        $script:window.DesiredSize.$name
    )

    foreach ($candidate in $candidates) {
        if ((Test-FiniteNumber $candidate) -and [double]$candidate -gt 0) {
            return [double]$candidate
        }
    }

    return 0.0
}

function ConvertFrom-ScreenWorkArea {
    param(
        $WorkingArea,
        $TransformFromDevice,
        $ScreenOrigin
    )

    $scaleX = [double]$TransformFromDevice.M11
    $scaleY = [double]$TransformFromDevice.M22

    if ($ScreenOrigin -and (Test-FiniteNumber $script:window.Left) -and (Test-FiniteNumber $script:window.Top)) {
        $left = [double]$script:window.Left + (([double]$WorkingArea.Left - [double]$ScreenOrigin.X) * $scaleX)
        $top  = [double]$script:window.Top  + (([double]$WorkingArea.Top  - [double]$ScreenOrigin.Y) * $scaleY)
        return @{
            Left   = $left
            Top    = $top
            Right  = $left + ([double]$WorkingArea.Width  * $scaleX)
            Bottom = $top  + ([double]$WorkingArea.Height * $scaleY)
        }
    }

    return @{
        Left   = [double]$WorkingArea.Left   * $scaleX
        Top    = [double]$WorkingArea.Top    * $scaleY
        Right  = [double]$WorkingArea.Right  * $scaleX
        Bottom = [double]$WorkingArea.Bottom * $scaleY
    }
}

# Work area (in WPF device-independent units) of the monitor the window is
# currently on. SystemParameters.WorkArea is always primary, so resolve the
# window monitor by HWND and convert the screen pixel rect through DPI.
function Get-WorkArea {
    $src = [System.Windows.PresentationSource]::FromVisual($script:window)
    if ($null -eq $src) {
        $wa = [System.Windows.SystemParameters]::WorkArea
        return @{ Left = $wa.Left; Top = $wa.Top; Right = $wa.Right; Bottom = $wa.Bottom }
    }
    $fromDev = $src.CompositionTarget.TransformFromDevice
    $hwnd    = (New-Object System.Windows.Interop.WindowInteropHelper $script:window).Handle
    $wa      = ([System.Windows.Forms.Screen]::FromHandle($hwnd)).WorkingArea
    $origin  = $null
    try {
        $origin = $script:window.PointToScreen((New-Object System.Windows.Point 0, 0))
    } catch {
        $origin = $null
    }
    return ConvertFrom-ScreenWorkArea $wa $fromDev $origin
}

function Clamp-Position {
    $wa = Get-WorkArea
    $w  = Get-WindowDimension 'Width'
    $h  = Get-WindowDimension 'Height'
    $script:window.Left = [math]::Max($wa.Left, [math]::Min($script:window.Left, $wa.Right  - $w))
    $script:window.Top  = [math]::Max($wa.Top,  [math]::Min($script:window.Top,  $wa.Bottom - $h))
}

function Snap-ToCorner([string]$corner) {
    $wa = Get-WorkArea
    $w  = Get-WindowDimension 'Width'
    $h  = Get-WindowDimension 'Height'
    switch ($corner) {
        'TR' { $script:window.Left = $wa.Right - $w - 16; $script:window.Top = $wa.Top    + 16 }
        'TL' { $script:window.Left = $wa.Left  + 16;      $script:window.Top = $wa.Top    + 16 }
        'BR' { $script:window.Left = $wa.Right - $w - 16; $script:window.Top = $wa.Bottom - $h - 16 }
        'BL' { $script:window.Left = $wa.Left  + 16;      $script:window.Top = $wa.Bottom - $h - 16 }
    }
    Save-UnifiedState
}

function Position-Window {
    if ($script:Positioned) { return }
    $script:Positioned = $true
    Resize-ToContent
    if ($null -ne $script:Cfg.Left) {
        $script:window.Left = [double]$script:Cfg.Left
        $script:window.Top  = [double]$script:Cfg.Top
        Clamp-Position
    } else {
        Snap-ToCorner 'TR'
    }
}

function Get-ClaudeQuotaExportWindowSpecs {
    @(
        [PSCustomObject]@{ Field = 'seven_day_fable';      Label = 'Fable' }
        [PSCustomObject]@{ Field = 'seven_day_opus';       Label = 'Opus' }
        [PSCustomObject]@{ Field = 'seven_day_sonnet';     Label = 'Sonnet' }
        [PSCustomObject]@{ Field = 'seven_day_oauth_apps'; Label = 'OAuth apps' }
        [PSCustomObject]@{ Field = 'seven_day_omelette';   Label = 'Omelette' }
        [PSCustomObject]@{ Field = 'seven_day_cowork';     Label = 'Cowork' }
    )
}

function Format-ClaudeQuotaWindowLine {
    param(
        [string]$Label,
        [object]$Window,
        [switch]$IncludeUtilization
    )

    if (-not $Window) { return $null }

    $used = [math]::Round([double]$Window.utilization)
    $remaining = [math]::Round(100 - [double]$Window.utilization)
    $suffixParts = @()
    if ($IncludeUtilization) { $suffixParts += "$used% used" }
    $reset = Format-Reset $Window.resets_at
    if ($reset) { $suffixParts += $reset }
    $suffix = if ($suffixParts.Count -gt 0) { ' (' + ($suffixParts -join ', ') + ')' } else { '' }

    return ('{0}: {1}% remaining{2}' -f $Label, $remaining, $suffix)
}

function Get-ClaudeQuotaStatLines {
    param(
        [object]$Data,
        [string]$Prefix = 'Claude '
    )

    if (-not $Data) { return @() }

    $lines = @()
    if ($Data.five_hour) {
        $lines += Format-ClaudeQuotaWindowLine "$($Prefix)5-hour" $Data.five_hour
    }
    if ($Data.seven_day) {
        $lines += Format-ClaudeQuotaWindowLine "$($Prefix)weekly" $Data.seven_day
    }
    foreach ($spec in Get-ClaudeQuotaExportWindowSpecs) {
        $window = $Data.PSObject.Properties[$spec.Field].Value
        if ($window) {
            $lines += Format-ClaudeQuotaWindowLine "$Prefix$($spec.Label)" $window -IncludeUtilization
        }
    }
    return $lines
}

function Copy-Stats {
    $d = $script:State.Data
    $s = $script:Stats
    $lines = @("AI Usage Overlay - $(Get-Date -Format 'yyyy-MM-dd HH:mm')")

    if ($d) {
        if ($script:ClaudeIdentity -and $script:ClaudeIdentity.Display) {
            $lines += "Claude account: $($script:ClaudeIdentity.Display)"
        }
        $lines += Get-ClaudeQuotaStatLines $d
    }

    if ($s) {
        $lines += "Claude est. API value: ~$(Fmt-Money $s.ValueUSD) all-time"
        $lines += "Claude tokens: $(Fmt-Tok $s.InTokens) in / $(Fmt-Tok $s.OutTokens) out"
        $lines += "Claude lifetime: $($s.Sessions) sessions / $(Fmt-Tok $s.Messages) msgs"
    }

    if ($script:CodexStats) {
        $cs = $script:CodexStats
        $lines += "Codex est. API value: ~$(Fmt-Money $cs.ValueUSD) all-time"
        $lines += "Codex tokens: $(Fmt-Tok $cs.InTokens) in / $(Fmt-Tok $cs.OutTokens) out"
        $lines += "Codex lifetime: $($cs.Sessions) sessions / $(Fmt-Tok $cs.Messages) msgs"
    }

    if ($script:LocalData) {
        $ld = $script:LocalData
        $lines += "Cursor edits: $($ld.edits30d) (30d) / $($ld.editsToday) today"
        if ($ld.topModel)      { $lines += "Cursor top model: $($ld.topModel) $($ld.topPct)%" }
        if ($ld.linesAccepted) { $lines += "Cursor AI lines accepted (30d): $($ld.linesAccepted)" }
    }

    [System.Windows.Clipboard]::SetText(($lines -join "`n"))
}
