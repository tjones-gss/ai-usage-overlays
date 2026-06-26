<#
    Unified AI Usage Overlay
    A single always-on-top HUD showing Claude Code, Codex, and Cursor usage.
    Right-click the panel for all options.

    Usage:
      pwsh -STA -File unified-overlay.ps1           # run
      pwsh -STA -File unified-overlay.ps1 -Install  # add login auto-start + run
      pwsh -STA -File unified-overlay.ps1 -Uninstall
#>
param(
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$Hidden,
    [switch]$Background   # set on self-relaunch to break infinite-loop
)

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion.Major -lt 7) {
    throw 'PowerShell 7 (pwsh) is required.'
}

$script:AppDir    = $PSScriptRoot
$script:StatePath = Join-Path $script:AppDir 'unified-overlay-state.json'
$script:VbsPath   = Join-Path $script:AppDir 'Start-Unified.vbs'
$script:ErrLog    = Join-Path $script:AppDir 'unified-overlay-error.log'
$script:PidPath   = Join-Path $script:AppDir 'unified-overlay.pid'
$script:LnkPath   = Join-Path ([Environment]::GetFolderPath('Startup')) 'AIUsageOverlay.lnk'
$script:CredPath  = Join-Path $env:USERPROFILE '.claude\.credentials.json'

function Quote-NativeArg([string]$Value) {
    '"' + ($Value -replace '"', '\"') + '"'
}

function Start-HiddenBackground {
    $exe = (Get-Process -Id $PID).Path
    # conhost --headless is required: pwsh -WindowStyle Hidden is ignored by Windows Terminal
    Start-Process 'conhost.exe' -ArgumentList (
        '--headless',
        (Quote-NativeArg $exe),
        '-STA',
        '-NoLogo',
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-WindowStyle',
        'Hidden',
        '-NonInteractive',
        '-File',
        (Quote-NativeArg $PSCommandPath),
        '-Background'
    )
}

function Install-Autostart {
    $ws = New-Object -ComObject WScript.Shell
    $sc = $ws.CreateShortcut($script:LnkPath)
    $sc.TargetPath       = Join-Path $env:SystemRoot 'System32\wscript.exe'
    $sc.Arguments        = '"' + $script:VbsPath + '"'
    $sc.WorkingDirectory = $script:AppDir
    $sc.Description      = 'AI Usage Overlay'
    $sc.Save()
}
function Uninstall-Autostart { if (Test-Path $script:LnkPath) { Remove-Item $script:LnkPath -Force } }
function Test-Autostart      { Test-Path $script:LnkPath }

if ($Uninstall) { Uninstall-Autostart; Write-Host 'Removed login auto-start.'; return }
if ($Install) {
    Install-Autostart
    Start-HiddenBackground
    Write-Host 'Installed. Unified overlay is running.'
    return
}

# Self-relaunch when run from a console. The spawned copy is hidden and uses
# -Background to skip this block, so there is no infinite loop.
if (-not $Background) {
    Add-Type -Name '_UnifiedK32' -Namespace '' -MemberDefinition '[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();'
    if ([_UnifiedK32]::GetConsoleWindow() -ne [IntPtr]::Zero) {
        Start-HiddenBackground
        exit
    }
}

try {

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase,
                       System.Windows.Forms, System.Drawing, System.Xaml

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---------------------------------------------------------------------------
# Load modules (dot-sourced into this scope)
# ---------------------------------------------------------------------------
. (Join-Path $script:AppDir 'src\Config.ps1')
. (Join-Path $script:AppDir 'src\Format.ps1')
. (Join-Path $script:AppDir 'src\Pricing.ps1')
. (Join-Path $script:AppDir 'src\History.ps1')
. (Join-Path $script:AppDir 'src\Data.ps1')
. (Join-Path $script:AppDir 'src\State.ps1')
. (Join-Path $script:AppDir 'src\CodexData.ps1')
. (Join-Path $script:AppDir 'src\CursorData.ps1')
. (Join-Path $script:AppDir 'src\Shell.ps1')
. (Join-Path $script:AppDir 'src\UnifiedState.ps1')
. (Join-Path $script:AppDir 'src\UnifiedTray.ps1')

# ---------------------------------------------------------------------------
# Runtime state (declared after modules so $xaml from Shell.ps1 is available)
# ---------------------------------------------------------------------------
$script:State      = @{ Data = $null; Status = 'init'; LastFetch = ''; Message = '' }
$script:Stats      = $null
$script:ReallyQuit = $false
$script:Positioned = $false

$script:window = [System.Windows.Markup.XamlReader]::Parse($xaml)

function Restore-UnifiedSections {
    foreach ($key in @('claude', 'codex', 'cursor')) {
        if ($script:Cfg.Sections.ContainsKey($key)) {
            Set-Section $key ([bool]$script:Cfg.Sections[$key])
        }
    }
}

# ---------------------------------------------------------------------------
# Startup sequence
# ---------------------------------------------------------------------------
Load-History
Load-UnifiedState
Get-Usage
Get-Stats
Get-CodexStats
Get-CursorUsage
Get-CursorLocalStats
Update-AllSections
Apply-UnifiedSettings
Restore-UnifiedSections

$script:pollTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:pollTimer.Interval = [TimeSpan]::FromSeconds(180)
$script:pollTimer.add_Tick({
    Get-Usage
    Get-Stats
    Get-CodexStats
    Get-CursorUsage
    Get-CursorLocalStats
    Update-AllSections
})

$script:tickTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:tickTimer.Interval = [TimeSpan]::FromSeconds(30)
$script:tickTimer.add_Tick({ Update-AllSections })

# Build-And-Show: retry window Show() until the DWM compositor is ready.
# At login the Startup-folder shortcut can fire before the desktop is fully
# initialised, causing WPF's SetRootVisual to fail with "VisualTarget cannot
# have a parent". The error is transient; recreating the window and retrying
# is the correct fix. Backoff: 250 ms, 500 ms, 1 s, 2 s, 4 s x3 (~16 s total).
function Build-And-Show {
    $maxAttempts = 8
    for ($i = 1; $i -le $maxAttempts; $i++) {
        if ($i -gt 1) {
            # Discard the bad window state and create a fresh one.
            $script:Positioned = $false
            $script:window = [System.Windows.Markup.XamlReader]::Parse($xaml)
            Update-AllSections
            Apply-UnifiedSettings
            Restore-UnifiedSections
        }
        Wire-UnifiedWindowEvents
        try {
            if (-not $Hidden -and -not [bool]$script:Cfg.StartHidden) { $script:window.Show() }
            return $true
        } catch {
            if ($_.Exception.Message -notmatch 'VisualTarget') { throw }
            $delay = [math]::Min(4000, [int](250 * [math]::Pow(2, $i - 1)))
            Write-Log "Show() attempt $i/$maxAttempts failed (compositor not ready); retrying in ${delay}ms..."
            Start-Sleep -Milliseconds $delay
        }
    }
    return $false
}

if (-not (Build-And-Show)) {
    Write-Log 'Unified overlay failed to start after all attempts; compositor never became ready.'
    return
}

$script:pollTimer.Start()
$script:tickTimer.Start()

# Write PID file so Uninstall.bat can terminate the process.
try { [System.IO.File]::WriteAllText($script:PidPath, "$PID") } catch { }

[System.Windows.Threading.Dispatcher]::Run()

try { Remove-Item $script:PidPath -ErrorAction SilentlyContinue } catch { }

}
catch {
    $msg = "[{0}] {1}`n{2}" -f (Get-Date -Format 's'), $_.Exception.Message, $_.ScriptStackTrace
    try { Add-Content -Path $script:ErrLog -Value $msg -Encoding UTF8 } catch { }
    throw
}
