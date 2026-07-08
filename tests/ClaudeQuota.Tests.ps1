#Requires -Module Pester
BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    $script:AppDir = $root
    $script:ErrLog = Join-Path $TestDrive 'overlay-test-errors.log'
    . (Join-Path $root 'src\Config.ps1')
    . (Join-Path $root 'src\Format.ps1')
}

Describe 'Normalize-ClaudeQuotaWindows' {
    BeforeAll {
        . (Join-Path $root 'src\Data.ps1')
    }

    It 'preserves top-level optional quota windows when present' {
        $resp = [PSCustomObject]@{
            seven_day_sonnet = [PSCustomObject]@{
                utilization = 12.5
                resets_at   = '2026-07-13T18:00:00Z'
            }
            limits = @()
        }

        $normalized = Normalize-ClaudeQuotaWindows $resp

        $normalized.seven_day_sonnet.utilization | Should -Be 12.5
        $normalized.seven_day_sonnet.resets_at | Should -Be '2026-07-13T18:00:00Z'
    }

    It 'maps supported optional windows from limits when top-level fields are absent' {
        $resp = [PSCustomObject]@{
            limits = @(
                [PSCustomObject]@{
                    percent   = 10
                    resets_at = '2026-07-13T10:00:00Z'
                    scope     = [PSCustomObject]@{ model = [PSCustomObject]@{ display_name = 'Sonnet' } }
                }
                [PSCustomObject]@{
                    percent      = 20
                    resets_at    = '2026-07-13T20:00:00Z'
                    display_name = 'OAuth Apps'
                }
                [PSCustomObject]@{
                    percent   = 30
                    resets_at = '2026-07-13T21:00:00Z'
                    scope     = [PSCustomObject]@{ name = 'Omelette' }
                }
                [PSCustomObject]@{
                    percent   = 40
                    resets_at = '2026-07-13T22:00:00Z'
                    limit_id  = 'seven_day_cowork'
                }
            )
        }

        $normalized = Normalize-ClaudeQuotaWindows $resp

        $normalized.seven_day_sonnet.utilization | Should -Be 10
        $normalized.seven_day_oauth_apps.utilization | Should -Be 20
        $normalized.seven_day_omelette.utilization | Should -Be 30
        $normalized.seven_day_cowork.utilization | Should -Be 40
    }

    It 'leaves absent optional quota windows empty' {
        $resp = [PSCustomObject]@{ limits = @() }

        $normalized = Normalize-ClaudeQuotaWindows $resp

        $normalized.PSObject.Properties['seven_day_sonnet'] | Should -BeNullOrEmpty
        $normalized.PSObject.Properties['seven_day_oauth_apps'] | Should -BeNullOrEmpty
        $normalized.PSObject.Properties['seven_day_omelette'] | Should -BeNullOrEmpty
        $normalized.PSObject.Properties['seven_day_cowork'] | Should -BeNullOrEmpty
    }
}

Describe 'Claude quota history samples' {
    BeforeAll {
        . (Join-Path $root 'src\History.ps1')
    }

    BeforeEach {
        $script:History = [System.Collections.Generic.List[object]]::new()
        $script:HistoryMaxLen = 480
    }

    It 'records additional optional quota windows when present' {
        $data = [PSCustomObject]@{
            five_hour              = [PSCustomObject]@{ utilization = 50.0 }
            seven_day              = [PSCustomObject]@{ utilization = 30.0 }
            seven_day_sonnet       = [PSCustomObject]@{ utilization = 10.0 }
            seven_day_oauth_apps   = [PSCustomObject]@{ utilization = 20.0 }
            seven_day_omelette     = [PSCustomObject]@{ utilization = 40.0 }
            seven_day_cowork       = [PSCustomObject]@{ utilization = 60.0 }
        }

        Add-HistorySample $data

        $script:History[0].seven_day_sonnet | Should -Be 10.0
        $script:History[0].seven_day_oauth_apps | Should -Be 20.0
        $script:History[0].seven_day_omelette | Should -Be 40.0
        $script:History[0].seven_day_cowork | Should -Be 60.0
    }

    It 'keeps additional optional quota windows empty when absent' {
        Add-HistorySample ([PSCustomObject]@{
            five_hour = [PSCustomObject]@{ utilization = 50.0 }
            seven_day = [PSCustomObject]@{ utilization = 30.0 }
        })

        $script:History[0].seven_day_sonnet | Should -BeNullOrEmpty
        $script:History[0].seven_day_oauth_apps | Should -BeNullOrEmpty
        $script:History[0].seven_day_omelette | Should -BeNullOrEmpty
        $script:History[0].seven_day_cowork | Should -BeNullOrEmpty
    }
}

Describe 'Claude quota copied stats' {
    BeforeAll {
        . (Join-Path $root 'src\Data.ps1')
        . (Join-Path $root 'src\State.ps1')
    }

    It 'keeps parser quota specs intact after state export helpers load' {
        $resp = [PSCustomObject]@{
            limits = @(
                [PSCustomObject]@{
                    percent   = 10
                    resets_at = '2026-07-13T10:00:00Z'
                    scope     = [PSCustomObject]@{ model = [PSCustomObject]@{ display_name = 'Sonnet' } }
                }
            )
        }

        (Normalize-ClaudeQuotaWindows $resp).seven_day_sonnet.utilization | Should -Be 10
    }

    It 'includes additional quota windows with utilization and reset details' {
        $data = [PSCustomObject]@{
            five_hour            = [PSCustomObject]@{ utilization = 50.0; resets_at = (Get-Date).AddHours(1).ToString('o') }
            seven_day            = [PSCustomObject]@{ utilization = 30.0; resets_at = (Get-Date).AddDays(1).ToString('o') }
            seven_day_sonnet     = [PSCustomObject]@{ utilization = 25.0; resets_at = (Get-Date).AddDays(2).ToString('o') }
            seven_day_oauth_apps = [PSCustomObject]@{ utilization = 35.0; resets_at = (Get-Date).AddDays(3).ToString('o') }
            seven_day_omelette   = [PSCustomObject]@{ utilization = 45.0; resets_at = (Get-Date).AddDays(4).ToString('o') }
            seven_day_cowork     = [PSCustomObject]@{ utilization = 55.0; resets_at = (Get-Date).AddDays(5).ToString('o') }
        }

        $lines = Get-ClaudeQuotaStatLines $data

        ($lines -join "`n") | Should -Match 'Sonnet:\s+75% remaining\s+\(25% used,'
        ($lines -join "`n") | Should -Match 'OAuth apps:\s+65% remaining\s+\(35% used,'
        ($lines -join "`n") | Should -Match 'Omelette:\s+55% remaining\s+\(45% used,'
        ($lines -join "`n") | Should -Match 'Cowork:\s+45% remaining\s+\(55% used,'
    }

    It 'omits absent additional quota windows from copied stats' {
        $data = [PSCustomObject]@{
            five_hour = [PSCustomObject]@{ utilization = 50.0; resets_at = (Get-Date).AddHours(1).ToString('o') }
            seven_day = [PSCustomObject]@{ utilization = 30.0; resets_at = (Get-Date).AddDays(1).ToString('o') }
        }

        $text = (Get-ClaudeQuotaStatLines $data) -join "`n"

        $text | Should -Not -Match 'Sonnet'
        $text | Should -Not -Match 'OAuth apps'
        $text | Should -Not -Match 'Omelette'
        $text | Should -Not -Match 'Cowork'
    }
}
