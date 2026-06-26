#Requires -Module Pester
BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    $script:AppDir = $root
    $script:ErrLog = Join-Path ([System.IO.Path]::GetTempPath()) 'overlay-test-errors.log'
    . (Join-Path $root 'src\Config.ps1')
    $script:CodexPrices = @{
        'gpt-5.5' = @{ in = 5.00; cachedIn = 0.50; out = 30.00 }
        default   = @{ in = 1.00; cachedIn = 0.10; out = 2.00 }
    }
    . (Join-Path $root 'src\CodexData.ps1')

    function New-CodexTokenEvent {
        param(
            [string]$Timestamp,
            [long]$InputTokens,
            [long]$CachedInputTokens,
            [long]$OutputTokens,
            [switch]$Legacy
        )

        $info = @{
            total_token_usage = @{
                input_tokens            = $InputTokens
                cached_input_tokens     = $CachedInputTokens
                output_tokens           = $OutputTokens
                reasoning_output_tokens = 0
                total_tokens            = $InputTokens + $OutputTokens
            }
            last_token_usage = @{
                input_tokens        = 999999
                cached_input_tokens = 999999
                output_tokens       = 999999
                total_tokens        = 1999998
            }
        }

        if ($Legacy) {
            return @{
                timestamp = $Timestamp
                type      = 'token_count'
                payload   = @{
                    info = $info
                }
            }
        }

        return @{
            timestamp = $Timestamp
            type      = 'event_msg'
            payload   = @{
                type                 = 'token_count'
                info                 = $info
                model_context_window = 258400
            }
            rate_limits = @{
                primary = @{ used_percent = 0 }
            }
        }
    }

    function New-TestTimestamp {
        param([datetime]$LocalTime)

        $offset = [System.TimeZoneInfo]::Local.GetUtcOffset($LocalTime)
        return ([System.DateTimeOffset]::new($LocalTime, $offset)).ToString('o')
    }

    function Write-CodexFixture {
        param(
            [string]$RelativePath,
            [object[]]$Events
        )

        $target = Join-Path $script:CodexSessionsDir $RelativePath
        $dir = Split-Path $target -Parent
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $jsonl = foreach ($event in $Events) {
            $event | ConvertTo-Json -Depth 10 -Compress
        }
        Set-Content -Path $target -Value $jsonl -Encoding UTF8
        return $target
    }
}

Describe 'Measure-CodexStats' {
    It 'returns zeroed stats for empty input' {
        $s = Measure-CodexStats @() ([datetime]'2026-06-10')
        $s.InTokens  | Should -Be 0
        $s.OutTokens | Should -Be 0
        $s.ValueUSD  | Should -Be 0.0
        $s.Messages  | Should -Be 0
        $s.Sessions  | Should -Be 0
        $s.TodayMsg  | Should -Be 0
        $s.TodayTok  | Should -Be 0
    }

    It 'filters today tokens and messages correctly' {
        $today = [datetime]'2026-06-10'
        $records = @(
            @{ Model='gpt-5.5'; Date=[datetime]'2026-06-09'; In=500L; CachedIn=0L; Out=100L; SessionId='s1' }
            @{ Model='gpt-5.5'; Date=[datetime]'2026-06-10'; In=100L; CachedIn=10L; Out=50L; SessionId='s2' }
            @{ Model='gpt-5.5'; Date=[datetime]'2026-06-10'; In=200L; CachedIn=20L; Out=25L; SessionId='s3' }
        )
        $s = Measure-CodexStats $records $today
        $s.TodayMsg | Should -Be 2
        $s.TodayTok | Should -Be 375
    }
}

Describe 'Estimate-CodexCost' {
    It 'uses gpt-5 family pricing and default pricing for other models' {
        $v = @{ inputTokens = 1000000; cachedInputTokens = 0; outputTokens = 0 }
        Estimate-CodexCost 'gpt-5.5' $v | Should -Be 5.0
        Estimate-CodexCost 'other-model' $v | Should -Be 1.0
    }

    It 'subtracts cached input tokens before applying uncached input pricing' {
        $v = @{ inputTokens = 1000000; cachedInputTokens = 250000; outputTokens = 100000 }
        Estimate-CodexCost 'gpt-5.5' $v | Should -Be 6.875
    }
}

Describe 'Get-CodexStats' {
    BeforeEach {
        $script:CodexSessionsDir = Join-Path $TestDrive 'sessions'
        if (Test-Path $script:CodexSessionsDir) {
            Remove-Item -Path $script:CodexSessionsDir -Recurse -Force
        }
        New-Item -ItemType Directory -Path $script:CodexSessionsDir -Force | Out-Null
        $script:CodexStatsFileCache = @{}
        $script:CodexStats = $null
    }

    It 'parses real event_msg token counts using the last cumulative event in each session file' {
        $baseTime = (Get-Date).Date.AddHours(10)
        $tsMeta = New-TestTimestamp $baseTime
        $tsModel1 = New-TestTimestamp ($baseTime.AddMinutes(1))
        $tsToken1 = New-TestTimestamp ($baseTime.AddMinutes(2))
        $tsModel2 = New-TestTimestamp ($baseTime.AddMinutes(3))
        $tsToken2 = New-TestTimestamp ($baseTime.AddMinutes(4))

        Write-CodexFixture '2026\06\10\rollout-test.jsonl' @(
            @{ timestamp=$tsMeta; type='session_meta'; payload=@{ session_id='s1'; timestamp=$tsMeta } }
            @{ timestamp=$tsModel1; type='turn_context'; payload=@{ model='other-model' } }
            (New-CodexTokenEvent $tsToken1 100 10 20)
            @{ timestamp=$tsModel2; type='turn_context'; payload=@{ model='gpt-5.5' } }
            (New-CodexTokenEvent $tsToken2 300 50 70)
        ) | Out-Null

        Get-CodexStats

        $script:CodexStats.InTokens  | Should -Be 300
        $script:CodexStats.OutTokens | Should -Be 70
        $script:CodexStats.ValueUSD  | Should -Be 0.003375
        $script:CodexStats.Messages  | Should -Be 1
        $script:CodexStats.Sessions  | Should -Be 1
        $script:CodexStats.TodayMsg  | Should -Be 1
        $script:CodexStats.TodayTok  | Should -Be 370
        $script:CodexStats.ValueUSD  | Should -BeGreaterThan 0
    }

    It 'still parses legacy top-level token_count events' {
        Write-CodexFixture '2026\06\10\legacy-test.jsonl' @(
            @{ timestamp='2026-06-10T10:00:00Z'; type='session_meta'; payload=@{ session_id='legacy'; timestamp='2026-06-10T10:00:00Z' } }
            @{ timestamp='2026-06-10T10:01:00Z'; type='turn_context'; payload=@{ model='gpt-5.5' } }
            (New-CodexTokenEvent '2026-06-10T10:02:00Z' 1000 250 100 -Legacy)
        ) | Out-Null

        Get-CodexStats

        $script:CodexStats.InTokens  | Should -Be 1000
        $script:CodexStats.OutTokens | Should -Be 100
        $script:CodexStats.ValueUSD  | Should -Be 0.006875
        $script:CodexStats.Sessions  | Should -Be 1
    }

    It 'tolerates a missing sessions directory' {
        $script:CodexSessionsDir = Join-Path $TestDrive 'missing'
        { Get-CodexStats } | Should -Not -Throw
        $script:CodexStats | Should -BeNullOrEmpty
    }
}
