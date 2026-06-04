# History.ps1 — usage history ring buffer and burn-rate / ETA projection

$script:HistoryPath   = Join-Path $script:AppDir 'overlay-history.json'
$script:History       = [System.Collections.Generic.List[object]]::new()
$script:HistoryMaxLen = 480   # ~24h at 3-min polling intervals

function Load-History {
    try {
        if (-not (Test-Path $script:HistoryPath)) { return }
        $raw = Get-Content $script:HistoryPath -Raw | ConvertFrom-Json
        if ($raw -is [array]) {
            $script:History = [System.Collections.Generic.List[object]]($raw)
        }
    } catch {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log "Load-History failed: $($_.Exception.Message)"
        }
    }
}

function Add-HistorySample([object]$data) {
    # $data is the API response object from Get-Usage ($script:State.Data)
    $sample = [PSCustomObject]@{
        t               = (Get-Date -Format 'o')  # ISO 8601
        five_hour       = if ($data.five_hour)        { [double]$data.five_hour.utilization }        else { $null }
        seven_day       = if ($data.seven_day)         { [double]$data.seven_day.utilization }         else { $null }
        seven_day_sonnet = if ($data.seven_day_sonnet) { [double]$data.seven_day_sonnet.utilization }  else { $null }
        seven_day_opus  = if ($data.seven_day_opus)   { [double]$data.seven_day_opus.utilization }    else { $null }
    }
    $script:History.Add($sample)
    # Trim to ring buffer max
    while ($script:History.Count -gt $script:HistoryMaxLen) {
        $script:History.RemoveAt(0)
    }
}

function Save-History {
    try {
        $script:History | ConvertTo-Json -Depth 3 | Set-Content -Path $script:HistoryPath -Encoding UTF8
    } catch {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log "Save-History failed: $($_.Exception.Message)"
        }
    }
}

function Get-Eta {
    param(
        [object[]]$Samples,
        [string]$MetricKey
    )
    # Need at least 3 samples to fit a line
    if ($null -eq $Samples -or $Samples.Count -lt 3) { return $null }

    # Filter to samples with a non-null value for this metric, within last 60 minutes
    $cutoff = (Get-Date).AddMinutes(-60)
    $recent = @($Samples | Where-Object {
        $null -ne $_.$MetricKey -and
        [System.DateTimeOffset]::Parse($_.t).LocalDateTime -ge $cutoff
    })
    if ($recent.Count -lt 3) { return $null }

    # Convert timestamps to minutes-since-first for linear regression
    $t0 = [System.DateTimeOffset]::Parse($recent[0].t)
    $xs = @($recent | ForEach-Object { ([System.DateTimeOffset]::Parse($_.t) - $t0).TotalMinutes })
    $ys = @($recent | ForEach-Object { [double]($_.$MetricKey) })

    # Simple linear regression: y = a + b*x
    $n    = $xs.Count
    $sumX = ($xs | Measure-Object -Sum).Sum
    $sumY = ($ys | Measure-Object -Sum).Sum
    $sumXY = 0; for ($i = 0; $i -lt $n; $i++) { $sumXY += $xs[$i] * $ys[$i] }
    $sumX2 = 0; for ($i = 0; $i -lt $n; $i++) { $sumX2 += $xs[$i] * $xs[$i] }
    $denom = $n * $sumX2 - $sumX * $sumX
    if ([math]::Abs($denom) -lt 1e-10) { return $null }  # perfectly flat / single point

    $b = ($n * $sumXY - $sumX * $sumY) / $denom  # slope (util % per minute)
    if ($b -le 0) { return $null }  # not increasing — no ETA

    # Current util = last sample's value
    $currentUtil = $ys[-1]
    if ($currentUtil -ge 100) { return 0 }  # already at limit

    # Minutes to reach 100%
    $a = ($sumY - $b * $sumX) / $n  # intercept
    $etaMinutes = (100.0 - $currentUtil) / $b
    if ($etaMinutes -gt 1440) { return $null }  # more than 24h away — not useful
    return [int][math]::Ceiling($etaMinutes)
}
