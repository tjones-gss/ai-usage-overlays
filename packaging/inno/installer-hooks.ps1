[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Install', 'Uninstall')]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [string]$InstallDir
)

$ErrorActionPreference = 'Stop'

function Stop-AIUsageOverlay {
    param([Parameter(Mandatory = $true)][string]$AppDir)

    $scriptPath = Join-Path $AppDir 'unified-overlay.ps1'
    $pidPath = Join-Path $AppDir 'unified-overlay.pid'

    if (Test-Path $pidPath) {
        try {
            $oldPid = [int](Get-Content $pidPath -Raw)
            Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue
        } catch {
        } finally {
            Remove-Item $pidPath -Force -ErrorAction SilentlyContinue
        }
    }

    Get-CimInstance Win32_Process -Filter "Name = 'pwsh.exe'" -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -and
            $_.CommandLine -like "*$scriptPath*"
        } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
}

$overlayScript = Join-Path $InstallDir 'unified-overlay.ps1'
if (-not (Test-Path $overlayScript)) {
    throw "Overlay script not found: $overlayScript"
}

if ($Action -eq 'Install') {
    & pwsh -STA -NoLogo -NoProfile -ExecutionPolicy Bypass -File $overlayScript -Install
    exit $LASTEXITCODE
}

& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $overlayScript -Uninstall
Stop-AIUsageOverlay -AppDir $InstallDir

