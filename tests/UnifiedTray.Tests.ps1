#Requires -Module Pester

Describe 'Unified tray refresh menu' {
    BeforeAll {
        $root = Split-Path $PSScriptRoot -Parent
        $script:UnifiedTraySource = Get-Content (Join-Path $root 'src\UnifiedTray.ps1') -Raw -Encoding UTF8
    }

    It 'routes Refresh now through the async refresh pipeline' {
        $script:UnifiedTraySource | Should -Match "New-StripItem 'Refresh now' \{ Invoke-ManualRefresh \}"
        $script:UnifiedTraySource | Should -Match 'function Invoke-ManualRefresh'
        $script:UnifiedTraySource | Should -Match 'Start-AllRefreshJobs'
    }

    It 'does not call provider fetchers directly from the Refresh now menu handler' {
        $refreshHandler = [regex]::Match(
            $script:UnifiedTraySource,
            "New-StripItem 'Refresh now' \{ (?<handler>.*?) \}"
        ).Groups['handler'].Value

        $refreshHandler | Should -Not -Match 'Get-Usage'
        $refreshHandler | Should -Not -Match 'Get-Stats'
        $refreshHandler | Should -Not -Match 'Get-CodexStats'
        $refreshHandler | Should -Not -Match 'Get-CursorUsage'
        $refreshHandler | Should -Not -Match 'Get-CursorLocalStats'
    }

    It 'positions the panel context menu from the WPF click point' {
        $script:UnifiedTraySource | Should -Match 'function Show-ContextMenuAtWpfPointer'
        $script:UnifiedTraySource | Should -Match 'GetPosition\(\$script:window\)'
        $script:UnifiedTraySource | Should -Match 'PointToScreen\(\$localPoint\)'

        $rightClickHandler = [regex]::Match(
            $script:UnifiedTraySource,
            '\$script:window\.Add_MouseRightButtonUp\(\{\s*(?<handler>.*?)\s*\}\)',
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        ).Groups['handler'].Value

        $rightClickHandler | Should -Match 'Show-ContextMenuAtWpfPointer \$e'
        $rightClickHandler | Should -Not -Match 'MousePosition'
    }
}
