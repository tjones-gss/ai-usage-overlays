<#
.SYNOPSIS
    Web installer for Cursor Usage Overlay.
.DESCRIPTION
    Downloads the latest release zip and installs to %LOCALAPPDATA%\CursorUsageOverlay.
    Usage: iwr -useb <url>/install.ps1 | iex
#>

# ── Configuration ──────────────────────────────────────────────────────────
$BaseUrl = '<SET-ME>'  # e.g. https://raw.githubusercontent.com/kcao-gss/ai-usage-overlays/cursor
# ───────────────────────────────────────────────────────────────────────────

$ZipUrl = "$BaseUrl/CursorUsageOverlay.zip"
$Dest   = Join-Path $env:LOCALAPPDATA 'CursorUsageOverlay'
$Tmp    = Join-Path $env:TEMP 'CursorUsageOverlay-install.zip'

# Ensure TLS 1.2 (required on Windows PowerShell 5.1)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host 'Cursor Usage Overlay — Installer' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Downloading...' -NoNewline
Invoke-WebRequest -Uri $ZipUrl -OutFile $Tmp -UseBasicParsing
Write-Host ' done.'

Write-Host 'Extracting...' -NoNewline
if (Test-Path $Dest) { Remove-Item $Dest -Recurse -Force }
Expand-Archive -Path $Tmp -DestinationPath (Split-Path $Dest)
Remove-Item $Tmp -ErrorAction SilentlyContinue
Write-Host ' done.'

Write-Host 'Installing...'
& "$Dest\cursor-overlay.ps1" -Install

Write-Host ''
Write-Host 'Done! Look for the green "Cu" icon in your system tray.' -ForegroundColor Green
