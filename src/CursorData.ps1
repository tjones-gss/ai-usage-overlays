$script:StateVscdb = Join-Path $env:APPDATA 'Cursor\User\globalStorage\state.vscdb'
$script:TrackingDb = Join-Path $env:USERPROFILE '.cursor\ai-tracking\ai-code-tracking.db'

$script:LiveData        = $null
$script:LocalData       = $null
$script:SummaryData     = $null
$script:AuthState       = 'init'
$script:CursorLastFetch = ''
$script:CursorErrMsg    = ''

function Fmt-Num([double]$n) {
    if ($n -ge 1e6) { return ('{0:0.0}M' -f ($n / 1e6)) }
    if ($n -ge 1e3) { return ('{0:0}k'   -f ($n / 1e3)) }
    return ('{0:0}' -f $n)
}

# ---------------------------------------------------------------------------
# SQLite helper - reads Cursor's SQLite databases via bundled sqlite3.exe
# ---------------------------------------------------------------------------
function Invoke-Sqlite {
    param([string]$DbPath, [string]$Query)
    $exe = $null
    if ($PSScriptRoot) {
        $candidate = Join-Path $PSScriptRoot 'sqlite3.exe'
        if (Test-Path $candidate) { $exe = $candidate }
    }
    if (-not $exe) {
        $cmd = Get-Command sqlite3.exe -ErrorAction SilentlyContinue
        if ($cmd) { $exe = $cmd.Source }
    }
    if (-not $exe) { return $null }
    try {
        # sqlite3 -json may return output as a string array (one line per line);
        # join into a single string so ConvertFrom-Json can parse the full JSON.
        $lines = & $exe -readonly -json $DbPath $Query 2>$null
        if ($lines) { $lines -join '' } else { $null }
    } catch { $null }
}

function Get-CursorToken {
    # Read accessToken and email from state.vscdb
    $raw = Invoke-Sqlite $script:StateVscdb "SELECT key, value FROM ItemTable WHERE key IN ('cursorAuth/accessToken','cursorAuth/cachedEmail')"
    if (-not $raw) { return $null, $null, $null }
    $rows = $null
    try { $rows = $raw | ConvertFrom-Json } catch { return $null, $null, $null }
    if (-not $rows) { return $null, $null, $null }

    $tok    = $null
    $email  = $null
    $userId = $null

    foreach ($row in $rows) {
        if ($row.key -eq 'cursorAuth/accessToken') { $tok   = $row.value -replace '^"|"$','' }
        if ($row.key -eq 'cursorAuth/cachedEmail')  { $email = $row.value -replace '^"|"$','' }
    }

    # Decode JWT payload to extract userId (sub field)
    if ($tok) {
        try {
            $parts = $tok -split '\.'
            if ($parts.Count -ge 2) {
                $b64 = $parts[1]
                $pad = $b64.Length % 4
                if ($pad -ne 0) { $b64 += '=' * (4 - $pad) }
                $payload = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b64)) | ConvertFrom-Json
                if ($payload.sub) { $userId = $payload.sub }
            }
        } catch { }
    }

    return $tok, $userId, $email
}

# ---------------------------------------------------------------------------
# Live data from Cursor API
# ---------------------------------------------------------------------------
function Get-CursorUsage {
    $tok, $userId, $email = Get-CursorToken
    if (-not $tok -or -not $userId) {
        $script:AuthState = 'notoken'; $script:CursorErrMsg = 'Cannot read Cursor token from state.vscdb'
        return
    }

    $cookie = "WorkosCursorSessionToken=$([Uri]::EscapeDataString($userId + '::' + $tok))"

    try {
        $r = Invoke-RestMethod "https://cursor.com/api/usage?user=$([Uri]::EscapeDataString($userId))" `
            -Headers @{ Cookie = $cookie } -TimeoutSec 20
        $script:LiveData        = $r
        $script:AuthState       = 'ok'
        $script:CursorErrMsg    = ''
        $script:CursorLastFetch = (Get-Date -Format 'HH:mm')
    } catch {
        $code = $null
        if ($_.Exception.Response) { try { $code = [int]$_.Exception.Response.StatusCode } catch { } }
        if ($code -eq 401) { $script:AuthState = 'auth';  $script:CursorErrMsg = 'Auth expired - reopen Cursor' }
        else                { $script:AuthState = 'stale'; $script:CursorErrMsg = $_.Exception.Message }
    }

    # Also fetch usage-summary for on-demand spend
    try {
        $script:SummaryData = Invoke-RestMethod 'https://cursor.com/api/usage-summary' `
            -Headers @{ Cookie = $cookie; Authorization = "Bearer $tok" } -TimeoutSec 20
    } catch { }
}

# ---------------------------------------------------------------------------
# Local stats from ai-code-tracking.db via sqlite3.exe
# ---------------------------------------------------------------------------
function Get-CursorLocalStats {
    if (-not (Test-Path $script:TrackingDb)) { return }

    # Total edits
    $rawTotal = Invoke-Sqlite $script:TrackingDb "SELECT COUNT(*) AS cnt FROM ai_code_hashes"
    if (-not $rawTotal) { return }
    $total = 0
    try {
        $totalRows = $rawTotal | ConvertFrom-Json
        if ($totalRows -and $totalRows.cnt) { $total = [int]$totalRows.cnt }
    } catch { return }

    # Today edits (createdAt is milliseconds since epoch)
    $rawToday = Invoke-Sqlite $script:TrackingDb "SELECT COUNT(*) AS cnt FROM ai_code_hashes WHERE date(createdAt/1000,'unixepoch') = date('now')"
    $todayCount = 0
    try {
        if ($rawToday) {
            $todayRows = $rawToday | ConvertFrom-Json
            if ($todayRows -and $null -ne $todayRows.cnt) { $todayCount = [int]$todayRows.cnt }
        }
    } catch { }

    # Top model
    $rawModel = Invoke-Sqlite $script:TrackingDb "SELECT model, COUNT(*) AS c FROM ai_code_hashes GROUP BY model ORDER BY c DESC LIMIT 1"
    $topModel = 'unknown'
    $topPct   = 0
    try {
        if ($rawModel) {
            $modelRow = $rawModel | ConvertFrom-Json
            if ($modelRow -and $modelRow.model) {
                $topModel = $modelRow.model
                if ($total -gt 0) {
                    $topPct = [int][Math]::Round([int]$modelRow.c * 100.0 / $total)
                }
            }
        }
    } catch { }

    # Distinct conversations
    $rawConvos = Invoke-Sqlite $script:TrackingDb "SELECT COUNT(DISTINCT conversationId) AS cnt FROM ai_code_hashes"
    $convos = 0
    try {
        if ($rawConvos) {
            $convoRows = $rawConvos | ConvertFrom-Json
            if ($convoRows -and $null -ne $convoRows.cnt) { $convos = [int]$convoRows.cnt }
        }
    } catch { }

    $script:LocalData = [PSCustomObject]@{
        total    = $total
        today    = $todayCount
        topModel = $topModel
        topPct   = $topPct
        convos   = $convos
    }
}
