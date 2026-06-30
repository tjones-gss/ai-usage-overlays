#Requires -Module Pester
BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    # History.ps1 references $script:AppDir at parse/dot-source time to build $script:HistoryPath
    $script:AppDir = $root
    . (Join-Path $root 'src\Config.ps1')
    . (Join-Path $root 'src\History.ps1')
}

Describe 'Add-HistorySample (ring buffer)' {
    BeforeEach {
        $script:History = [System.Collections.Generic.List[object]]::new()
        $script:HistoryMaxLen = 480
    }
    It 'adds a sample with correct fields' {
        $data = [PSCustomObject]@{
            five_hour        = [PSCustomObject]@{ utilization = 50.0 }
            seven_day        = [PSCustomObject]@{ utilization = 30.0 }
            seven_day_opus   = $null
        }
        Add-HistorySample $data
        $script:History.Count | Should -Be 1
        $script:History[0].five_hour  | Should -Be 50.0
        $script:History[0].seven_day  | Should -Be 30.0
        $script:History[0].seven_day_opus | Should -BeNullOrEmpty
    }
    It 'trims to HistoryMaxLen when exceeded' {
        $script:HistoryMaxLen = 5
        $data = [PSCustomObject]@{
            five_hour        = [PSCustomObject]@{ utilization = 10.0 }
            seven_day        = $null
            seven_day_opus   = $null
        }
        for ($i = 0; $i -lt 7; $i++) { Add-HistorySample $data }
        $script:History.Count | Should -Be 5
    }
}

Describe 'Get-Eta' {
    It 'returns $null with fewer than 3 samples' {
        Get-Eta @() 'five_hour' | Should -BeNullOrEmpty

        $s = [PSCustomObject]@{
            t         = (Get-Date).AddMinutes(-5) | Get-Date -Format 'o'
            five_hour = 10
        }
        Get-Eta @($s) 'five_hour' | Should -BeNullOrEmpty
    }
    It 'returns $null for flat data' {
        $now = Get-Date
        $samples = 0..4 | ForEach-Object {
            [PSCustomObject]@{
                t         = $now.AddMinutes(-$_ * 5) | Get-Date -Format 'o'
                five_hour = 50.0
            }
        }
        Get-Eta $samples 'five_hour' | Should -BeNullOrEmpty
    }
    It 'returns $null for decreasing data' {
        $now = Get-Date
        # Samples ordered oldest-first: times go from -20min to now, values go 80 -> 60 (decreasing)
        $samples = 0..4 | ForEach-Object {
            [PSCustomObject]@{
                t         = $now.AddMinutes($_ * 5 - 20) | Get-Date -Format 'o'
                five_hour = 80.0 - ($_ * 5)  # 80, 75, 70, 65, 60 — decreasing over time
            }
        }
        Get-Eta $samples 'five_hour' | Should -BeNullOrEmpty
    }
    It 'returns positive minutes for clearly rising data' {
        $now = Get-Date
        # Rising from 10% to 50% over 40 minutes — ETA should be well-defined
        $samples = 0..4 | ForEach-Object {
            [PSCustomObject]@{
                t         = $now.AddMinutes($_ * 10 - 40) | Get-Date -Format 'o'
                five_hour = 10.0 + ($_ * 10)  # 10, 20, 30, 40, 50
            }
        }
        $eta = Get-Eta $samples 'five_hour'
        $eta | Should -Not -BeNullOrEmpty
        $eta | Should -BeGreaterThan 0
    }
    It 'returns $null when ETA is more than 24 hours away' {
        $now = Get-Date
        # Very slow rise: 0% to 1% over 60 min — would take hundreds of hours
        $samples = 0..4 | ForEach-Object {
            [PSCustomObject]@{
                t         = $now.AddMinutes($_ * 15 - 60) | Get-Date -Format 'o'
                five_hour = 0.0 + ($_ * 0.25)  # 0, 0.25, 0.5, 0.75, 1.0
            }
        }
        Get-Eta $samples 'five_hour' | Should -BeNullOrEmpty
    }
}
