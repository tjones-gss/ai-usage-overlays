#Requires -Module Pester
BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    $script:AppDir = $root
    . (Join-Path $root 'src\Config.ps1')
    . (Join-Path $root 'src\Update.ps1')
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
