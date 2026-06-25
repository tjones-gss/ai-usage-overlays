<#
    Combined AI Usage Overlay
    Runs the Claude Code and Cursor usage overlays side-by-side in a single process.
    Each overlay gets its own STA thread and tray icon — no name conflicts.

    Usage:
      pwsh -File combined-overlay.ps1           # run
      pwsh -File combined-overlay.ps1 -Install  # add login auto-start + run
      pwsh -File combined-overlay.ps1 -Uninstall
#>
param(
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$Background
)

$ErrorActionPreference = 'Stop'

$script:AppDir  = $PSScriptRoot
$script:VbsPath = Join-Path $script:AppDir 'Start-Combined.vbs'
$script:ErrLog  = Join-Path $script:AppDir 'combined-error.log'
$script:LnkPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'AIUsageOverlay.lnk'

function Install-Autostart {
    $ws = New-Object -ComObject WScript.Shell
    $sc = $ws.CreateShortcut($script:LnkPath)
    $sc.TargetPath       = Join-Path $env:SystemRoot 'System32\wscript.exe'
    $sc.Arguments        = '"' + $script:VbsPath + '"'
    $sc.WorkingDirectory = $script:AppDir
    $sc.Description      = 'AI Usage Overlay (Claude + Cursor)'
    $sc.Save()
}
function Uninstall-Autostart { if (Test-Path $script:LnkPath) { Remove-Item $script:LnkPath -Force } }

if ($Uninstall) { Uninstall-Autostart; Write-Host 'Removed login auto-start.'; return }
if ($Install) {
    Install-Autostart
    $exe = (Get-Process -Id $PID).Path
    Start-Process 'conhost.exe' -ArgumentList ('--headless',$exe,'-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-NonInteractive','-File',$PSCommandPath,'-Background')
    Write-Host 'Installed. Both overlays are running.'
    return
}

if (-not $Background) {
    Add-Type -Name '_CombK32' -Namespace '' -MemberDefinition '[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();'
    if ([_CombK32]::GetConsoleWindow() -ne [IntPtr]::Zero) {
        $exe = (Get-Process -Id $PID).Path
        Start-Process 'conhost.exe' -ArgumentList ('--headless',$exe,'-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-NonInteractive','-File',$PSCommandPath,'-Background')
        exit
    }
}

try {

function Start-OverlayThread([string]$scriptPath) {
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'
    $rs.ThreadOptions  = 'ReuseThread'
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript("& '$($scriptPath.Replace("'","''"))' -Background")
    $handle = $ps.BeginInvoke()
    return [pscustomobject]@{ PS = $ps; Handle = $handle; RS = $rs }
}

$claudeThread = Start-OverlayThread (Join-Path $script:AppDir 'overlay.ps1')
$cursorThread = Start-OverlayThread (Join-Path $script:AppDir 'cursor-overlay.ps1')

while (-not $claudeThread.Handle.IsCompleted -or -not $cursorThread.Handle.IsCompleted) {
    Start-Sleep -Seconds 5
}

$claudeThread.PS.EndInvoke($claudeThread.Handle)
$claudeThread.RS.Close()
$cursorThread.PS.EndInvoke($cursorThread.Handle)
$cursorThread.RS.Close()

} catch {
    $msg = "[{0}] {1}`n{2}" -f (Get-Date -Format 's'), $_.Exception.Message, $_.ScriptStackTrace
    try { Add-Content -Path $script:ErrLog -Value $msg } catch { }
    throw
}
