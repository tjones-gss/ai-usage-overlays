#Requires -Module Pester

Describe 'Unified overlay CLI snapshot mode' {
    BeforeAll {
        $root = Split-Path $PSScriptRoot -Parent
        $script:UnifiedOverlaySource = Get-Content (Join-Path $root 'unified-overlay.ps1') -Raw -Encoding UTF8
    }

    It 'declares snapshot switches' {
        $script:UnifiedOverlaySource | Should -Match '\[switch\]\$Json'
        $script:UnifiedOverlaySource | Should -Match '\[switch\]\$Snapshot'
        $script:UnifiedOverlaySource | Should -Match '\[switch\]\$NoHud'
    }

    It 'exits through snapshot output before WPF startup' {
        $snapshotIndex = $script:UnifiedOverlaySource.IndexOf('if ($Json -or $Snapshot -or $NoHud)')
        $wpfIndex = $script:UnifiedOverlaySource.IndexOf('Add-Type -AssemblyName PresentationFramework')

        $snapshotIndex | Should -BeGreaterThan -1
        $wpfIndex | Should -BeGreaterThan -1
        $snapshotIndex | Should -BeLessThan $wpfIndex
    }
}
