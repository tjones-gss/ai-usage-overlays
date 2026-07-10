#Requires -Module Pester
BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    $script:AppDir = $root
    $script:ErrLog = Join-Path ([System.IO.Path]::GetTempPath()) 'overlay-test-errors.log'
    . (Join-Path $root 'src\Config.ps1')
    . (Join-Path $root 'src\Pricing.ps1')
    . (Join-Path $root 'src\Data.ps1')
}

Describe 'Measure-Stats' {
    It 'returns zeroed stats for empty input' {
        $s = Measure-Stats @() ([datetime]'2026-06-10')
        $s.InTokens  | Should -Be 0
        $s.OutTokens | Should -Be 0
        $s.ValueUSD  | Should -Be 0.0
        $s.Messages  | Should -Be 0
        $s.Sessions  | Should -Be 0
        $s.TodayMsg  | Should -Be 0
        $s.TodayTok  | Should -Be 0
    }

    It 'sums all-time input and output tokens across multiple records' {
        $records = @(
            @{ Model='claude-sonnet-4'; Date=[datetime]'2026-06-01'; In=100000L; Out=10000L; CacheW=0L; CacheR=0L; SessionId='s1'; Key='a' }
            @{ Model='claude-sonnet-4'; Date=[datetime]'2026-06-09'; In=200000L; Out=20000L; CacheW=0L; CacheR=0L; SessionId='s2'; Key='b' }
        )
        $s = Measure-Stats $records ([datetime]'2026-06-10')
        $s.InTokens  | Should -Be 300000
        $s.OutTokens | Should -Be 30000
    }

    It 'filters today tokens and messages correctly' {
        $today = [datetime]'2026-06-10'
        $records = @(
            @{ Model='claude-sonnet-4'; Date=[datetime]'2026-06-09'; In=500000L; Out=0L; CacheW=0L; CacheR=0L; SessionId='s1'; Key='a' }
            @{ Model='claude-sonnet-4'; Date=[datetime]'2026-06-10'; In=100000L; Out=50000L; CacheW=0L; CacheR=0L; SessionId='s1'; Key='b' }
            @{ Model='claude-sonnet-4'; Date=[datetime]'2026-06-10'; In=200000L; Out=25000L; CacheW=0L; CacheR=0L; SessionId='s2'; Key='c' }
        )
        $s = Measure-Stats $records $today
        $s.TodayMsg | Should -Be 2
        $s.TodayTok | Should -Be 375000    # (100000+50000) + (200000+25000)
    }

    It 'counts distinct sessions and total messages' {
        $records = @(
            @{ Model='claude-sonnet-4'; Date=[datetime]'2026-06-10'; In=1L; Out=1L; CacheW=0L; CacheR=0L; SessionId='s1'; Key='a' }
            @{ Model='claude-sonnet-4'; Date=[datetime]'2026-06-10'; In=1L; Out=1L; CacheW=0L; CacheR=0L; SessionId='s1'; Key='b' }
            @{ Model='claude-sonnet-4'; Date=[datetime]'2026-06-10'; In=1L; Out=1L; CacheW=0L; CacheR=0L; SessionId='s2'; Key='c' }
        )
        $s = Measure-Stats $records ([datetime]'2026-06-10')
        $s.Sessions | Should -Be 2
        $s.Messages | Should -Be 3
    }

    It 'applies opus pricing ($15/M) vs sonnet pricing ($3/M) for 1M input each' {
        $records = @(
            @{ Model='claude-opus-4-8';  Date=[datetime]'2026-06-10'; In=1000000L; Out=0L; CacheW=0L; CacheR=0L; SessionId='s1'; Key='a' }
            @{ Model='claude-sonnet-4-6'; Date=[datetime]'2026-06-10'; In=1000000L; Out=0L; CacheW=0L; CacheR=0L; SessionId='s2'; Key='b' }
        )
        $s = Measure-Stats $records ([datetime]'2026-06-10')
        $s.ValueUSD | Should -Be 18.0   # 15.0 + 3.0
    }

    It 'returns zero today stats when no records match today' {
        $records = @(
            @{ Model='claude-sonnet-4'; Date=[datetime]'2026-06-09'; In=999999L; Out=999999L; CacheW=0L; CacheR=0L; SessionId='s1'; Key='a' }
        )
        $s = Measure-Stats $records ([datetime]'2026-06-10')
        $s.TodayMsg | Should -Be 0
        $s.TodayTok | Should -Be 0
    }

    It 'includes cache tokens in cost but not in InTokens/OutTokens totals' {
        # Pricing uses cacheW + cacheR for cost; InTokens/OutTokens are the raw input/output counts only
        $records = @(
            @{ Model='claude-opus-4-8'; Date=[datetime]'2026-06-10'; In=0L; Out=0L; CacheW=1000000L; CacheR=0L; SessionId='s1'; Key='a' }
        )
        $s = Measure-Stats $records ([datetime]'2026-06-10')
        $s.InTokens  | Should -Be 0
        $s.OutTokens | Should -Be 0
        $s.ValueUSD  | Should -Be 18.75   # opus cacheWrite: $18.75/M
    }
}

Describe 'Get-ClaudeProjectsDirCandidates' {
    It 'includes projects directories from supplied WSL home roots' {
        $wslHome = '\\wsl.localhost\Ubuntu\home\alice'

        $dirs = Get-ClaudeProjectsDirCandidates -WslHomeRoots @($wslHome)

        $dirs | Should -Contain '\\wsl.localhost\Ubuntu\home\alice\.claude\projects'
    }
}
