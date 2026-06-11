#Requires -Module Pester
BeforeAll {
    # Dot-source the pure formatting functions (no WPF assemblies needed for these)
    $root = Split-Path $PSScriptRoot -Parent
    . (Join-Path $root 'src\Config.ps1')   # needed for $script:AppDir etc.
    . (Join-Path $root 'src\Format.ps1')   # defines Format-Reset, Fmt-Tok, Fmt-Money, Remaining-Color
}

Describe 'Format-Reset' {
    It 'returns empty string for null/empty input' {
        Format-Reset $null  | Should -Be ''
        Format-Reset ''     | Should -Be ''
    }
    It 'returns "now" for a past date' {
        $past = (Get-Date).AddMinutes(-5) | Get-Date -Format 'o'
        Format-Reset $past | Should -Be 'now'
    }
    It 'returns minutes format for < 1 hour' {
        $future = (Get-Date).AddMinutes(15) | Get-Date -Format 'o'
        Format-Reset $future | Should -Match '^\↺ \d+m$'
    }
    It 'returns hours+minutes format for 1-24 hours' {
        $future = (Get-Date).AddHours(2).AddMinutes(30) | Get-Date -Format 'o'
        Format-Reset $future | Should -Match '^\↺ \d+h\d{2}m$'
    }
    It 'returns days+hours format for >= 1 day' {
        $future = (Get-Date).AddDays(2).AddHours(3) | Get-Date -Format 'o'
        Format-Reset $future | Should -Match '^\↺ \d+d \d+h$'
    }
    It 'returns empty string for invalid ISO string' {
        Format-Reset 'not-a-date' | Should -Be ''
    }
}

Describe 'Fmt-Tok' {
    It 'formats numbers below 1000 as integer' {
        Fmt-Tok 0   | Should -Be '0'
        Fmt-Tok 999 | Should -Be '999'
    }
    It 'formats thousands with k suffix' {
        Fmt-Tok 1000    | Should -Be '1.0k'
        Fmt-Tok 1500    | Should -Be '1.5k'
        Fmt-Tok 500000  | Should -Be '500.0k'
    }
    It 'formats millions with M suffix' {
        Fmt-Tok 1000000   | Should -Be '1.0M'
        Fmt-Tok 1500000   | Should -Be '1.5M'
    }
}

Describe 'Fmt-Money' {
    It 'formats with dollar sign and no decimal' {
        Fmt-Money 0      | Should -Be '$0'
        Fmt-Money 1234   | Should -Be '$1,234'
        Fmt-Money 1234.9 | Should -Be '$1,235'
    }
}

Describe 'Remaining-Color' {
    It 'returns red for <= 5% remaining' {
        Remaining-Color 0 | Should -Be '#F87171'
        Remaining-Color 5 | Should -Be '#F87171'
    }
    It 'returns amber for 6-20% remaining' {
        Remaining-Color 6  | Should -Be '#FBBF24'
        Remaining-Color 20 | Should -Be '#FBBF24'
    }
    It 'returns white for > 20% remaining' {
        Remaining-Color 21  | Should -Be '#F1F5F9'
        Remaining-Color 100 | Should -Be '#F1F5F9'
    }
}
