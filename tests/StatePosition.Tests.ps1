#Requires -Module Pester

Describe 'Unified state positioning' {
    BeforeAll {
        $root = Split-Path $PSScriptRoot -Parent
        $script:Cfg = @{}
        . (Join-Path $root 'src\UnifiedState.ps1')
        function Save-UnifiedState { }
    }

    BeforeEach {
        $script:window = [pscustomobject]@{
            Left         = 100.0
            Top          = 50.0
            ActualWidth  = 0.0
            ActualHeight = 0.0
            Width        = [double]::NaN
            Height       = [double]::NaN
            RenderSize   = [pscustomobject]@{ Width = 280.0; Height = 160.0 }
            DesiredSize  = [pscustomobject]@{ Width = 260.0; Height = 140.0 }
        }
    }

    It 'converts monitor work area from the window screen origin, not virtual desktop zero' {
        $area = [pscustomobject]@{
            Left = 3000.0; Top = 600.0; Right = 4600.0; Bottom = 1500.0; Width = 1600.0; Height = 900.0
        }
        $transform = [pscustomobject]@{ M11 = 0.5; M22 = 0.5 }
        $origin = [pscustomobject]@{ X = 3000.0; Y = 600.0 }

        $result = ConvertFrom-ScreenWorkArea $area $transform $origin

        $result.Left   | Should -Be 100.0
        $result.Top    | Should -Be 50.0
        $result.Right  | Should -Be 900.0
        $result.Bottom | Should -Be 500.0
    }

    It 'snaps bottom-right using rendered size when actual and explicit sizes are not usable' {
        function Get-WorkArea { @{ Left = 0.0; Top = 0.0; Right = 1000.0; Bottom = 800.0 } }

        Snap-ToCorner 'BR'

        $script:window.Left | Should -Be 704.0
        $script:window.Top  | Should -Be 624.0
    }

    It 'maps each menu corner key to the matching work-area corner' {
        function Get-WorkArea { @{ Left = 10.0; Top = 20.0; Right = 1010.0; Bottom = 820.0 } }
        $script:window.ActualWidth = 200.0
        $script:window.ActualHeight = 100.0

        Snap-ToCorner 'TR'
        $script:window.Left | Should -Be 794.0
        $script:window.Top  | Should -Be 36.0

        Snap-ToCorner 'TL'
        $script:window.Left | Should -Be 26.0
        $script:window.Top  | Should -Be 36.0

        Snap-ToCorner 'BR'
        $script:window.Left | Should -Be 794.0
        $script:window.Top  | Should -Be 704.0

        Snap-ToCorner 'BL'
        $script:window.Left | Should -Be 26.0
        $script:window.Top  | Should -Be 704.0
    }
}

Describe 'Legacy state positioning' {
    BeforeAll {
        $root = Split-Path $PSScriptRoot -Parent
        . (Join-Path $root 'src\State.ps1')
        function Save-State { }
    }

    BeforeEach {
        $script:window = [pscustomobject]@{
            Left         = 100.0
            Top          = 50.0
            ActualWidth  = 0.0
            ActualHeight = 0.0
            Width        = [double]::NaN
            Height       = [double]::NaN
            RenderSize   = [pscustomobject]@{ Width = 280.0; Height = 160.0 }
            DesiredSize  = [pscustomobject]@{ Width = 260.0; Height = 140.0 }
        }
    }

    It 'converts monitor work area from the window screen origin, not virtual desktop zero' {
        $area = [pscustomobject]@{
            Left = 3000.0; Top = 600.0; Right = 4600.0; Bottom = 1500.0; Width = 1600.0; Height = 900.0
        }
        $transform = [pscustomobject]@{ M11 = 0.5; M22 = 0.5 }
        $origin = [pscustomobject]@{ X = 3000.0; Y = 600.0 }

        $result = ConvertFrom-ScreenWorkArea $area $transform $origin

        $result.Left   | Should -Be 100.0
        $result.Top    | Should -Be 50.0
        $result.Right  | Should -Be 900.0
        $result.Bottom | Should -Be 500.0
    }

    It 'snaps bottom-right using rendered size when actual and explicit sizes are not usable' {
        function Get-WorkArea { @{ Left = 0.0; Top = 0.0; Right = 1000.0; Bottom = 800.0 } }

        Snap-ToCorner 'BR'

        $script:window.Left | Should -Be 704.0
        $script:window.Top  | Should -Be 624.0
    }
}
