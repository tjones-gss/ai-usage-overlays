# Data.ps1 - data fetchers: Get-Usage, Get-Stats, and the Write-Log diagnostic helper

function Write-Log {
    param([string]$Message)
    try {
        $line = '[{0}] {1}' -f (Get-Date -Format 's'), $Message
        Add-Content -Path $script:ErrLog -Value $line -Encoding UTF8
    } catch { }  # never throw from a logger
}

# ---------------------------------------------------------------------------
# Claude quota window normalization
#
# Anthropic may return some weekly windows as top-level seven_day_* fields and
# some in limits[]. Surface both shapes under stable seven_day_* properties so
# export/history code can serialize them without knowing the payload variant.
# ---------------------------------------------------------------------------
function Get-ClaudeQuotaWindowSpecs {
    @(
        [PSCustomObject]@{ Field = 'seven_day_fable';      Label = 'Fable';      Match = @('Fable') }
        [PSCustomObject]@{ Field = 'seven_day_opus';       Label = 'Opus';       Match = @('Opus') }
        [PSCustomObject]@{ Field = 'seven_day_sonnet';     Label = 'Sonnet';     Match = @('Sonnet') }
        [PSCustomObject]@{ Field = 'seven_day_oauth_apps'; Label = 'OAuth apps'; Match = @('OAuth apps', 'OAuth Apps', 'OAuth') }
        [PSCustomObject]@{ Field = 'seven_day_omelette';   Label = 'Omelette';   Match = @('Omelette') }
        [PSCustomObject]@{ Field = 'seven_day_cowork';     Label = 'Cowork';     Match = @('Cowork') }
    )
}

function ConvertTo-ClaudeQuotaMatchKey($value) {
    if (-not $value) { return '' }
    return ([string]$value).ToLowerInvariant() -replace '[^a-z0-9]', ''
}

function Get-PropertyValue($object, [string]$name) {
    if (-not $object) { return $null }
    $prop = $object.PSObject.Properties[$name]
    if ($prop) { return $prop.Value }
    return $null
}

function Get-ClaudeLimitNames($limit, $spec) {
    $scope = Get-PropertyValue $limit 'scope'
    $model = Get-PropertyValue $scope 'model'
    $application = Get-PropertyValue $scope 'application'

    @(
        (Get-PropertyValue $limit 'display_name')
        (Get-PropertyValue $limit 'name')
        (Get-PropertyValue $limit 'limit_name')
        (Get-PropertyValue $limit 'limit_id')
        (Get-PropertyValue $scope 'display_name')
        (Get-PropertyValue $scope 'name')
        (Get-PropertyValue $scope 'type')
        (Get-PropertyValue $model 'display_name')
        (Get-PropertyValue $model 'name')
        (Get-PropertyValue $application 'display_name')
        (Get-PropertyValue $application 'name')
    ) | Where-Object { $_ }
}

function ConvertTo-ClaudeQuotaWindow($limit) {
    if (-not $limit) { return $null }
    $utilization = $null
    foreach ($name in @('utilization', 'percent', 'used_percent')) {
        $candidate = Get-PropertyValue $limit $name
        if ($null -ne $candidate) { $utilization = [double]$candidate; break }
    }
    if ($null -eq $utilization) { return $null }

    [PSCustomObject]@{
        utilization = $utilization
        resets_at   = Get-PropertyValue $limit 'resets_at'
    }
}

function Get-ScopedLimit([object]$resp, [object]$spec) {
    if (-not $resp.limits) { return $null }
    $matches = @($spec.Match | ForEach-Object { ConvertTo-ClaudeQuotaMatchKey $_ })
    foreach ($lim in $resp.limits) {
        $limitNames = @(Get-ClaudeLimitNames $lim $spec | ForEach-Object { ConvertTo-ClaudeQuotaMatchKey $_ })
        foreach ($name in $limitNames) {
            foreach ($match in $matches) {
                if ($name -eq $match -or ($match -and $name.EndsWith($match))) {
                    return ConvertTo-ClaudeQuotaWindow $lim
                }
            }
        }
    }
    return $null
}

function Normalize-ClaudeQuotaWindows([object]$resp) {
    if (-not $resp) { return $resp }

    foreach ($spec in Get-ClaudeQuotaWindowSpecs) {
        $existing = Get-PropertyValue $resp $spec.Field
        if ($null -eq $existing) {
            $existing = Get-ScopedLimit $resp $spec
        }
        if ($null -ne $existing) {
            $resp | Add-Member -NotePropertyName $spec.Field -NotePropertyValue (ConvertTo-ClaudeQuotaWindow $existing) -Force
        }
    }

    return $resp
}

function ConvertTo-ClaudeIdentity {
    param($Profile)

    if (-not $Profile) { return $null }

    $account = $Profile.account
    $user = $Profile.user
    $org = $Profile.organization
    if (-not $org -and $Profile.organizations) {
        $org = @($Profile.organizations) | Select-Object -First 1
    }

    $email = $null
    foreach ($candidate in @($Profile.email, $account.email, $user.email)) {
        if ($candidate) { $email = [string]$candidate; break }
    }

    $orgName = $null
    foreach ($candidate in @($Profile.organization_name, $org.name, $org.display_name)) {
        if ($candidate) { $orgName = [string]$candidate; break }
    }

    $orgId = $null
    foreach ($candidate in @($Profile.organization_uuid, $Profile.organization_id, $org.uuid, $org.id)) {
        if ($candidate) { $orgId = [string]$candidate; break }
    }

    if (-not $email -and -not $orgName -and -not $orgId) { return $null }

    $parts = @()
    if ($email) { $parts += $email }
    if ($orgName) { $parts += $orgName }
    elseif ($orgId) { $parts += $orgId }

    [PSCustomObject]@{
        Email        = $email
        Organization = $orgName
        OrganizationId = $orgId
        Display      = ($parts -join ' / ')
    }
}

function Get-ClaudeBackoffPath {
    Join-Path $script:AppDir 'claude-backoff.json'
}

function Get-ClaudeBackoffUntil {
    try {
        $path = Get-ClaudeBackoffPath
        if (-not (Test-Path $path)) { return $null }

        $raw = Get-Content $path -Raw -Encoding UTF8 -ErrorAction Stop
        if (-not $raw) { return $null }

        $json = $raw | ConvertFrom-Json -ErrorAction Stop
        if (-not $json.BackoffUntil) { return $null }

        return ([System.DateTimeOffset]::Parse([string]$json.BackoffUntil)).LocalDateTime
    } catch {
        Write-Log "Claude backoff load failed - $($_.Exception.Message)"
        return $null
    }
}

function Set-ClaudeBackoffUntil {
    param([datetime]$BackoffUntil)

    try {
        [pscustomobject]@{
            BackoffUntil = ([System.DateTimeOffset]$BackoffUntil).ToString('o')
        } | ConvertTo-Json -Depth 3 | Set-Content -Path (Get-ClaudeBackoffPath) -Encoding UTF8
    } catch {
        Write-Log "Claude backoff save failed - $($_.Exception.Message)"
    }
}

function Clear-ClaudeBackoff {
    try {
        $path = Get-ClaudeBackoffPath
        if (Test-Path $path) { Remove-Item $path -Force -ErrorAction Stop }
    } catch {
        Write-Log "Claude backoff clear failed - $($_.Exception.Message)"
    }
}

function ConvertFrom-RetryAfter {
    param($Value)

    if ($null -eq $Value) { return $null }
    $text = [string]$Value
    if (-not $text) { return $null }

    $seconds = 0
    if ([int]::TryParse($text, [ref]$seconds)) {
        return (Get-Date).AddSeconds([math]::Max(60, $seconds))
    }

    try {
        return ([System.DateTimeOffset]::Parse($text)).LocalDateTime
    } catch {
        return $null
    }
}

function Get-ResponseRetryAfter {
    param($Response)

    if (-not $Response) { return $null }

    try {
        $header = $Response.Headers['Retry-After']
        if ($header) { return ConvertFrom-RetryAfter $header }
    } catch { }

    try {
        $values = $Response.Headers.GetValues('Retry-After')
        if ($values -and $values.Count -gt 0) { return ConvertFrom-RetryAfter $values[0] }
    } catch { }

    return $null
}

function Get-ClaudeProfile {
    param(
        [Parameter(Mandatory = $true)][string]$Token,
        [int]$TimeoutSec = 20
    )

    $profile = Invoke-RestMethod 'https://api.anthropic.com/api/oauth/profile' -TimeoutSec $TimeoutSec -Headers @{
        Authorization = "Bearer $Token"; 'anthropic-beta' = 'oauth-2025-04-20'; 'User-Agent' = $script:UA
    }
    return ConvertTo-ClaudeIdentity $profile
}

function Get-Usage {
    param(
        [int]$TimeoutSec = 20,
        [switch]$Force
    )

    if (-not $Force) {
        $backoffUntil = Get-ClaudeBackoffUntil
        if ($backoffUntil -and $backoffUntil -gt (Get-Date)) {
            $script:State.Status = 'stale'
            $script:State.Message = "Rate limited until $($backoffUntil.ToString('HH:mm'))"
            return
        }
    }

    $tok = $null
    try { $tok = (Get-Content $script:CredPath -Raw | ConvertFrom-Json).claudeAiOauth.accessToken } catch {
        $script:State.Status = 'error'; $script:State.Message = 'No credentials file'; return
    }
    if (-not $tok) { $script:State.Status = 'auth'; $script:State.Message = 'Not logged in'; return }
    try {
        $resp = Invoke-RestMethod 'https://api.anthropic.com/api/oauth/usage' -TimeoutSec $TimeoutSec -Headers @{
            Authorization = "Bearer $tok"; 'anthropic-beta' = 'oauth-2025-04-20'; 'User-Agent' = $script:UA
        }
        $resp = Normalize-ClaudeQuotaWindows $resp
        $script:State.Data = $resp; $script:State.Status = 'ok'
        $script:State.Message = ''; $script:State.LastFetch = (Get-Date -Format 'HH:mm')
        Clear-ClaudeBackoff
        # Record to history ring buffer
        Add-HistorySample $resp
        Save-History
    } catch {
        $code = $null
        if ($_.Exception.Response) { try { $code = [int]$_.Exception.Response.StatusCode } catch { } }
        if     ($code -eq 401) { $script:State.Status = 'auth';  $script:State.Message = 'Auth expired' }
        elseif ($code -eq 429) {
            $retryUntil = Get-ResponseRetryAfter $_.Exception.Response
            if (-not $retryUntil -or $retryUntil -lt (Get-Date).AddMinutes(5)) {
                $retryUntil = (Get-Date).AddMinutes(15)
            }
            Set-ClaudeBackoffUntil $retryUntil
            $script:State.Status = 'stale'
            $script:State.Message = "Rate limited until $($retryUntil.ToString('HH:mm'))"
        }
        else                   { $script:State.Status = 'stale'; $script:State.Message = $_.Exception.Message }
    }

    try {
        $script:ClaudeIdentity = Get-ClaudeProfile -Token $tok -TimeoutSec $TimeoutSec
    } catch {
        Write-Log "Get-Usage: Claude profile fetch failed - $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------------------
# Measure-Stats - pure aggregator, takes pre-parsed records and a reference
# date; returns the same hashtable shape consumed by Update-UI.
#
# Each record must have:
#   Model     - model name string (e.g. 'claude-opus-4-8')
#   Date      - [datetime] (local date of the message)
#   In        - [long] input tokens
#   Out       - [long] output tokens
#   CacheW    - [long] cache-creation tokens
#   CacheR    - [long] cache-read tokens
#   SessionId - session GUID string
#   Key       - dedup key (already applied upstream by Get-Stats)
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

# Per-file parse cache: path -> @{ Stamp; Records }
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
        Write-Log "Get-Stats: failed to load cache $CachePath - $($_.Exception.Message)"
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
        Write-Log "Get-Stats: failed to save cache $CachePath - $($_.Exception.Message)"
    }
}

function Get-Stats {
    $cachePath = Join-Path $script:AppDir 'stats-cache.json'
    Import-StatsFileCache $cachePath

    $projDir = Join-Path $env:USERPROFILE '.claude\projects'
    if (-not (Test-Path $projDir)) {
        Write-Log 'Get-Stats: ~/.claude/projects not found - no transcript data'
        return
    }

    try {
        $files = Get-ChildItem $projDir -Recurse -Filter '*.jsonl' -File -ErrorAction Stop
    } catch {
        Write-Log "Get-Stats: failed to enumerate transcripts - $($_.Exception.Message)"
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
            # Reuse cached parse - only add records whose keys haven't been seen yet
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
            Write-Log "Get-Stats: skipping unreadable file $($file.FullName) - $($_.Exception.Message)"
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
        Write-Log "Get-Stats: Measure-Stats failed - $($_.Exception.Message)"
    }
}
