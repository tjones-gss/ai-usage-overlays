#Requires -Module Pester
BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    . (Join-Path $root 'src\Config.ps1')
    . (Join-Path $root 'src\Pricing.ps1')
}

Describe 'Estimate-Cost' {
    It 'throws if $script:Prices is not loaded' {
        $savedPrices = $script:Prices
        $script:Prices = $null
        { Estimate-Cost 'claude-sonnet' @{inputTokens=1000000; outputTokens=0; cacheCreationInputTokens=0; cacheReadInputTokens=0} } | Should -Throw
        $script:Prices = $savedPrices
    }
    It 'calculates opus pricing for 1M input tokens' {
        $v = @{inputTokens=1000000; outputTokens=0; cacheCreationInputTokens=0; cacheReadInputTokens=0}
        Estimate-Cost 'claude-opus-4' $v | Should -Be 15.0
    }
    It 'calculates sonnet pricing for 1M input tokens' {
        $v = @{inputTokens=1000000; outputTokens=0; cacheCreationInputTokens=0; cacheReadInputTokens=0}
        Estimate-Cost 'claude-sonnet-4' $v | Should -Be 3.0
    }
    It 'calculates haiku pricing for 1M input tokens' {
        $v = @{inputTokens=1000000; outputTokens=0; cacheCreationInputTokens=0; cacheReadInputTokens=0}
        Estimate-Cost 'claude-haiku-4' $v | Should -Be 1.0
    }
    It 'falls back to sonnet pricing for unknown model names' {
        $v = @{inputTokens=1000000; outputTokens=0; cacheCreationInputTokens=0; cacheReadInputTokens=0}
        # unknown model falls back to sonnet pricing ($3/M)
        Estimate-Cost 'claude-unknown-xyz' $v | Should -Be 3.0
    }
    It 'calculates output token costs' {
        $v = @{inputTokens=0; outputTokens=1000000; cacheCreationInputTokens=0; cacheReadInputTokens=0}
        Estimate-Cost 'claude-opus-4' $v | Should -Be 75.0
    }
}
