# Pricing.ps1 — API cost estimation (references $script:Prices from Config.ps1)

function Estimate-Cost([string]$name, $v) {
    $tier = if ($name -match 'opus') { 'opus' } elseif ($name -match 'haiku') { 'haiku' } else { 'sonnet' }
    if (-not ($name -match 'opus') -and -not ($name -match 'haiku') -and -not ($name -match 'sonnet')) {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log "Unknown model '$name' — falling back to sonnet pricing (verify prices)" }
    }
    $p = $script:Prices[$tier]
    return ([double]$v.inputTokens              / 1e6 * $p.in)  +
           ([double]$v.outputTokens             / 1e6 * $p.out) +
           ([double]$v.cacheCreationInputTokens / 1e6 * $p.cw)  +
           ([double]$v.cacheReadInputTokens      / 1e6 * $p.cr)
}
