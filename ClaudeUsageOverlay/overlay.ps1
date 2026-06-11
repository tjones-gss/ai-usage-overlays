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
$script:PidPath   = Join-Path $script:AppDir 'overlay.pid'
$script:VbsPath   = Join-Path $script:AppDir 'Start-Overlay.vbs'
$script:ErrLog    = Join-Path $script:AppDir 'overlay-error.log'
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
    Start-Process $exe -ArgumentList '-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-NonInteractive','-File',$PSCommandPath,'-Background'
    Write-Host 'Installed. Overlay is running.'
    return
}

# Self-relaunch when run from a console — spawns hidden copy and exits the console.
# -Background on the spawned copy skips this block so there's no infinite loop.
if (-not $Background) {
    Add-Type -Name '_K32' -Namespace '' -MemberDefinition '[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();'
    if ([_K32]::GetConsoleWindow() -ne [IntPtr]::Zero) {
        $exe = (Get-Process -Id $PID).Path
        Start-Process $exe -ArgumentList '-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-NonInteractive','-File',$PSCommandPath,'-Background'
        exit
    }
}

try {

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase,
                       System.Windows.Forms, System.Drawing, System.Xaml

# ---------------------------------------------------------------------------
# State & config
# ---------------------------------------------------------------------------
$script:State         = @{ Data = $null; Status = 'init'; LastFetch = ''; Message = '' }
$script:Stats         = $null
$script:ReallyQuit    = $false
$script:Positioned    = $false
$script:BarTrackWidth = 250.0

# Single-instance guard — PID file prevents duplicate instances regardless of launch method
if (Test-Path $script:PidPath) {
    $oldPid = [int](Get-Content $script:PidPath -Raw -EA SilentlyContinue)
    if ($oldPid -and $oldPid -ne $PID) { Stop-Process -Id $oldPid -Force -EA SilentlyContinue }
}
$PID | Set-Content $script:PidPath

$script:PendingOpacity = $null   # set by menu handlers; applied on WPF thread by timer

$script:Prices = @{
    opus   = @{ in = 15.0; out = 75.0; cw = 18.75; cr = 1.50 }
    sonnet = @{ in = 3.0;  out = 15.0; cw = 3.75;  cr = 0.30 }
    haiku  = @{ in = 1.0;  out = 5.0;  cw = 1.25;  cr = 0.10 }
}

$script:UA = 'claude-code/2.1.0'
try { $v = (& claude --version) 2>$null; if ($v -match '(\d+\.\d+\.\d+)') { $script:UA = "claude-code/$($matches[1])" } } catch { }

# ---------------------------------------------------------------------------
# Color themes
# ---------------------------------------------------------------------------
$script:Themes = [ordered]@{
    'Deep Space' = @{
        FivehColors = '#0369A1','#38BDF8'
        WeekColors  = '#C2410C','#FB923C'
        SonColors   = '#6D28D9','#C084FC'
        OpusColors  = '#92400E','#FDE047'
        FivehFg     = '#38BDF8'
        WeekFg      = '#FB923C'
        SonFg       = '#C084FC'
        OpusFg      = '#FDE047'
        Stripe      = '#38BDF8','#818CF8','#E879F9','#FB923C'
    }
    'Ocean' = @{
        FivehColors = '#0F766E','#2DD4BF'
        WeekColors  = '#9D174D','#FB7185'
        SonColors   = '#1E40AF','#93C5FD'
        OpusColors  = '#92400E','#FCD34D'
        FivehFg     = '#2DD4BF'
        WeekFg      = '#FB7185'
        SonFg       = '#93C5FD'
        OpusFg      = '#FCD34D'
        Stripe      = '#2DD4BF','#93C5FD','#FB7185','#FCD34D'
    }
    'Neon' = @{
        FivehColors = '#BE185D','#F472B6'
        WeekColors  = '#15803D','#4ADE80'
        SonColors   = '#1D4ED8','#60A5FA'
        OpusColors  = '#B45309','#FDE047'
        FivehFg     = '#F472B6'
        WeekFg      = '#4ADE80'
        SonFg       = '#60A5FA'
        OpusFg      = '#FDE047'
        Stripe      = '#F472B6','#4ADE80','#60A5FA','#FDE047'
    }
    'Mono' = @{
        FivehColors = '#1E3A5F','#94A3B8'
        WeekColors  = '#1E3A5F','#94A3B8'
        SonColors   = '#1E3A5F','#94A3B8'
        OpusColors  = '#1E3A5F','#94A3B8'
        FivehFg     = '#94A3B8'
        WeekFg      = '#94A3B8'
        SonFg       = '#94A3B8'
        OpusFg      = '#94A3B8'
        Stripe      = '#334155','#64748B','#94A3B8','#64748B'
    }
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function NewBrush([string]$hex) {
    New-Object System.Windows.Media.SolidColorBrush (
        [System.Windows.Media.Color][System.Windows.Media.ColorConverter]::ConvertFromString($hex))
}

function New-GradientBrush([string]$c1, [string]$c2) {
    $b = New-Object System.Windows.Media.LinearGradientBrush
    $b.StartPoint = [System.Windows.Point]::new(0,0)
    $b.EndPoint   = [System.Windows.Point]::new(1,0)
    $s1 = New-Object System.Windows.Media.GradientStop
    $s1.Color = [System.Windows.Media.ColorConverter]::ConvertFromString($c1); $s1.Offset = 0
    $s2 = New-Object System.Windows.Media.GradientStop
    $s2.Color = [System.Windows.Media.ColorConverter]::ConvertFromString($c2); $s2.Offset = 1
    [void]$b.GradientStops.Add($s1); [void]$b.GradientStops.Add($s2)
    return $b
}

function Format-Reset([string]$iso) {
    if (-not $iso) { return '' }
    try {
        $span = [System.DateTimeOffset]::Parse($iso) - [System.DateTimeOffset]::Now
        if ($span.TotalSeconds -le 0) { return 'now' }
        if ($span.TotalDays  -ge 1)   { return ('↺ {0}d {1}h'   -f [int]$span.TotalDays, $span.Hours) }
        if ($span.TotalHours -ge 1)   { return ('↺ {0}h{1:00}m' -f [int]$span.TotalHours, $span.Minutes) }
        return ('↺ {0}m' -f [int]$span.TotalMinutes)
    } catch { return '' }
}

# Color for the remaining-% number: green → amber → red as capacity runs out
function Remaining-Color([double]$rem) {
    if ($rem -le 5)  { return '#F87171' }  # red   — almost out
    if ($rem -le 20) { return '#FBBF24' }  # amber — getting low
    return '#F1F5F9'                        # white — plenty left
}

function Fmt-Tok([double]$n) {
    if ($n -ge 1e6) { return ('{0:0.0}M' -f ($n / 1e6)) }
    if ($n -ge 1e3) { return ('{0:0.0}k' -f ($n / 1e3)) }
    return ('{0:0}' -f $n)
}

function Fmt-Money([double]$n) { return ('${0:N0}' -f $n) }

function Estimate-Cost([string]$name, $v) {
    $tier = if ($name -match 'opus') { 'opus' } elseif ($name -match 'haiku') { 'haiku' } else { 'sonnet' }
    $p = $script:Prices[$tier]
    return ([double]$v.inputTokens              / 1e6 * $p.in)  +
           ([double]$v.outputTokens             / 1e6 * $p.out) +
           ([double]$v.cacheCreationInputTokens / 1e6 * $p.cw)  +
           ([double]$v.cacheReadInputTokens      / 1e6 * $p.cr)
}

# ---------------------------------------------------------------------------
# Data fetchers
# ---------------------------------------------------------------------------
function Get-Usage {
    $tok = $null
    try { $tok = (Get-Content $script:CredPath -Raw | ConvertFrom-Json).claudeAiOauth.accessToken } catch {
        $script:State.Status = 'error'; $script:State.Message = 'No credentials file'; return
    }
    if (-not $tok) { $script:State.Status = 'auth'; $script:State.Message = 'Not logged in'; return }
    try {
        $resp = Invoke-RestMethod 'https://api.anthropic.com/api/oauth/usage' -TimeoutSec 20 -Headers @{
            Authorization = "Bearer $tok"; 'anthropic-beta' = 'oauth-2025-04-20'; 'User-Agent' = $script:UA
        }
        $script:State.Data = $resp; $script:State.Status = 'ok'
        $script:State.Message = ''; $script:State.LastFetch = (Get-Date -Format 'HH:mm')
    } catch {
        $code = $null
        if ($_.Exception.Response) { try { $code = [int]$_.Exception.Response.StatusCode } catch { } }
        if     ($code -eq 401) { $script:State.Status = 'auth';  $script:State.Message = 'Auth expired' }
        elseif ($code -eq 429) { $script:State.Status = 'stale'; $script:State.Message = 'Rate limited' }
        else                   { $script:State.Status = 'stale'; $script:State.Message = $_.Exception.Message }
    }
}

function Get-Stats {
    $path = Join-Path $env:USERPROFILE '.claude\stats-cache.json'
    try { $d = Get-Content $path -Raw | ConvertFrom-Json } catch { return }
    $val = 0.0; $tin = 0L; $tout = 0L
    if ($d.modelUsage) {
        foreach ($m in $d.modelUsage.PSObject.Properties) {
            $val  += Estimate-Cost $m.Name $m.Value
            $tin  += [long]$m.Value.inputTokens
            $tout += [long]$m.Value.outputTokens
        }
    }
    $today = (Get-Date -Format 'yyyy-MM-dd')
    $tMsg = 0; $tTok = 0L
    if ($d.dailyActivity) {
        $da = $d.dailyActivity | Where-Object { (Get-Date $_.date -Format 'yyyy-MM-dd') -eq $today }
        if ($da) { $tMsg = [int]$da.messageCount }
    }
    if ($d.dailyModelTokens) {
        $dt = $d.dailyModelTokens | Where-Object { (Get-Date $_.date -Format 'yyyy-MM-dd') -eq $today }
        if ($dt -and $dt.tokensByModel) {
            foreach ($p in $dt.tokensByModel.PSObject.Properties) { $tTok += [long]$p.Value }
        }
    }
    $script:Stats = @{
        ValueUSD = $val; InTokens = $tin; OutTokens = $tout
        Sessions = [int]$d.totalSessions; Messages = [int]$d.totalMessages
        TodayMsg = $tMsg; TodayTok = $tTok; LastComputed = $d.lastComputedDate
        CacheStale = ($d.lastComputedDate -ne $today)
    }
}

# ---------------------------------------------------------------------------
# XAML — AllowsTransparency removed; window Background matches panel so the
# rounded-corner areas show solid colour instead of bleeding through to other
# windows behind the overlay.
# ---------------------------------------------------------------------------
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Claude Usage" WindowStyle="None" AllowsTransparency="False"
        Background="#0F172A" Topmost="True" ShowInTaskbar="False"
        SizeToContent="WidthAndHeight" ResizeMode="NoResize"
        WindowStartupLocation="Manual">
  <Window.Resources>
    <LinearGradientBrush x:Key="PanelBg" StartPoint="0,0" EndPoint="0.7,1">
      <GradientStop Color="#0F172A" Offset="0"/>
      <GradientStop Color="#0B1220" Offset="1"/>
    </LinearGradientBrush>
    <LinearGradientBrush x:Key="PanelBorder" StartPoint="0,0" EndPoint="1,1">
      <GradientStop Color="#1E3A5F" Offset="0"/>
      <GradientStop Color="#0F172A" Offset="1"/>
    </LinearGradientBrush>
    <LinearGradientBrush x:Key="Divider" StartPoint="0,0" EndPoint="1,0">
      <GradientStop Color="Transparent" Offset="0"/>
      <GradientStop Color="#38BDF828" Offset="0.25"/>
      <GradientStop Color="#C084FC28" Offset="0.75"/>
      <GradientStop Color="Transparent" Offset="1"/>
    </LinearGradientBrush>
  </Window.Resources>

  <Border Background="{StaticResource PanelBg}" BorderBrush="{StaticResource PanelBorder}"
          BorderThickness="1" CornerRadius="14" ClipToBounds="True">
    <DockPanel>

      <!-- Rainbow accent stripe — named so theme changes can update it -->
      <Border x:Name="accentStripe" DockPanel.Dock="Top" Height="3">
        <Border.Background>
          <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
            <GradientStop Color="#38BDF8" Offset="0"/>
            <GradientStop Color="#818CF8" Offset="0.33"/>
            <GradientStop Color="#E879F9" Offset="0.66"/>
            <GradientStop Color="#FB923C" Offset="1"/>
          </LinearGradientBrush>
        </Border.Background>
      </Border>

      <StackPanel Margin="14,9,14,13" Width="250">

        <!-- Header -->
        <Grid Margin="0,0,0,11">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
            <Ellipse x:Name="statusDot" Width="7" Height="7" Fill="#4ADE80"
                     VerticalAlignment="Center" Margin="0,0,8,0"/>
            <TextBlock Foreground="#6B8FAF" FontSize="11" FontFamily="Bahnschrift SemiBold" Text="CLAUDE "/>
            <TextBlock Foreground="#E2E8F0" FontSize="11" FontFamily="Bahnschrift SemiBold" Text="USAGE"/>
          </StackPanel>
          <TextBlock x:Name="timeText" Grid.Column="1" Text=""
                     Foreground="#4B6A8A" FontSize="10" FontFamily="Consolas" VerticalAlignment="Center"/>
        </Grid>

        <!-- 5h metric — bar = remaining capacity -->
        <StackPanel Margin="0,0,0,10">
          <Grid Margin="0,0,0,3">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Bottom">
              <TextBlock x:Name="fivehLabel" Text="5-HOUR SESSION"
                         Foreground="#38BDF8" FontSize="8" FontFamily="Bahnschrift SemiBold"/>
            </StackPanel>
            <TextBlock Grid.Column="1" x:Name="fivehPct" Text="--" Foreground="#F1F5F9"
                       FontSize="20" FontFamily="Bahnschrift Bold" VerticalAlignment="Bottom" Margin="0,0,4,0"/>
            <TextBlock Grid.Column="2" x:Name="fivehReset" Text=""
                       Foreground="#5B8AA8" FontSize="9" FontFamily="Consolas"
                       VerticalAlignment="Bottom" Margin="0,0,0,2"/>
          </Grid>
          <Border Height="7" CornerRadius="3.5" Background="#131F33" Width="250" HorizontalAlignment="Left">
            <Border x:Name="fivehBar" Height="7" CornerRadius="3.5" HorizontalAlignment="Left" Width="250">
              <Border.Background>
                <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                  <GradientStop Color="#0369A1" Offset="0"/>
                  <GradientStop Color="#38BDF8" Offset="1"/>
                </LinearGradientBrush>
              </Border.Background>
            </Border>
          </Border>
          <TextBlock x:Name="fivehSub" Text="used" Foreground="#2D4A66"
                     FontSize="7" FontFamily="Bahnschrift SemiBold" Margin="0,1,0,0"/>
        </StackPanel>

        <!-- Weekly metric -->
        <StackPanel Margin="0,0,0,10">
          <Grid Margin="0,0,0,3">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock x:Name="weekLabel" Grid.Column="0" Text="WEEKLY LIMIT"
                       Foreground="#FB923C" FontSize="8" FontFamily="Bahnschrift SemiBold" VerticalAlignment="Bottom"/>
            <TextBlock Grid.Column="1" x:Name="weekPct" Text="--" Foreground="#F1F5F9"
                       FontSize="20" FontFamily="Bahnschrift Bold" VerticalAlignment="Bottom" Margin="0,0,4,0"/>
            <TextBlock Grid.Column="2" x:Name="weekReset" Text=""
                       Foreground="#5B8AA8" FontSize="9" FontFamily="Consolas"
                       VerticalAlignment="Bottom" Margin="0,0,0,2"/>
          </Grid>
          <Border Height="7" CornerRadius="3.5" Background="#131F33" Width="250" HorizontalAlignment="Left">
            <Border x:Name="weekBar" Height="7" CornerRadius="3.5" HorizontalAlignment="Left" Width="250">
              <Border.Background>
                <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                  <GradientStop Color="#C2410C" Offset="0"/>
                  <GradientStop Color="#FB923C" Offset="1"/>
                </LinearGradientBrush>
              </Border.Background>
            </Border>
          </Border>
          <TextBlock x:Name="weekSub" Text="used" Foreground="#2D4A66"
                     FontSize="7" FontFamily="Bahnschrift SemiBold" Margin="0,1,0,0"/>
        </StackPanel>

        <!-- Sonnet metric -->
        <StackPanel Margin="0,0,0,7">
          <Grid Margin="0,0,0,3">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock x:Name="sonLabel" Grid.Column="0" Text="SONNET WEEKLY"
                       Foreground="#C084FC" FontSize="8" FontFamily="Bahnschrift SemiBold" VerticalAlignment="Bottom"/>
            <TextBlock Grid.Column="1" x:Name="sonPct" Text="--" Foreground="#F1F5F9"
                       FontSize="20" FontFamily="Bahnschrift Bold" VerticalAlignment="Bottom" Margin="0,0,4,0"/>
            <TextBlock Grid.Column="2" x:Name="sonReset" Text=""
                       Foreground="#5B8AA8" FontSize="9" FontFamily="Consolas"
                       VerticalAlignment="Bottom" Margin="0,0,0,2"/>
          </Grid>
          <Border Height="7" CornerRadius="3.5" Background="#131F33" Width="250" HorizontalAlignment="Left">
            <Border x:Name="sonBar" Height="7" CornerRadius="3.5" HorizontalAlignment="Left" Width="250">
              <Border.Background>
                <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                  <GradientStop Color="#6D28D9" Offset="0"/>
                  <GradientStop Color="#C084FC" Offset="1"/>
                </LinearGradientBrush>
              </Border.Background>
            </Border>
          </Border>
          <TextBlock x:Name="sonSub" Text="used" Foreground="#2D4A66"
                     FontSize="7" FontFamily="Bahnschrift SemiBold" Margin="0,1,0,0"/>
        </StackPanel>

        <!-- Opus metric (collapsed unless used) -->
        <StackPanel x:Name="opusRow" Margin="0,0,0,7" Visibility="Collapsed">
          <Grid Margin="0,0,0,3">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock x:Name="opusLabel" Grid.Column="0" Text="OPUS WEEKLY"
                       Foreground="#FDE047" FontSize="8" FontFamily="Bahnschrift SemiBold" VerticalAlignment="Bottom"/>
            <TextBlock Grid.Column="1" x:Name="opusPct" Text="--" Foreground="#F1F5F9"
                       FontSize="20" FontFamily="Bahnschrift Bold" VerticalAlignment="Bottom" Margin="0,0,4,0"/>
            <TextBlock Grid.Column="2" x:Name="opusReset" Text=""
                       Foreground="#5B8AA8" FontSize="9" FontFamily="Consolas"
                       VerticalAlignment="Bottom" Margin="0,0,0,2"/>
          </Grid>
          <Border Height="7" CornerRadius="3.5" Background="#131F33" Width="250" HorizontalAlignment="Left">
            <Border x:Name="opusBar" Height="7" CornerRadius="3.5" HorizontalAlignment="Left" Width="250">
              <Border.Background>
                <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                  <GradientStop Color="#92400E" Offset="0"/>
                  <GradientStop Color="#FDE047" Offset="1"/>
                </LinearGradientBrush>
              </Border.Background>
            </Border>
          </Border>
          <TextBlock x:Name="opusSub" Text="used" Foreground="#2D4A66"
                     FontSize="7" FontFamily="Bahnschrift SemiBold" Margin="0,1,0,0"/>
        </StackPanel>

        <!-- Divider -->
        <Border Height="1" Background="{StaticResource Divider}" Margin="0,4,0,8"/>

        <!-- Stats -->
        <StackPanel x:Name="statsPanel">
          <Grid Margin="0,0,0,4">
            <Grid.ColumnDefinitions><ColumnDefinition Width="70"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <TextBlock Grid.Column="0" Text="EST. COST" Foreground="#5A8AAA"
                       FontSize="10" FontFamily="Bahnschrift SemiBold" VerticalAlignment="Center"
                       ToolTip="API-equivalent value of all usage (not a real charge on flat-rate plans)"/>
            <TextBlock Grid.Column="1" x:Name="valText" Text="--" Foreground="#94A3B8" FontSize="13" FontFamily="Consolas"/>
          </Grid>
          <Grid x:Name="extraRow" Margin="0,0,0,4" Visibility="Collapsed">
            <Grid.ColumnDefinitions><ColumnDefinition Width="70"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <TextBlock Grid.Column="0" Text="OVERAGE" Foreground="#5A8AAA"
                       FontSize="10" FontFamily="Bahnschrift SemiBold" VerticalAlignment="Center"
                       ToolTip="Real spend beyond your plan this month"/>
            <TextBlock Grid.Column="1" x:Name="extraVal" Text="" Foreground="#FBB740" FontSize="13" FontFamily="Consolas"/>
          </Grid>
          <Grid Margin="0,0,0,4">
            <Grid.ColumnDefinitions><ColumnDefinition Width="70"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <TextBlock Grid.Column="0" Text="TOKENS" Foreground="#5A8AAA"
                       FontSize="10" FontFamily="Bahnschrift SemiBold" VerticalAlignment="Center"
                       ToolTip="All-time input / output tokens"/>
            <TextBlock Grid.Column="1" x:Name="tokText" Text="--" Foreground="#64748B" FontSize="13" FontFamily="Consolas"/>
          </Grid>
          <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition Width="70"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <TextBlock Grid.Column="0" Text="LIFETIME" Foreground="#5A8AAA"
                       FontSize="10" FontFamily="Bahnschrift SemiBold" VerticalAlignment="Center"/>
            <TextBlock Grid.Column="1" x:Name="lifeText" Text="--" Foreground="#64748B" FontSize="13" FontFamily="Consolas"/>
          </Grid>
        </StackPanel>

      </StackPanel>
    </DockPanel>
  </Border>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$script:window = [System.Windows.Markup.XamlReader]::Load($reader)

# ---------------------------------------------------------------------------
# Theme application
# ---------------------------------------------------------------------------
function Apply-Theme([string]$name) {
    $t = $script:Themes[$name]
    if (-not $t) { return }

    $bars   = @('fivehBar','weekBar','sonBar','opusBar')
    $labels = @('fivehLabel','weekLabel','sonLabel','opusLabel')
    $subs   = @('fivehSub','weekSub','sonSub','opusSub')
    $fgKeys = @('FivehFg','WeekFg','SonFg','OpusFg')
    $bgKeys = @('FivehColors','WeekColors','SonColors','OpusColors')

    for ($i = 0; $i -lt 4; $i++) {
        $b = $script:window.FindName($bars[$i])
        if ($b) { $b.Background = New-GradientBrush $t[$bgKeys[$i]][0] $t[$bgKeys[$i]][1] }
        $l = $script:window.FindName($labels[$i])
        if ($l) { $l.Foreground = NewBrush $t[$fgKeys[$i]] }
        $s = $script:window.FindName($subs[$i])
        if ($s) { $s.Foreground = NewBrush ($t[$fgKeys[$i]] + '55') }
    }

    # Update the rainbow stripe
    $stripe = $script:window.FindName('accentStripe')
    if ($stripe) {
        $gb = New-Object System.Windows.Media.LinearGradientBrush
        $gb.StartPoint = [System.Windows.Point]::new(0,0)
        $gb.EndPoint   = [System.Windows.Point]::new(1,0)
        $offsets = @(0, 0.33, 0.66, 1)
        for ($i = 0; $i -lt 4; $i++) {
            $gs = New-Object System.Windows.Media.GradientStop
            $gs.Color  = [System.Windows.Media.ColorConverter]::ConvertFromString($t.Stripe[$i])
            $gs.Offset = $offsets[$i]
            [void]$gb.GradientStops.Add($gs)
        }
        $stripe.Background = $gb
    }

    # Sync checkmarks on theme menu items (WinForms: .Checked not .IsChecked)
    if ($script:themeItems) {
        foreach ($kv in $script:themeItems.GetEnumerator()) {
            $kv.Value.Checked = ($kv.Key -eq $name)
        }
    }
}

# ---------------------------------------------------------------------------
# Set-Bar — shows REMAINING capacity (100 - utilisation)
# Bar width: full = 100% remaining, empty = 0% remaining
# ---------------------------------------------------------------------------
function Set-Bar([string]$bar, [string]$pct, [string]$sub, [string]$reset, $util, $resetsAt) {
    $b  = $script:window.FindName($bar)
    $p  = $script:window.FindName($pct)
    $sb = if ($sub)   { $script:window.FindName($sub)   } else { $null }
    $r  = if ($reset) { $script:window.FindName($reset) } else { $null }
    if ($null -eq $util) {
        $b.Width = 0; $p.Text = '--'; $p.Foreground = NewBrush '#F1F5F9'
        if ($sb) { $sb.Text = 'used' }
        if ($r)  { $r.Text  = '' }
        return
    }
    $u        = [double]$util
    $b.Width  = [math]::Max(0, [math]::Min($script:BarTrackWidth, [math]::Round($u / 100.0 * $script:BarTrackWidth)))
    $p.Text   = ('{0:0}%' -f $u)
    # Colour: white → amber → red as usage climbs
    $fg = if ($u -ge 95) { '#F87171' } elseif ($u -ge 80) { '#FBBF24' } else { '#F1F5F9' }
    $p.Foreground = NewBrush $fg
    if ($sb) { $sb.Text = if ($u -ge 95) { 'critical!' } elseif ($u -ge 80) { 'high' } else { 'used' } }
    if ($r)  { $r.Text  = Format-Reset $resetsAt }
}

# ---------------------------------------------------------------------------
# Update-UI
# ---------------------------------------------------------------------------
function Update-UI {
    $dot  = $script:window.FindName('statusDot')
    $time = $script:window.FindName('timeText')

    switch ($script:State.Status) {
        'ok'    { $dot.Fill = NewBrush '#4ADE80' }
        'stale' { $dot.Fill = NewBrush '#FBBF24' }
        'auth'  { $dot.Fill = NewBrush '#F87171' }
        'error' { $dot.Fill = NewBrush '#F87171' }
        default { $dot.Fill = NewBrush '#4B6A8A' }
    }

    $s = $script:Stats
    if ($s) {
        $script:window.FindName('valText').Text   = ('~{0} all-time' -f (Fmt-Money $s.ValueUSD))
        $script:window.FindName('tokText').Text   = ('{0} in / {1} out' -f (Fmt-Tok $s.InTokens), (Fmt-Tok $s.OutTokens))
$script:window.FindName('lifeText').Text  = ('{0} sess · {1} msgs' -f $s.Sessions, (Fmt-Tok $s.Messages))
        $script:window.FindName('statsPanel').ToolTip = ('Cache last updated: {0}' -f $s.LastComputed)
    }

    $d = $script:State.Data
    if ($null -eq $d) {
        Set-Bar 'fivehBar' 'fivehPct' 'fivehSub' 'fivehReset' $null $null
        Set-Bar 'weekBar'  'weekPct'  'weekSub'  'weekReset'  $null $null
        Set-Bar 'sonBar'   'sonPct'   'sonSub'   'sonReset'   $null $null
        $time.Text = if ($script:State.Message) { $script:State.Message } else { 'connecting...' }
        return
    }

    Set-Bar 'fivehBar' 'fivehPct' 'fivehSub' 'fivehReset' $d.five_hour.utilization        $d.five_hour.resets_at
    Set-Bar 'weekBar'  'weekPct'  'weekSub'  'weekReset'  $d.seven_day.utilization         $d.seven_day.resets_at
    Set-Bar 'sonBar'   'sonPct'   'sonSub'   'sonReset'   $d.seven_day_sonnet.utilization  $d.seven_day_sonnet.resets_at

    if ($d.seven_day_opus) {
        $script:window.FindName('opusRow').Visibility = [System.Windows.Visibility]::Visible
        Set-Bar 'opusBar' 'opusPct' 'opusSub' 'opusReset' $d.seven_day_opus.utilization $d.seven_day_opus.resets_at
    } else {
        $script:window.FindName('opusRow').Visibility = [System.Windows.Visibility]::Collapsed
    }

    $ex = $d.extra_usage
    if ($ex -and $ex.is_enabled -and $ex.monthly_limit) {
        $sym   = if ($ex.currency -eq 'USD') { '$' } else { "$($ex.currency) " }
        $used  = [double]$ex.used_credits  / 100.0
        $limit = [double]$ex.monthly_limit / 100.0
        $script:window.FindName('extraRow').Visibility = [System.Windows.Visibility]::Visible
        $script:window.FindName('extraVal').Text = ('{0}{1:N2} / {0}{2:N0}' -f $sym, $used, $limit)
    } else {
        $script:window.FindName('extraRow').Visibility = [System.Windows.Visibility]::Collapsed
    }

    $time.Text = if ($script:State.Status -eq 'ok') { $script:State.LastFetch } else { $script:State.Message }
    if ($script:notify) {
        $script:notify.Text = ('Claude  5h {0:0}%  Wk {1:0}%' -f [double]$d.five_hour.utilization, [double]$d.seven_day.utilization)
    }
}

# ---------------------------------------------------------------------------
# Settings persistence
# ---------------------------------------------------------------------------
$script:Cfg = @{
    Left        = $null
    Top         = $null
    Opacity     = 1.0
    StartHidden = $false
    ShowStats   = $true
    Theme       = 'Deep Space'
}

function Save-State {
    try {
        $script:Cfg.Left = $script:window.Left
        $script:Cfg.Top  = $script:window.Top
        $script:Cfg | ConvertTo-Json | Set-Content -Path $script:StatePath -Encoding UTF8
    } catch { }
}

function Load-State {
    try {
        if (-not (Test-Path $script:StatePath)) { return }
        $s = Get-Content $script:StatePath -Raw | ConvertFrom-Json
        foreach ($k in @('Left','Top','Opacity','StartHidden','ShowStats','Theme')) {
            if ($null -ne $s.$k) { $script:Cfg[$k] = $s.$k }
        }
    } catch { }
}

function Apply-Settings {
    # Opacity is set via PendingOpacity → DispatcherTimer (never from WinForms thread directly)
    $script:PendingOpacity = [double]$script:Cfg.Opacity
    $vis = if ($script:Cfg.ShowStats) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    $sp = $script:window.FindName('statsPanel'); if ($sp) { $sp.Visibility = $vis }
    Apply-Theme $script:Cfg.Theme
}

# ---------------------------------------------------------------------------
# Window positioning — clamps to work area so it never goes off-screen
# ---------------------------------------------------------------------------
function Clamp-Position {
    $wa = [System.Windows.SystemParameters]::WorkArea
    $w  = $script:window.ActualWidth
    $h  = $script:window.ActualHeight
    $script:window.Left = [math]::Max($wa.Left, [math]::Min($script:window.Left, $wa.Right  - $w))
    $script:window.Top  = [math]::Max($wa.Top,  [math]::Min($script:window.Top,  $wa.Bottom - $h))
}

function Snap-ToCorner([string]$corner) {
    $wa = [System.Windows.SystemParameters]::WorkArea
    $w  = $script:window.ActualWidth;  $h = $script:window.ActualHeight
    switch ($corner) {
        'TR' { $script:window.Left = $wa.Right - $w - 16; $script:window.Top = $wa.Top    + 16 }
        'TL' { $script:window.Left = $wa.Left  + 16;      $script:window.Top = $wa.Top    + 16 }
        'BR' { $script:window.Left = $wa.Right - $w - 16; $script:window.Top = $wa.Bottom - $h - 16 }
        'BL' { $script:window.Left = $wa.Left  + 16;      $script:window.Top = $wa.Bottom - $h - 16 }
    }
    Save-State
}

function Position-Window {
    if ($script:Positioned) { return }
    $script:Positioned = $true
    if ($null -ne $script:Cfg.Left) {
        $script:window.Left = [double]$script:Cfg.Left
        $script:window.Top  = [double]$script:Cfg.Top
        Clamp-Position
    } else {
        Snap-ToCorner 'TR'
    }
}

function Copy-Stats {
    $d = $script:State.Data; $s = $script:Stats
    $lines = @("Claude Code Usage — $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
    if ($d) {
        $lines += "5-hour:  $([math]::Round(100-[double]$d.five_hour.utilization))% remaining  ($(Format-Reset $d.five_hour.resets_at))"
        $lines += "Weekly:  $([math]::Round(100-[double]$d.seven_day.utilization))% remaining  ($(Format-Reset $d.seven_day.resets_at))"
        if ($d.seven_day_sonnet) { $lines += "Sonnet:  $([math]::Round(100-[double]$d.seven_day_sonnet.utilization))% remaining" }
        if ($d.seven_day_opus)   { $lines += "Opus:    $([math]::Round(100-[double]$d.seven_day_opus.utilization))% remaining" }
    }
    if ($s) {
        $lines += "Est. API value: ~$(Fmt-Money $s.ValueUSD) all-time"
        $lines += "Tokens: $(Fmt-Tok $s.InTokens) in / $(Fmt-Tok $s.OutTokens) out"
        $lines += "Lifetime: $($s.Sessions) sessions / $(Fmt-Tok $s.Messages) msgs"
    }
    [System.Windows.Clipboard]::SetText(($lines -join "`n"))
}

# ---------------------------------------------------------------------------
# Window events
# ---------------------------------------------------------------------------
$script:window.Add_MouseLeftButtonDown({ try { $script:window.DragMove() } catch { }; Save-State })
$script:window.Add_Loaded({ Position-Window })
$script:window.Add_Closing({ param($s, $e) if (-not $script:ReallyQuit) { $e.Cancel = $true; $script:window.Hide() } })

function Toggle-Window {
    if ($script:window.IsVisible) { $script:window.Hide() }
    else { $script:window.Show(); $script:window.Activate(); $script:window.Topmost = $true }
}

function Quit-App {
    $script:ReallyQuit = $true
    if ($script:pollTimer) { $script:pollTimer.Stop() }
    if ($script:tickTimer) { $script:tickTimer.Stop() }
    if ($script:notify)    { $script:notify.Visible = $false; $script:notify.Dispose() }
    if (Test-Path $script:PidPath) { Remove-Item $script:PidPath -Force -EA SilentlyContinue }
    $script:window.Close()
    $script:window.Dispatcher.InvokeShutdown()
}

# ---------------------------------------------------------------------------
# Right-click context menu — dark-themed WinForms ContextMenuStrip shown
# from the WPF panel's MouseRightButtonUp event.
# ---------------------------------------------------------------------------
$script:themeItems  = @{}
function Set-Opacity([double]$val, [string]$label) {
    $script:Cfg.Opacity = $val
    $script:PendingOpacity = $val   # DispatcherTimer applies this on WPF thread
    Save-State
    foreach ($x in $script:opacityItems.Values) { $x.Checked = $false }
    if ($script:opacityItems.ContainsKey($label)) { $script:opacityItems[$label].Checked = $true }
}
$script:opacityItems = @{}

# Dark colour table for the strip renderer
# Resolve already-loaded assembly paths so Add-Type can find them under .NET 6+
$_sdPath  = [System.Drawing.Color].Assembly.Location
$_swfPath = [System.Windows.Forms.Form].Assembly.Location
Add-Type -ReferencedAssemblies $_sdPath, $_swfPath -TypeDefinition @'
using System.Drawing;
using System.Windows.Forms;
public class DarkColorTable : ProfessionalColorTable {
    public override Color MenuItemSelected              => Color.FromArgb(30,  58, 95);
    public override Color MenuItemBorder                => Color.FromArgb(56, 130, 180);
    public override Color MenuBorder                    => Color.FromArgb(30,  58, 95);
    public override Color ToolStripDropDownBackground   => Color.FromArgb(13,  20, 40);
    public override Color ImageMarginGradientBegin      => Color.FromArgb(13,  20, 40);
    public override Color ImageMarginGradientMiddle     => Color.FromArgb(13,  20, 40);
    public override Color ImageMarginGradientEnd        => Color.FromArgb(13,  20, 40);
    public override Color CheckBackground               => Color.FromArgb(30,  58, 95);
    public override Color CheckSelectedBackground       => Color.FromArgb(56, 130, 180);
    public override Color SeparatorDark                 => Color.FromArgb(30,  58, 95);
    public override Color SeparatorLight                => Color.FromArgb(13,  20, 40);
    public override Color MenuItemSelectedGradientBegin => Color.FromArgb(30,  58, 95);
    public override Color MenuItemSelectedGradientEnd   => Color.FromArgb(30,  58, 95);
    public override Color MenuItemPressedGradientBegin  => Color.FromArgb(56, 130, 180);
    public override Color MenuItemPressedGradientEnd    => Color.FromArgb(56, 130, 180);
    public override Color MenuStripGradientBegin        => Color.FromArgb(13,  20, 40);
    public override Color MenuStripGradientEnd          => Color.FromArgb(13,  20, 40);
}
public class DarkMenuRenderer : ToolStripProfessionalRenderer {
    public DarkMenuRenderer() : base(new DarkColorTable()) { RoundedEdges = false; }
}
'@

$darkFg   = [System.Drawing.Color]::FromArgb(203, 213, 225)
$darkBg   = [System.Drawing.Color]::FromArgb(13, 20, 40)
$menuFont = New-Object System.Drawing.Font('Segoe UI', 9.5)

function New-StripItem([string]$text, [scriptblock]$onClick) {
    $mi = New-Object System.Windows.Forms.ToolStripMenuItem($text)
    $mi.ForeColor = $darkFg
    $mi.BackColor = $darkBg
    $mi.Font      = $menuFont
    if ($onClick) { $mi.add_Click($onClick) }
    return $mi
}

$script:ctxStrip = New-Object System.Windows.Forms.ContextMenuStrip
$script:ctxStrip.Renderer  = New-Object DarkMenuRenderer
$script:ctxStrip.BackColor = $darkBg
$script:ctxStrip.ForeColor = $darkFg
$script:ctxStrip.Font      = $menuFont
$script:ctxStrip.ShowImageMargin = $false

function Add-Separator {
    $sep = New-Object System.Windows.Forms.ToolStripSeparator
    $sep.BackColor = $darkBg; $sep.ForeColor = $darkFg
    [void]$script:ctxStrip.Items.Add($sep)
}

# ── Actions ───────────────────────────────────────────────────────────────
[void]$script:ctxStrip.Items.Add((New-StripItem 'Refresh now'             { Get-Usage; Get-Stats; Update-UI }))
[void]$script:ctxStrip.Items.Add((New-StripItem 'Copy stats to clipboard' { Copy-Stats }))
[void]$script:ctxStrip.Items.Add((New-StripItem 'Open claude.ai/usage'    { Start-Process 'https://claude.ai/settings/limits' }))
Add-Separator

# ── Snap to corner ────────────────────────────────────────────────────────
$miSnap = New-StripItem 'Snap to corner' $null
foreach ($pair in @(('Top right','TR'),('Top left','TL'),('Bottom right','BR'),('Bottom left','BL'))) {
    $lbl = $pair[0]; $key = $pair[1]
    $sub = New-StripItem $lbl ([scriptblock]::Create("Snap-ToCorner '$key'"))
    [void]$miSnap.DropDownItems.Add($sub)
}
[void]$script:ctxStrip.Items.Add($miSnap)

# ── Opacity ───────────────────────────────────────────────────────────────
$miOp = New-StripItem 'Opacity' $null
foreach ($pair in @(('100%',1.0),('80%',0.8),('60%',0.6),('40%',0.4))) {
    $lbl = $pair[0]; $val = $pair[1]
    $sub = New-StripItem $lbl ([scriptblock]::Create("Set-Opacity $val '$lbl'"))
    $sub.CheckOnClick = $false
    $sub.Checked = ([double]$script:Cfg.Opacity -eq [double]$val)
    $script:opacityItems[$lbl] = $sub
    [void]$miOp.DropDownItems.Add($sub)
}
[void]$script:ctxStrip.Items.Add($miOp)

# ── Themes ────────────────────────────────────────────────────────────────
$miTheme = New-StripItem 'Theme' $null
foreach ($tname in $script:Themes.Keys) {
    $tn  = $tname
    $sub = New-StripItem $tname ([scriptblock]::Create("`$script:Cfg.Theme='$tn'; Apply-Theme '$tn'; Save-State; foreach(`$x in `$script:themeItems.Values){`$x.Checked=`$false}; `$script:themeItems['$tn'].Checked=`$true"))
    $sub.CheckOnClick = $false
    $sub.Checked = ($tname -eq $script:Cfg.Theme)
    $script:themeItems[$tname] = $sub
    [void]$miTheme.DropDownItems.Add($sub)
}
[void]$script:ctxStrip.Items.Add($miTheme)
Add-Separator

# ── Toggles ───────────────────────────────────────────────────────────────
$miStats = New-StripItem 'Show stats panel' {
    $script:Cfg.ShowStats = -not [bool]$script:Cfg.ShowStats
    $miStats.Checked = [bool]$script:Cfg.ShowStats
    Apply-Settings; Save-State
}
$miStats.Checked = [bool]$script:Cfg.ShowStats
[void]$script:ctxStrip.Items.Add($miStats)

$script:miLogin = New-StripItem 'Open at login' {
    if (Test-Autostart) { Uninstall-Autostart } else { Install-Autostart }
    $script:miLogin.Checked = (Test-Autostart)
}
$script:miLogin.Checked = (Test-Autostart)
[void]$script:ctxStrip.Items.Add($script:miLogin)

$miSH = New-StripItem 'Start hidden to tray' {
    $script:Cfg.StartHidden = -not [bool]$script:Cfg.StartHidden
    $miSH.Checked = [bool]$script:Cfg.StartHidden; Save-State
}
$miSH.Checked = [bool]$script:Cfg.StartHidden
[void]$script:ctxStrip.Items.Add($miSH)
Add-Separator

# ── Window ────────────────────────────────────────────────────────────────
[void]$script:ctxStrip.Items.Add((New-StripItem 'Minimize to tray' { $script:window.Hide() }))
[void]$script:ctxStrip.Items.Add((New-StripItem 'Quit'             { Quit-App }))

# Show at cursor on right-click anywhere on the WPF panel
$script:window.Add_MouseRightButtonUp({
    $pt = [System.Windows.Forms.Control]::MousePosition
    $script:ctxStrip.Show($pt.X, $pt.Y)
})

# ---------------------------------------------------------------------------
# Tray icon — left-click only (full menu is on the panel)
# ---------------------------------------------------------------------------
function New-TrayIcon {
    $bmp = New-Object System.Drawing.Bitmap 32, 32
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $grd = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Point 1,1),(New-Object System.Drawing.Point 31,31),
        [System.Drawing.Color]::FromArgb(255,30,58,138),[System.Drawing.Color]::FromArgb(255,109,40,217))
    $g.FillEllipse($grd,1,1,30,30)
    $fnt = New-Object System.Drawing.Font('Bahnschrift',14,[System.Drawing.FontStyle]::Bold)
    $sf  = New-Object System.Drawing.StringFormat
    $sf.Alignment = [System.Drawing.StringAlignment]::Center
    $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
    $g.DrawString('C',$fnt,[System.Drawing.Brushes]::White,(New-Object System.Drawing.RectangleF(0,0,32,32)),$sf)
    $g.Dispose()
    return [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}

$script:notify = New-Object System.Windows.Forms.NotifyIcon
$script:notify.Icon    = New-TrayIcon
$script:notify.Text    = 'Claude Usage  (left-click to show)'
$script:notify.Visible = $true
$script:notify.add_MouseClick({ param($s,$e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { Toggle-Window }
})

# ---------------------------------------------------------------------------
# Timers
# ---------------------------------------------------------------------------
$script:pollTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:pollTimer.Interval = [TimeSpan]::FromSeconds(180)
$script:pollTimer.add_Tick({ Get-Usage; Get-Stats; Update-UI })

$script:tickTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:tickTimer.Interval = [TimeSpan]::FromSeconds(30)
$script:tickTimer.add_Tick({ Update-UI })

# ---------------------------------------------------------------------------
# Go
# ---------------------------------------------------------------------------
Load-State
Get-Usage
Get-Stats
Update-UI
Apply-Settings   # applies theme, opacity, stats visibility

# Opacity timer — only place that touches $script:window.Opacity; runs on WPF dispatcher thread
$script:opacityTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:opacityTimer.Interval = [TimeSpan]::FromMilliseconds(100)
$script:opacityTimer.add_Tick({
    if ($null -ne $script:PendingOpacity) {
        try { $script:window.Opacity = [double]$script:PendingOpacity } catch { }
        $script:PendingOpacity = $null
    }
})

$script:pollTimer.Start()
$script:tickTimer.Start()
$script:opacityTimer.Start()

if (-not $Hidden -and -not [bool]$script:Cfg.StartHidden) { $script:window.Show() }

[System.Windows.Threading.Dispatcher]::Run()

}
catch {
    $msg = "[{0}] {1}`n{2}" -f (Get-Date -Format 's'), $_.Exception.Message, $_.ScriptStackTrace
    try { Add-Content -Path $script:ErrLog -Value $msg } catch { }
    throw
}
