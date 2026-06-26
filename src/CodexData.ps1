# CodexData.ps1 - Codex session parsing and usage cost estimation

if (-not $script:CodexSessionsDir) {
    $script:CodexSessionsDir = Join-Path $env:USERPROFILE '.codex\sessions'
}

$script:CodexStats = $null
$script:CodexStatsFileCache = @{}

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

function Measure-CodexStats([object[]]$records, [datetime]$today) {
    $val = 0.0; $tin = 0L; $tout = 0L
    $sessions = [System.Collections.Generic.HashSet[string]]::new()
    $tMsg = 0; $tTok = 0L

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

function Get-CodexStats {
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

    foreach ($file in $files) {
        $stamp = "$($file.LastWriteTimeUtc.Ticks):$($file.Length)"
        $cached = $script:CodexStatsFileCache[$file.FullName]

        if ($cached -and $cached.Stamp -eq $stamp) {
            foreach ($r in $cached.Records) {
                $allRecords.Add($r)
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
                if ($usage) {
                    $lastUsage = $usage
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

        $script:CodexStatsFileCache[$file.FullName] = @{ Stamp = $stamp; Records = $fileRecords }

        foreach ($r in $fileRecords) {
            $allRecords.Add($r)
        }
    }

    try {
        $script:CodexStats = Measure-CodexStats $allRecords.ToArray() (Get-Date)
    } catch {
        Write-CodexLog "Get-CodexStats: Measure-CodexStats failed - $($_.Exception.Message)"
    }
}
