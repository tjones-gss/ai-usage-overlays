# CodexData.ps1 - Codex session parsing and usage cost estimation

if (-not $script:CodexSessionsDir) {
    $script:CodexSessionsDir = Join-Path $env:USERPROFILE '.codex\sessions'
}

$script:CodexStats = $null
$script:CodexStatsFileCache = @{}

function Convert-CodexCacheDate {
    param($Value)

    if (-not $Value) { return $null }
    if ($Value -is [datetime]) { return $Value }

    try {
        return [System.DateTimeOffset]::Parse([string]$Value).LocalDateTime
    } catch {
        return $null
    }
}

function Convert-CodexCacheRecords {
    param($Records)

    $converted = [System.Collections.Generic.List[object]]::new()
    if (-not $Records) { return $converted }

    foreach ($r in @($Records)) {
        $date = Convert-CodexCacheDate $r.Date
        if (-not $date) { continue }

        $converted.Add(@{
            Model     = [string]$r.Model
            Date      = $date
            In        = [long]$r.In
            CachedIn  = [long]$r.CachedIn
            Out       = [long]$r.Out
            SessionId = [string]$r.SessionId
        })
    }

    return $converted
}

function Import-CodexStatsFileCache {
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
                Stamp         = [string]$entry.Stamp
                Records       = Convert-CodexCacheRecords $entry.Records
                LastTokenDate = Convert-CodexCacheDate $entry.LastTokenDate
                RateLimits    = $entry.RateLimits
            }
        }

        $script:CodexStatsFileCache = $loaded
    } catch {
        Write-CodexLog "Get-CodexStats: failed to load cache $CachePath - $($_.Exception.Message)"
    }
}

function Export-CodexStatsFileCache {
    param([string]$CachePath)

    if (-not $CachePath) { return }

    try {
        $script:CodexStatsFileCache |
            ConvertTo-Json -Depth 12 |
            Set-Content -Path $CachePath -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-CodexLog "Get-CodexStats: failed to save cache $CachePath - $($_.Exception.Message)"
    }
}

function Write-CodexLog {
    param([string]$Message)
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log $Message
    }
}

function Convert-CodexTimestamp {
    param($Value)

    if (-not $Value) { return $null }

    try {
        if ($Value -is [string]) {
            return [System.DateTimeOffset]::Parse($Value).LocalDateTime
        }
        return ([datetime]$Value).ToLocalTime()
    } catch {
        return $null
    }
}

function Convert-CodexEpochSeconds {
    param($Value)

    if ($null -eq $Value) { return $null }

    try {
        return [System.DateTimeOffset]::FromUnixTimeSeconds([long][double]$Value).LocalDateTime
    } catch {
        return $null
    }
}

function Estimate-CodexCost([string]$model, $v) {
    if (-not $script:CodexPrices) { throw 'Estimate-CodexCost: $script:CodexPrices not loaded - dot-source Config.ps1 first.' }

    if ($model -match '^gpt-5') {
        if ($script:CodexPrices.ContainsKey($model)) {
            $tier = $model
        } else {
            $tier = 'gpt-5.5'
        }
    } else {
        $tier = 'default'
        if ($model -and (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
            Write-Log "Unknown Codex model '$model' - falling back to default pricing (verify prices)"
        }
    }

    if (-not $script:CodexPrices.ContainsKey($tier)) {
        $tier = 'default'
    }

    $p = $script:CodexPrices[$tier]
    $inputTokens = [double]$v.inputTokens
    $cachedInputTokens = [double]$v.cachedInputTokens
    $outputTokens = [double]$v.outputTokens
    $uncachedInputTokens = [Math]::Max(0.0, $inputTokens - $cachedInputTokens)

    return ($uncachedInputTokens / 1e6 * $p.in) +
           ($cachedInputTokens   / 1e6 * $p.cachedIn) +
           ($outputTokens        / 1e6 * $p.out)
}

function Measure-CodexStats([object[]]$records, [datetime]$today, $rateLimits = $null) {
    $val = 0.0; $tin = 0L; $tout = 0L
    $sessions = [System.Collections.Generic.HashSet[string]]::new()
    $tMsg = 0; $tTok = 0L
    $fiveHourPct = $null
    $fiveHourResetsAt = $null
    $weekPct = $null
    $weekResetsAt = $null
    $currentModel = $null
    $latestModelDate = $null

    foreach ($r in $records) {
        $v = @{
            inputTokens       = [long]$r.In
            cachedInputTokens = [long]$r.CachedIn
            outputTokens      = [long]$r.Out
        }
        $val  += Estimate-CodexCost $r.Model $v
        $tin  += [long]$r.In
        $tout += [long]$r.Out
        [void]$sessions.Add([string]$r.SessionId)

        if ($r.Date.Date -eq $today.Date) {
            $tMsg++
            $tTok += [long]$r.In + [long]$r.Out
        }

        # Current model = the model of the most recent session that named one
        # ('default' is the fallback for sessions with no turn_context).
        if ($r.Model -and $r.Model -ne 'default' -and ((-not $latestModelDate) -or ($r.Date -gt $latestModelDate))) {
            $latestModelDate = $r.Date
            $currentModel = $r.Model
        }
    }

    if ($rateLimits) {
        $primary = $rateLimits.primary
        if ($primary) {
            if ($null -ne $primary.used_percent) {
                $fiveHourPct = [double]$primary.used_percent
            }
            if ($null -ne $primary.resets_at) {
                $fiveHourResetsAt = Convert-CodexEpochSeconds $primary.resets_at
            }
        }

        $secondary = $rateLimits.secondary
        if ($secondary) {
            if ($null -ne $secondary.used_percent) {
                $weekPct = [double]$secondary.used_percent
            }
            if ($null -ne $secondary.resets_at) {
                $weekResetsAt = Convert-CodexEpochSeconds $secondary.resets_at
            }
        }
    }

    return @{
        ValueUSD         = $val
        InTokens         = $tin
        OutTokens        = $tout
        Sessions         = $sessions.Count
        Messages         = $records.Count
        TodayMsg         = $tMsg
        TodayTok         = $tTok
        FiveHourPct      = $fiveHourPct
        FiveHourResetsAt = $fiveHourResetsAt
        WeekPct          = $weekPct
        WeekResetsAt     = $weekResetsAt
        Model            = $currentModel
        LastComputed     = (Get-Date -Format 'yyyy-MM-dd HH:mm')
    }
}

function Get-CodexStats {
    $cachePath = Join-Path $script:AppDir 'codex-cache.json'
    Import-CodexStatsFileCache $cachePath

    if (-not (Test-Path $script:CodexSessionsDir)) {
        Write-CodexLog 'Get-CodexStats: ~/.codex/sessions not found - no session data'
        return
    }

    try {
        $files = Get-ChildItem $script:CodexSessionsDir -Recurse -Filter '*.jsonl' -File -ErrorAction Stop
    } catch {
        Write-CodexLog "Get-CodexStats: failed to enumerate sessions - $($_.Exception.Message)"
        return
    }

    $allRecords = [System.Collections.Generic.List[object]]::new()
    $latestRateLimits = $null
    $latestTokenDate = $null
    $activeCache = @{}

    foreach ($file in $files) {
        $stamp = "$($file.LastWriteTimeUtc.Ticks):$($file.Length)"
        $cached = $script:CodexStatsFileCache[$file.FullName]

        if ($cached -and $cached.Stamp -eq $stamp) {
            $activeCache[$file.FullName] = $cached
            foreach ($r in $cached.Records) {
                $allRecords.Add($r)
            }
            if ($cached.LastTokenDate -and ((-not $latestTokenDate) -or ($cached.LastTokenDate -gt $latestTokenDate))) {
                $latestTokenDate = $cached.LastTokenDate
                $latestRateLimits = $cached.RateLimits
            }
            continue
        }

        $fileRecords = [System.Collections.Generic.List[object]]::new()
        try {
            $lines = Get-Content $file.FullName -Encoding UTF8 -ErrorAction Stop
        } catch {
            Write-CodexLog "Get-CodexStats: skipping unreadable file $($file.FullName) - $($_.Exception.Message)"
            continue
        }

        $lastUsage = $null
        $lastModel = $null
        $sessionId = $null
        $sessionDate = $null
        $lastTokenDate = $null
        $lastRateLimits = $null

        foreach ($line in $lines) {
            if (-not $line) { continue }

            try {
                $o = $line | ConvertFrom-Json -ErrorAction Stop
            } catch {
                continue
            }

            if ($o.type -eq 'session_meta') {
                if ($o.payload.session_id) {
                    $sessionId = [string]$o.payload.session_id
                }
                $metaDate = Convert-CodexTimestamp $o.payload.timestamp
                if (-not $metaDate) {
                    $metaDate = Convert-CodexTimestamp $o.timestamp
                }
                if ($metaDate) {
                    $sessionDate = $metaDate
                }
            } elseif ($o.type -eq 'turn_context') {
                if ($o.payload.model) {
                    $lastModel = [string]$o.payload.model
                }
            } elseif (($o.type -eq 'token_count') -or
                      (($o.type -eq 'event_msg') -and ($o.payload.type -eq 'token_count'))) {
                $usage = $o.payload.info.total_token_usage
                $limits = $o.payload.rate_limits
                if (-not $limits) {
                    $limits = $o.rate_limits
                }
                if ($usage) {
                    $lastUsage = $usage
                    $lastRateLimits = $limits
                    $tokenDate = Convert-CodexTimestamp $o.timestamp
                    if ($tokenDate) {
                        $lastTokenDate = $tokenDate
                    }
                }
            }
        }

        if ($lastUsage) {
            $recordDate = $sessionDate
            if (-not $recordDate) { $recordDate = $lastTokenDate }
            if (-not $recordDate) { $recordDate = $file.LastWriteTime }

            $modelName = $lastModel
            if (-not $modelName) { $modelName = 'default' }

            $sessionName = $sessionId
            if (-not $sessionName) { $sessionName = $file.BaseName }

            $fileRecords.Add(@{
                Model     = $modelName
                Date      = $recordDate
                In        = [long]$lastUsage.input_tokens
                CachedIn  = [long]$lastUsage.cached_input_tokens
                Out       = [long]$lastUsage.output_tokens
                SessionId = [string]$sessionName
            })
        }

        $fileTokenDate = $lastTokenDate
        if ($lastUsage) {
            if (-not $fileTokenDate) { $fileTokenDate = $sessionDate }
            if (-not $fileTokenDate) { $fileTokenDate = $file.LastWriteTime }

            if ((-not $latestTokenDate) -or ($fileTokenDate -gt $latestTokenDate)) {
                $latestTokenDate = $fileTokenDate
                $latestRateLimits = $lastRateLimits
            }
        }

        $activeCache[$file.FullName] = @{
            Stamp         = $stamp
            Records       = $fileRecords
            LastTokenDate = $fileTokenDate
            RateLimits    = $lastRateLimits
        }

        foreach ($r in $fileRecords) {
            $allRecords.Add($r)
        }
    }

    $script:CodexStatsFileCache = $activeCache
    Export-CodexStatsFileCache $cachePath

    try {
        $script:CodexStats = Measure-CodexStats $allRecords.ToArray() (Get-Date) $latestRateLimits
    } catch {
        Write-CodexLog "Get-CodexStats: Measure-CodexStats failed - $($_.Exception.Message)"
    }
}
