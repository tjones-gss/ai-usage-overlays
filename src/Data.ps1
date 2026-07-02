# Data.ps1 — data fetchers: Get-Usage, Get-Stats, and the Write-Log diagnostic helper

function Write-Log {
    param([string]$Message)
    try {
        $line = '[{0}] {1}' -f (Get-Date -Format 's'), $Message
        Add-Content -Path $script:ErrLog -Value $line -Encoding UTF8
    } catch { }  # never throw from a logger
}

# ---------------------------------------------------------------------------
# Get-ScopedLimit — pulls a per-model weekly limit out of the API's limits[]
# array by its scope display name (e.g. 'Fable') and returns an object shaped
# like the legacy top-level seven_day_* fields so the UI can consume it
# uniformly. Returns $null when the model isn't present.
# ---------------------------------------------------------------------------
function Get-ScopedLimit([object]$resp, [string]$displayName) {
    if (-not $resp.limits) { return $null }
    foreach ($lim in $resp.limits) {
        if ($lim.scope.model.display_name -eq $displayName) {
            return [PSCustomObject]@{
                utilization = [double]$lim.percent
                resets_at   = $lim.resets_at
            }
        }
    }
    return $null
}

function Get-Usage {
    param([int]$TimeoutSec = 20)

    $tok = $null
    try { $tok = (Get-Content $script:CredPath -Raw | ConvertFrom-Json).claudeAiOauth.accessToken } catch {
        $script:State.Status = 'error'; $script:State.Message = 'No credentials file'; return
    }
    if (-not $tok) { $script:State.Status = 'auth'; $script:State.Message = 'Not logged in'; return }
    try {
        $resp = Invoke-RestMethod 'https://api.anthropic.com/api/oauth/usage' -TimeoutSec $TimeoutSec -Headers @{
            Authorization = "Bearer $tok"; 'anthropic-beta' = 'oauth-2025-04-20'; 'User-Agent' = $script:UA
        }
        # Fable (and future per-model caps) live in the limits[] array as
        # weekly_scoped entries, not as top-level seven_day_* fields. Surface
        # Fable under the legacy field shape so the rest of the app is uniform.
        $fable = Get-ScopedLimit $resp 'Fable'
        $resp | Add-Member -NotePropertyName seven_day_fable -NotePropertyValue $fable -Force
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

# ---------------------------------------------------------------------------
# Measure-Stats — pure aggregator, takes pre-parsed records and a reference
# date; returns the same hashtable shape consumed by Update-UI.
#
# Each record must have:
#   Model     — model name string (e.g. 'claude-opus-4-8')
#   Date      — [datetime] (local date of the message)
#   In        — [long] input tokens
#   Out       — [long] output tokens
#   CacheW    — [long] cache-creation tokens
#   CacheR    — [long] cache-read tokens
#   SessionId — session GUID string
#   Key       — dedup key (already applied upstream by Get-Stats)
# ---------------------------------------------------------------------------
function Measure-Stats([object[]]$records, [datetime]$today) {
    $val = 0.0; $tin = 0L; $tout = 0L
    $sessions = [System.Collections.Generic.HashSet[string]]::new()
    $tMsg = 0; $tTok = 0L

    foreach ($r in $records) {
        $v = @{
            inputTokens              = $r.In
            outputTokens             = $r.Out
            cacheCreationInputTokens = $r.CacheW
            cacheReadInputTokens     = $r.CacheR
        }
        $val  += Estimate-Cost $r.Model $v
        $tin  += [long]$r.In
        $tout += [long]$r.Out
        [void]$sessions.Add([string]$r.SessionId)

        if ($r.Date.Date -eq $today.Date) {
            $tMsg++
            $tTok += [long]$r.In + [long]$r.Out
        }
    }

    return @{
        ValueUSD     = $val
        InTokens     = $tin
        OutTokens    = $tout
        Sessions     = $sessions.Count
        Messages     = $records.Count
        TodayMsg     = $tMsg
        TodayTok     = $tTok
        LastComputed = (Get-Date -Format 'yyyy-MM-dd HH:mm')
    }
}

# Per-file parse cache: path → @{ Stamp; Records }
# Stamp = "$($file.LastWriteTimeUtc.Ticks):$($file.Length)"
$script:StatsFileCache = @{}

function Convert-StatsCacheDate {
    param($Value)

    if (-not $Value) { return $null }
    if ($Value -is [datetime]) { return $Value }

    try {
        return [System.DateTimeOffset]::Parse([string]$Value).LocalDateTime
    } catch {
        return $null
    }
}

function Convert-StatsCacheRecords {
    param($Records)

    $converted = [System.Collections.Generic.List[object]]::new()
    if (-not $Records) { return $converted }

    foreach ($r in @($Records)) {
        $date = Convert-StatsCacheDate $r.Date
        if (-not $date) { continue }

        $converted.Add(@{
            Model     = [string]$r.Model
            Date      = $date
            In        = [long]$r.In
            Out       = [long]$r.Out
            CacheW    = [long]$r.CacheW
            CacheR    = [long]$r.CacheR
            SessionId = [string]$r.SessionId
            Key       = [string]$r.Key
        })
    }

    return $converted
}

function Import-StatsFileCache {
    param([string]$CachePath)

    if (-not $CachePath -or -not (Test-Path $CachePath)) { return }

    try {
        $raw = Get-Content $CachePath -Raw -Encoding UTF8 -ErrorAction Stop
        if (-not $raw) { return }

        $json = $raw | ConvertFrom-Json -ErrorAction Stop
        $loaded = @{}

        foreach ($prop in $json.PSObject.Properties) {
            $entry = $prop.Value
            if (-not $entry -or -not $entry.Stamp) { continue }

            $loaded[$prop.Name] = @{
                Stamp   = [string]$entry.Stamp
                Records = Convert-StatsCacheRecords $entry.Records
            }
        }

        $script:StatsFileCache = $loaded
    } catch {
        Write-Log "Get-Stats: failed to load cache $CachePath — $($_.Exception.Message)"
    }
}

function Export-StatsFileCache {
    param([string]$CachePath)

    if (-not $CachePath) { return }

    try {
        $script:StatsFileCache |
            ConvertTo-Json -Depth 8 |
            Set-Content -Path $CachePath -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-Log "Get-Stats: failed to save cache $CachePath — $($_.Exception.Message)"
    }
}

function Get-Stats {
    $cachePath = Join-Path $script:AppDir 'stats-cache.json'
    Import-StatsFileCache $cachePath

    $projDir = Join-Path $env:USERPROFILE '.claude\projects'
    if (-not (Test-Path $projDir)) {
        Write-Log 'Get-Stats: ~/.claude/projects not found — no transcript data'
        return
    }

    try {
        $files = Get-ChildItem $projDir -Recurse -Filter '*.jsonl' -File -ErrorAction Stop
    } catch {
        Write-Log "Get-Stats: failed to enumerate transcripts — $($_.Exception.Message)"
        return
    }

    # Deduplicate across all files using msgId:requestId key
    $seen  = [System.Collections.Generic.HashSet[string]]::new()
    $allRecords = [System.Collections.Generic.List[object]]::new()
    $activeCache = @{}

    foreach ($file in $files) {
        $stamp = "$($file.LastWriteTimeUtc.Ticks):$($file.Length)"
        $cached = $script:StatsFileCache[$file.FullName]

        if ($cached -and $cached.Stamp -eq $stamp) {
            $activeCache[$file.FullName] = $cached
            # Reuse cached parse — only add records whose keys haven't been seen yet
            foreach ($r in $cached.Records) {
                if ($seen.Add($r.Key)) { $allRecords.Add($r) }
            }
            continue
        }

        # Parse this file fresh
        $fileRecords = [System.Collections.Generic.List[object]]::new()
        try {
            $lines = Get-Content $file.FullName -Encoding UTF8 -ErrorAction Stop
        } catch {
            Write-Log "Get-Stats: skipping unreadable file $($file.FullName) — $($_.Exception.Message)"
            continue
        }

        foreach ($line in $lines) {
            if (-not $line) { continue }
            try {
                $o = $line | ConvertFrom-Json -ErrorAction Stop
            } catch { continue }

            # Only assistant messages with usage data
            if ($o.type -ne 'assistant') { continue }
            $u = $o.message.usage
            if (-not $u) { continue }

            $key = "$($o.message.id):$($o.requestId)"
            $ts  = $o.timestamp
            if (-not $ts) { continue }
            # PS7 ConvertFrom-Json auto-converts ISO timestamps to [datetime]; PS5 leaves them as strings.
            # [System.DateTimeOffset]::Parse handles the string case; the else handles PS7's [datetime].
            $localDate = if ($ts -is [string]) { [System.DateTimeOffset]::Parse($ts).LocalDateTime } else { ([datetime]$ts).ToLocalTime() }

            $r = @{
                Model     = [string]$o.message.model
                Date      = $localDate
                In        = [long]$u.input_tokens
                Out       = [long]$u.output_tokens
                CacheW    = [long]$u.cache_creation_input_tokens
                CacheR    = [long]$u.cache_read_input_tokens
                SessionId = [string]$o.sessionId
                Key       = $key
            }
            $fileRecords.Add($r)
        }

        $activeCache[$file.FullName] = @{ Stamp = $stamp; Records = $fileRecords }

        foreach ($r in $fileRecords) {
            if ($seen.Add($r.Key)) { $allRecords.Add($r) }
        }
    }

    $script:StatsFileCache = $activeCache
    Export-StatsFileCache $cachePath

    try {
        $script:Stats = Measure-Stats $allRecords.ToArray() (Get-Date)
    } catch {
        Write-Log "Get-Stats: Measure-Stats failed — $($_.Exception.Message)"
    }
}
