#Requires -Module Pester

Describe 'Quake extra usage' {
    BeforeAll {
        $root = Split-Path $PSScriptRoot -Parent
        . (Join-Path $root 'src\QuakeView.ps1')
    }

    It 'converts the existing Claude extra usage fields to display dollars' {
        $display = ConvertTo-QuakeExtraUsage ([pscustomobject]@{
            is_enabled    = $true
            used_credits  = 1234
            monthly_limit = 5000
            currency      = 'USD'
        })

        $display.Used  | Should -Be 12.34
        $display.Limit | Should -Be 50.0
        $display.Symbol | Should -Be '$'
    }

    It 'returns no display data when extra usage is disabled' {
        ConvertTo-QuakeExtraUsage ([pscustomobject]@{
            is_enabled    = $false
            used_credits  = 1234
            monthly_limit = 5000
            currency      = 'USD'
        }) | Should -BeNullOrEmpty
    }
}

Describe 'Quake monitor selection' {
    BeforeAll {
        $root = Split-Path $PSScriptRoot -Parent
        function Write-Log { param([string]$Message) }
        . (Join-Path $root 'src\Dropdown.ps1')
    }

    BeforeEach {
        $script:Cfg = @{ ViewMode = 'Quake'; DropdownMonitor = 'Primary' }
        $script:DropdownShown = $true
        $script:DropdownAnimating = $true
        $script:window = [pscustomobject]@{ Left = 0.0; Top = 0.0 }
        $script:window | Add-Member ScriptMethod BeginAnimation { param($Property, $Animation) }
        $script:window | Add-Member ScriptMethod UpdateLayout { }
    }

    It 'resizes the visible strip after changing monitors' {
        Mock Resize-QuakeToContent {}
        Mock Get-DropdownGeometry { @{ Left = 1920.0; ShownTop = 0.0 } }

        Set-DropdownMonitor 'DISPLAY2'

        Should -Invoke Resize-QuakeToContent -Times 1 -Exactly
        $script:window.Left | Should -Be 1920.0
        $script:DropdownAnimating | Should -BeFalse
    }
}
