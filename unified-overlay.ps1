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

function Stop-ExistingInstance {
    $scriptPath = [System.IO.Path]::GetFullPath($PSCommandPath)

    if (Test-Path $script:PidPath) {
        try {
            $oldPid = [int](Get-Content $script:PidPath -Raw)
            if ($oldPid -ne $PID) {
                $old = Get-CimInstance Win32_Process -Filter "ProcessId=$oldPid" -ErrorAction SilentlyContinue
                if ($old -and $old.CommandLine -like "*$scriptPath*") {
                    Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Milliseconds 500
                }
            }
        } catch { }
        Remove-Item $script:PidPath -Force -ErrorAction SilentlyContinue
    }

    Get-CimInstance Win32_Process -Filter "Name = 'pwsh.exe'" -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ProcessId -ne $PID -and
            $_.CommandLine -like "*$scriptPath*" -and
            $_.CommandLine -like '*-Background*'
        } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
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
    Stop-ExistingInstance
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
# Async data gathering (off the WPF dispatcher thread)
#
# The poll fans out to network (cursor.com, api.anthropic.com — up to 20s each)
# and to 5 sqlite3.exe spawns. Doing that synchronously on the UI thread froze
# the window for up to ~40s every 3 minutes. Instead we Start-ThreadJob
# self-contained refreshes (no WPF, separate runspace -> no shared $script: vars),
# and a fast completion-poll timer marshals each RETURNED data packet back onto
# the UI thread and renders there.
# ---------------------------------------------------------------------------

# Runs in background runspaces. Each job dot-sources the modules it needs and
# RETURNS plain data only; WPF objects are touched only on the dispatcher thread.
$script:ClaudeUsageScript = {
    param([string]$AppDir, [string]$CredPath, [string]$ErrLog, [int]$UsageTimeoutSec = 20)

    $script:AppDir   = $AppDir
    $script:CredPath = $CredPath
    $script:ErrLog   = $ErrLog
    # Invoke-Sqlite resolves sqlite3.exe via $PSScriptRoot (src\) then PATH; the
    # bundled exe lives in the app root, so make it findable via PATH here.
    $env:PATH = "$AppDir;$env:PATH"

    . (Join-Path $AppDir 'src\Config.ps1')
    . (Join-Path $AppDir 'src\History.ps1')
    . (Join-Path $AppDir 'src\Data.ps1')
    . (Join-Path $AppDir 'src\CursorData.ps1')

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # State hashtable mirrors the shape unified-overlay.ps1 declares.
    $script:State = @{ Data = $null; Status = 'init'; LastFetch = ''; Message = '' }

    Load-History
    Get-Usage -TimeoutSec $UsageTimeoutSec
    Get-CursorUsage
    Get-CursorLocalStats

    @{
        Kind            = 'ClaudeUsage'
        State           = $script:State
        LiveData        = $script:LiveData
        SummaryData     = $script:SummaryData
        LocalData       = $script:LocalData
        AuthState       = $script:AuthState
        CursorErrMsg    = $script:CursorErrMsg
        CursorLastFetch = $script:CursorLastFetch
        History         = @($script:History)
    }
}

$script:ClaudeStatsScript = {
    param([string]$AppDir, [string]$ErrLog)

    $script:AppDir = $AppDir
    $script:ErrLog = $ErrLog

    . (Join-Path $AppDir 'src\Config.ps1')
    . (Join-Path $AppDir 'src\Pricing.ps1')
    . (Join-Path $AppDir 'src\Data.ps1')

    Get-Stats

    @{
        Kind  = 'ClaudeStats'
        Stats = $script:Stats
    }
}

$script:CodexStatsScript = {
    param([string]$AppDir, [string]$ErrLog)

    $script:AppDir = $AppDir
    $script:ErrLog = $ErrLog

    . (Join-Path $AppDir 'src\Config.ps1')
    . (Join-Path $AppDir 'src\Pricing.ps1')
    . (Join-Path $AppDir 'src\Data.ps1')
    . (Join-Path $AppDir 'src\CodexData.ps1')

    Get-CodexStats

    @{
        Kind       = 'CodexStats'
        CodexStats = $script:CodexStats
    }
}

$script:pollJobs = @{}

function Start-AllRefreshJobs {
    param([int]$UsageTimeoutSec = 20)

    $jobs = @(
        @{
            Kind       = 'ClaudeUsage'
            Script     = $script:ClaudeUsageScript
            Arguments  = @($script:AppDir, $script:CredPath, $script:ErrLog, $UsageTimeoutSec)
        }
        @{
            Kind       = 'ClaudeStats'
            Script     = $script:ClaudeStatsScript
            Arguments  = @($script:AppDir, $script:ErrLog)
        }
        @{
            Kind       = 'CodexStats'
            Script     = $script:CodexStatsScript
            Arguments  = @($script:AppDir, $script:ErrLog)
        }
    )

    foreach ($jobSpec in $jobs) {
        $kind = $jobSpec.Kind

        if ($script:pollJobs.ContainsKey($kind)) {
            $existing = $script:pollJobs[$kind]
            if ($existing.State -eq 'Running' -or $existing.State -eq 'NotStarted') {
                Write-Log "Start-AllRefreshJobs: previous $kind refresh still running; skipping this source."
                continue
            }

            Remove-Job $existing -Force -ErrorAction SilentlyContinue
            $script:pollJobs.Remove($kind)
        }

        $script:pollJobs[$kind] = Start-ThreadJob -ScriptBlock $jobSpec.Script -ArgumentList $jobSpec.Arguments
    }
}

function Complete-RefreshJobs {
    if (-not $script:pollJobs -or $script:pollJobs.Count -eq 0) { return $false }

    $completedAny = $false

    foreach ($kind in @($script:pollJobs.Keys)) {
        $job = $script:pollJobs[$kind]
        if ($job.State -eq 'Running' -or $job.State -eq 'NotStarted') { continue }

        try {
            $results = @(Receive-Job $job -ErrorAction SilentlyContinue)
            $r = $results | Where-Object { $_ -is [hashtable] -and $_.ContainsKey('Kind') } | Select-Object -Last 1

            if ($r) {
                $resultKind = [string]$r['Kind']
                $applied = $true
                switch ($resultKind) {
                    'ClaudeUsage' {
                        $script:State           = $r['State']
                        $script:LiveData        = $r['LiveData']
                        $script:SummaryData     = $r['SummaryData']
                        $script:LocalData       = $r['LocalData']
                        $script:AuthState       = $r['AuthState']
                        $script:CursorErrMsg    = $r['CursorErrMsg']
                        $script:CursorLastFetch = $r['CursorLastFetch']
                        $script:History         = [System.Collections.Generic.List[object]]::new()
                        foreach ($sample in @($r['History'])) { [void]$script:History.Add($sample) }
                    }
                    'ClaudeStats' {
                        $script:Stats = $r['Stats']
                    }
                    'CodexStats' {
                        $script:CodexStats = $r['CodexStats']
                    }
                    default {
                        Write-Log "Complete-RefreshJobs: unknown result kind '$resultKind'."
                        $applied = $false
                    }
                }

                if ($applied) {
                    Update-AllSections
                    Resize-ToContent
                }
            }

            $completedAny = $true
        } catch {
            Write-Log "Complete-RefreshJobs: $kind failed: $($_.Exception.Message)"
        } finally {
            Remove-Job $job -Force -ErrorAction SilentlyContinue
            $script:pollJobs.Remove($kind)
        }
    }

    return $completedAny
}

# ---------------------------------------------------------------------------
# Startup sequence — window shows immediately in a "loading" state; the first
# data load runs async and each section fills in as its refresh job returns.
# ---------------------------------------------------------------------------
Load-UnifiedState
$script:State.Status  = 'init'
$script:State.Message = 'loading...'
Update-AllSections
Apply-UnifiedSettings
Restore-UnifiedSections
Resize-ToContent
Start-AllRefreshJobs -UsageTimeoutSec 8

# Poll timer: every 180s kick off fresh async refreshes (skips sources still running).
$script:pollTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:pollTimer.Interval = [TimeSpan]::FromSeconds(180)
$script:pollTimer.add_Tick({ Start-AllRefreshJobs })

# Completion timer: cheaply checks whether refresh jobs have finished and, if
# so, marshals their data onto the UI thread and renders immediately.
$script:jobTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:jobTimer.Interval = [TimeSpan]::FromMilliseconds(500)
$script:jobTimer.add_Tick({ [void](Complete-RefreshJobs) })

# Tick timer: refreshes reset countdowns/clock every 30s (render only, no I/O,
# no layout Measure — Resize-ToContent is intentionally NOT in this path).
$script:tickTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:tickTimer.Interval = [TimeSpan]::FromSeconds(30)
$script:tickTimer.add_Tick({ Update-AllSections })

function Show-UnifiedWindowWhenRendered {
    Resize-ToContent
    $script:window.Opacity = 0
    $script:window.add_ContentRendered({
        $opacity = 1.0
        if ($script:Cfg -and $script:Cfg.ContainsKey('Opacity') -and $null -ne $script:Cfg.Opacity) {
            $opacity = [double]$script:Cfg.Opacity
        }
        $script:window.Opacity = $opacity
    })
    $script:window.Show()
    Resize-ToContent
    if (-not $script:Positioned) { Position-Window } else { Clamp-Position }
}

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
            Resize-ToContent
        }
        Wire-UnifiedWindowEvents
        try {
            if (-not $Hidden -and -not [bool]$script:Cfg.StartHidden) { Show-UnifiedWindowWhenRendered }
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
$script:jobTimer.Start()
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
