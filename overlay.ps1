<#
    Claude Code Usage Overlay
    A tiny always-on-top HUD showing live Claude Code limits.
    Right-click the panel for all options.

    Usage:
      pwsh -File overlay.ps1           # run
      pwsh -File overlay.ps1 -Install  # add login auto-start + run
      pwsh -File overlay.ps1 -Uninstall
#>
param(
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$Hidden,
    [switch]$Background   # set on self-relaunch to break infinite-loop
)

$ErrorActionPreference = 'Stop'

$script:AppDir    = $PSScriptRoot
$script:StatePath = Join-Path $script:AppDir 'overlay-state.json'
$script:VbsPath   = Join-Path $script:AppDir 'Start-Overlay.vbs'
$script:ErrLog    = Join-Path $script:AppDir 'overlay-error.log'
$script:PidPath   = Join-Path $script:AppDir 'overlay.pid'
$script:LnkPath   = Join-Path ([Environment]::GetFolderPath('Startup')) 'ClaudeUsageOverlay.lnk'
$script:CredPath  = Join-Path $env:USERPROFILE '.claude\.credentials.json'

function Install-Autostart {
    $ws = New-Object -ComObject WScript.Shell
    $sc = $ws.CreateShortcut($script:LnkPath)
    $sc.TargetPath       = Join-Path $env:SystemRoot 'System32\wscript.exe'
    $sc.Arguments        = '"' + $script:VbsPath + '"'
    $sc.WorkingDirectory = $script:AppDir
    $sc.Description      = 'Claude Code Usage Overlay'
    $sc.Save()
}
function Uninstall-Autostart { if (Test-Path $script:LnkPath) { Remove-Item $script:LnkPath -Force } }
function Test-Autostart      { Test-Path $script:LnkPath }

if ($Uninstall) { Uninstall-Autostart; Write-Host 'Removed login auto-start.'; return }
if ($Install) {
    Install-Autostart
    $exe = (Get-Process -Id $PID).Path
    # conhost --headless is required: pwsh -WindowStyle Hidden is ignored by Windows Terminal
    Start-Process 'conhost.exe' -ArgumentList ('--headless',$exe,'-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-NonInteractive','-File',$PSCommandPath,'-Background')
    Write-Host 'Installed. Overlay is running.'
    return
}

# Self-relaunch when run from a console — spawns hidden copy and exits the console.
# -Background on the spawned copy skips this block so there's no infinite loop.
if (-not $Background) {
    Add-Type -Name '_K32' -Namespace '' -MemberDefinition '[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();'
    if ([_K32]::GetConsoleWindow() -ne [IntPtr]::Zero) {
        $exe = (Get-Process -Id $PID).Path
        # conhost --headless is required: pwsh -WindowStyle Hidden is ignored by Windows Terminal
        Start-Process 'conhost.exe' -ArgumentList ('--headless',$exe,'-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-NonInteractive','-File',$PSCommandPath,'-Background')
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
. (Join-Path $script:AppDir 'src\Ui.ps1')

# ---------------------------------------------------------------------------
# Runtime state (declared after modules so $xaml from Ui.ps1 is available)
# ---------------------------------------------------------------------------
$script:State      = @{ Data = $null; Status = 'init'; LastFetch = ''; Message = '' }
$script:Stats      = $null
$script:ReallyQuit = $false
$script:Positioned = $false

$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$script:window = [System.Windows.Markup.XamlReader]::Load($reader)

# Tray MUST be dot-sourced after $script:window is created (wires window events at load time)
. (Join-Path $script:AppDir 'src\Tray.ps1')

# ---------------------------------------------------------------------------
# Startup sequence
# ---------------------------------------------------------------------------
Load-History
Load-State
Get-Usage
Get-Stats
Update-UI
Apply-Settings   # applies theme, opacity, stats visibility

$script:pollTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:pollTimer.Interval = [TimeSpan]::FromSeconds($script:PollSeconds)
$script:pollTimer.add_Tick({ Get-Usage; Get-Stats; Update-UI })

$script:tickTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:tickTimer.Interval = [TimeSpan]::FromSeconds($script:TickSeconds)
$script:tickTimer.add_Tick({ Update-UI })

$script:pollTimer.Start()
$script:tickTimer.Start()

# Write PID file so Uninstall.bat can terminate the process
try { [System.IO.File]::WriteAllText($script:PidPath, "$PID") } catch { }

# Always show unless the user has explicitly chosen "Start hidden"
if (-not $Hidden -and -not [bool]$script:Cfg.StartHidden) { $script:window.Show() }

[System.Windows.Threading.Dispatcher]::Run()

try { Remove-Item $script:PidPath -ErrorAction SilentlyContinue } catch { }

}
catch {
    $msg = "[{0}] {1}`n{2}" -f (Get-Date -Format 's'), $_.Exception.Message, $_.ScriptStackTrace
    try { Add-Content -Path $script:ErrLog -Value $msg } catch { }
    throw
}
