#Requires -Module Pester
BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    $script:AppDir = $root
    $script:ErrLog = Join-Path $TestDrive 'overlay-test-errors.log'
    $script:CredPath = Join-Path $TestDrive '.credentials.json'
    . (Join-Path $root 'src\Config.ps1')
    . (Join-Path $root 'src\Data.ps1')
}

Describe 'ConvertTo-ClaudeIdentity' {
    It 'extracts email and organization from the OAuth profile payload' {
        $profile = [pscustomobject]@{
            account = [pscustomobject]@{ email = 'dev@example.test' }
            organization = [pscustomobject]@{
                uuid = 'org-123'
                name = 'Example Org'
            }
        }

        $identity = ConvertTo-ClaudeIdentity $profile

        $identity.Email | Should -Be 'dev@example.test'
        $identity.Organization | Should -Be 'Example Org'
        $identity.OrganizationId | Should -Be 'org-123'
        $identity.Display | Should -Be 'dev@example.test / Example Org'
    }

    It 'returns null when the profile has no usable identity fields' {
        ConvertTo-ClaudeIdentity ([pscustomobject]@{}) | Should -BeNullOrEmpty
    }
}

Describe 'Get-Usage Claude profile behavior' {
    BeforeEach {
        Set-Content -Path $script:CredPath -Encoding UTF8 -Value '{"claudeAiOauth":{"accessToken":"token-123"}}'
        $script:State = @{ Data = $null; Status = 'init'; LastFetch = ''; Message = '' }
        $script:ClaudeIdentity = $null
        function Add-HistorySample { param($data) }
        function Save-History { }
    }

    It 'stores Claude identity when usage and profile fetches succeed' {
        Mock Invoke-RestMethod {
            [pscustomobject]@{
                five_hour = [pscustomobject]@{ utilization = 10; resets_at = '2026-07-06T18:00:00Z' }
                seven_day = [pscustomobject]@{ utilization = 20; resets_at = '2026-07-13T18:00:00Z' }
                limits = @()
            }
        } -ParameterFilter { $Uri -like '*oauth/usage' }
        Mock Invoke-RestMethod {
            [pscustomobject]@{
                account = [pscustomobject]@{ email = 'dev@example.test' }
                organization = [pscustomobject]@{ name = 'Example Org'; uuid = 'org-123' }
            }
        } -ParameterFilter { $Uri -like '*oauth/profile' }

        Get-Usage

        $script:State.Status | Should -Be 'ok'
        $script:ClaudeIdentity.Display | Should -Be 'dev@example.test / Example Org'
    }

    It 'keeps usage data when the profile fetch fails' {
        Mock Invoke-RestMethod {
            [pscustomobject]@{
                five_hour = [pscustomobject]@{ utilization = 10; resets_at = '2026-07-06T18:00:00Z' }
                seven_day = [pscustomobject]@{ utilization = 20; resets_at = '2026-07-13T18:00:00Z' }
                limits = @()
            }
        } -ParameterFilter { $Uri -like '*oauth/usage' }
        Mock Invoke-RestMethod { throw 'profile down' } -ParameterFilter { $Uri -like '*oauth/profile' }

        Get-Usage

        $script:State.Status | Should -Be 'ok'
        $script:State.Data | Should -Not -BeNullOrEmpty
        $script:ClaudeIdentity | Should -BeNullOrEmpty
    }
}

Describe 'Claude rate-limit backoff helpers' {
    BeforeEach {
        $script:AppDir = $TestDrive
    }

    It 'persists and reloads the Claude backoff timestamp' {
        $until = (Get-Date).AddMinutes(12)

        Set-ClaudeBackoffUntil $until
        $loaded = Get-ClaudeBackoffUntil

        $loaded | Should -Not -BeNullOrEmpty
        [math]::Abs(($loaded - $until).TotalSeconds) | Should -BeLessThan 2
    }

    It 'parses Retry-After seconds with a one-minute floor' {
        $before = Get-Date

        $retryAt = ConvertFrom-RetryAfter '15'

        ($retryAt - $before).TotalSeconds | Should -BeGreaterOrEqual 59
    }

    It 'clears persisted Claude backoff state' {
        Set-ClaudeBackoffUntil (Get-Date).AddMinutes(10)

        Clear-ClaudeBackoff

        Get-ClaudeBackoffUntil | Should -BeNullOrEmpty
    }
}
