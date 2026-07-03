[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Install', 'Uninstall')]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [string]$InstallDir
)

$ErrorActionPreference = 'Stop'

function Get-OverlayPowerShell {
    $candidates = @(
        (Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'PowerShell\7\pwsh.exe'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe')
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) { return $candidate }
    }

    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwsh) { return $pwsh.Source }

    $powershell = Get-Command powershell.exe -ErrorAction Stop
    return $powershell.Source
}

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

    Get-CimInstance Win32_Process -Filter "Name = 'pwsh.exe' OR Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
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

$psExe = Get-OverlayPowerShell

if ($Action -eq 'Install') {
    & $psExe -STA -NoLogo -NoProfile -ExecutionPolicy Bypass -File $overlayScript -Install
    exit $LASTEXITCODE
}

& $psExe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $overlayScript -Uninstall
Stop-AIUsageOverlay -AppDir $InstallDir

