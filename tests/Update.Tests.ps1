#Requires -Module Pester
BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    $script:AppDir = $root
    . (Join-Path $root 'src\Config.ps1')
    . (Join-Path $root 'src\Update.ps1')
    . (Join-Path $root 'src\UnifiedState.ps1')
}

Describe 'Update version comparison' {
    It 'normalizes v-prefixed semantic versions' {
        (ConvertTo-AppVersion 'v1.2.3').ToString() | Should -Be '1.2.3'
        (ConvertTo-AppVersion '1.2.3').ToString() | Should -Be '1.2.3'
    }

    It 'detects newer release versions' {
        Test-AppVersionGreater -LatestVersion 'v1.2.0' -CurrentVersion '1.1.9' | Should -BeTrue
        Test-AppVersionGreater -LatestVersion 'v1.2.0' -CurrentVersion '1.2.0' | Should -BeFalse
        Test-AppVersionGreater -LatestVersion 'v1.1.9' -CurrentVersion '1.2.0' | Should -BeFalse
    }
}

Describe 'Convert-GitHubReleaseToAppUpdateInfo' {
    It 'returns current when the latest release matches the current app version' {
        $release = [pscustomobject]@{
            tag_name = 'v1.0.0'
            html_url = 'https://example.test/releases/v1.0.0'
            assets = @(
                [pscustomobject]@{ name = 'AIUsageOverlaySetup.exe'; browser_download_url = 'https://example.test/setup.exe' }
            )
        }

        $info = Convert-GitHubReleaseToAppUpdateInfo -Release $release -CurrentVersion '1.0.0'

        $info.Status | Should -Be 'current'
        $info.Message | Should -Match 'up to date'
    }

    It 'returns available when a newer release has the setup asset' {
        $release = [pscustomobject]@{
            tag_name = 'v1.1.0'
            html_url = 'https://example.test/releases/v1.1.0'
            assets = @(
                [pscustomobject]@{ name = 'AIUsageOverlaySetup.exe'; browser_download_url = 'https://example.test/setup.exe' }
            )
        }

        $info = Convert-GitHubReleaseToAppUpdateInfo -Release $release -CurrentVersion '1.0.0'

        $info.Status | Should -Be 'available'
        $info.DownloadUrl | Should -Be 'https://example.test/setup.exe'
    }

    It 'reports a missing installer asset for newer releases without setup EXE' {
        $release = [pscustomobject]@{
            tag_name = 'v1.1.0'
            html_url = 'https://example.test/releases/v1.1.0'
            assets = @(
                [pscustomobject]@{ name = 'source.zip'; browser_download_url = 'https://example.test/source.zip' }
            )
        }

        $info = Convert-GitHubReleaseToAppUpdateInfo -Release $release -CurrentVersion '1.0.0'

        $info.Status | Should -Be 'missing-asset'
        $info.Message | Should -Match 'AIUsageOverlaySetup.exe'
    }
}

Describe 'Test-AppUpdateAvailable' {
    It 'does not throw when GitHub checks fail' {
        Mock Get-GitHubLatestRelease { throw 'network down' }

        $info = Test-AppUpdateAvailable -CurrentVersion '1.0.0'

        $info.Status | Should -Be 'error'
        $info.Message | Should -Match 'Update check failed'
    }

    It 'reports when no GitHub release exists' {
        Mock Get-GitHubLatestRelease { $null }

        $info = Test-AppUpdateAvailable -CurrentVersion '1.0.0'

        $info.Status | Should -Be 'no-release'
    }
}

Describe 'Automatic update check gating' {
    BeforeEach {
        $script:Cfg = @{}
        Initialize-UnifiedCfg
        $script:StatePath = Join-Path $TestDrive 'unified-overlay-state.json'
        $script:window = $null
        $script:UpdateState.CheckedAt = $null
    }

    It 'is not due when automatic checks are disabled' {
        Test-AppUpdateAutoCheckDue -Enabled:$false -LastCheckedAt $null | Should -BeFalse
    }

    It 'is due when no prior update check has completed' {
        Test-AppUpdateAutoCheckDue -Enabled:$true -LastCheckedAt $null | Should -BeTrue
    }

    It 'waits until the configured interval has elapsed' {
        $now = [datetime]'2026-07-06T12:00:00'

        Test-AppUpdateAutoCheckDue -Enabled:$true -LastCheckedAt $now.AddHours(-23) -Now $now -IntervalHours 24 | Should -BeFalse
        Test-AppUpdateAutoCheckDue -Enabled:$true -LastCheckedAt $now.AddHours(-24) -Now $now -IntervalHours 24 | Should -BeTrue
    }

    It 'persists the completed update check timestamp across unified state reloads' {
        $checkedAt = [datetime]'2026-07-06T12:00:00'
        $now = $checkedAt.AddHours(23)

        $script:Cfg.LastUpdateCheckAt = $checkedAt
        Save-UnifiedState

        $script:Cfg = @{}
        Initialize-UnifiedCfg
        $script:UpdateState.CheckedAt = $null

        Load-UnifiedState

        $script:UpdateState.CheckedAt | Should -Not -BeNullOrEmpty
        Test-AppUpdateAutoCheckDue -Enabled:$true -LastCheckedAt $script:UpdateState.CheckedAt -Now $now -IntervalHours 24 | Should -BeFalse
    }
}

Describe 'Automatic update notification gating' {
    It 'notifies once for an available release version' {
        $info = [pscustomobject]@{
            Status = 'available'
            LatestVersion = 'v1.2.0'
            DownloadUrl = 'https://example.test/AIUsageOverlaySetup.exe'
        }

        Test-AppUpdateNotificationDue -Info $info -LastNotifiedVersion $null | Should -BeTrue
        Test-AppUpdateNotificationDue -Info $info -LastNotifiedVersion 'v1.2.0' | Should -BeFalse
    }

    It 'does not notify for current or failed checks' {
        Test-AppUpdateNotificationDue -Info ([pscustomobject]@{ Status = 'current'; LatestVersion = 'v1.2.0' }) -LastNotifiedVersion $null | Should -BeFalse
        Test-AppUpdateNotificationDue -Info ([pscustomobject]@{ Status = 'error'; LatestVersion = $null }) -LastNotifiedVersion $null | Should -BeFalse
    }
}

Describe 'Install-AppUpdate' {
    It 'downloads and starts the setup installer for an available update' {
        Mock Save-DownloadedUpdate { Join-Path $TestDrive 'AIUsageOverlaySetup.exe' }
        Mock Start-Process { [pscustomobject]@{ Id = 1234 } }

        $info = [pscustomobject]@{
            Status = 'available'
            LatestVersion = 'v1.1.0'
            DownloadUrl = 'https://example.test/AIUsageOverlaySetup.exe'
            WebUrl = 'https://example.test/releases/v1.1.0'
        }

        $result = Install-AppUpdate -Info $info

        $result.Status | Should -Be 'installing'
        Should -Invoke Save-DownloadedUpdate -Times 1 -Exactly
        Should -Invoke Start-Process -Times 1 -Exactly
    }

    It 'returns an error result when the download fails' {
        Mock Save-DownloadedUpdate { throw 'download failed' }
        Mock Start-Process { throw 'should not start' }

        $info = [pscustomobject]@{
            Status = 'available'
            LatestVersion = 'v1.1.0'
            DownloadUrl = 'https://example.test/AIUsageOverlaySetup.exe'
            WebUrl = 'https://example.test/releases/v1.1.0'
        }

        $result = Install-AppUpdate -Info $info

        $result.Status | Should -Be 'error'
        $result.Message | Should -Match 'download failed'
        Should -Invoke Start-Process -Times 0 -Exactly
    }
}
