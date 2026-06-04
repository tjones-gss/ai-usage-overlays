# Data.ps1 — data fetchers: Get-Usage, Get-Stats, and the Write-Log diagnostic helper

function Write-Log {
    param([string]$Message)
    try {
        $line = '[{0}] {1}' -f (Get-Date -Format 's'), $Message
        Add-Content -Path $script:ErrLog -Value $line -Encoding UTF8
    } catch { }  # never throw from a logger
}

function Get-Usage {
    $tok = $null
    try { $tok = (Get-Content $script:CredPath -Raw | ConvertFrom-Json).claudeAiOauth.accessToken } catch {
        $script:State.Status = 'error'; $script:State.Message = 'No credentials file'; return
    }
    if (-not $tok) { $script:State.Status = 'auth'; $script:State.Message = 'Not logged in'; return }
    try {
        $resp = Invoke-RestMethod 'https://api.anthropic.com/api/oauth/usage' -TimeoutSec 20 -Headers @{
            Authorization = "Bearer $tok"; 'anthropic-beta' = 'oauth-2025-04-20'; 'User-Agent' = $script:UA
        }
        $script:State.Data = $resp; $script:State.Status = 'ok'
        $script:State.Message = ''; $script:State.LastFetch = (Get-Date -Format 'HH:mm')
        # Record to history ring buffer
        Add-HistorySample $resp
        Save-History
    } catch {
        $code = $null
        if ($_.Exception.Response) { try { $code = [int]$_.Exception.Response.StatusCode } catch { } }
        if     ($code -eq 401) { $script:State.Status = 'auth';  $script:State.Message = 'Auth expired' }
        elseif ($code -eq 429) { $script:State.Status = 'stale'; $script:State.Message = 'Rate limited' }
        else                   { $script:State.Status = 'stale'; $script:State.Message = $_.Exception.Message }
    }
}

function Get-Stats {
    $path = Join-Path $env:USERPROFILE '.claude\stats-cache.json'
    try { $d = Get-Content $path -Raw | ConvertFrom-Json } catch {
        Write-Log "Get-Stats: failed to read stats-cache.json — $($_.Exception.Message)"
        return
    }
    $val = 0.0; $tin = 0L; $tout = 0L
    if ($d.modelUsage) {
        foreach ($m in $d.modelUsage.PSObject.Properties) {
            $val  += Estimate-Cost $m.Name $m.Value
            $tin  += [long]$m.Value.inputTokens
            $tout += [long]$m.Value.outputTokens
        }
    }
    $today = (Get-Date -Format 'yyyy-MM-dd')
    $tMsg = 0; $tTok = 0L
    if ($d.dailyActivity) {
        $da = $d.dailyActivity | Where-Object { (Get-Date $_.date -Format 'yyyy-MM-dd') -eq $today }
        if ($da) { $tMsg = [int]$da.messageCount }
    }
    if ($d.dailyModelTokens) {
        $dt = $d.dailyModelTokens | Where-Object { (Get-Date $_.date -Format 'yyyy-MM-dd') -eq $today }
        if ($dt -and $dt.tokensByModel) {
            foreach ($p in $dt.tokensByModel.PSObject.Properties) { $tTok += [long]$p.Value }
        }
    }
    $script:Stats = @{
        ValueUSD = $val; InTokens = $tin; OutTokens = $tout
        Sessions = [int]$d.totalSessions; Messages = [int]$d.totalMessages
        TodayMsg = $tMsg; TodayTok = $tTok; LastComputed = $d.lastComputedDate
    }
}
