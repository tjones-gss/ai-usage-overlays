# AI Usage Overlays — one-liner installer
# Installs both the Claude Code and Cursor usage overlays.
#
# Run in PowerShell (or paste to your Claude / Cursor agent):
#   irm https://raw.githubusercontent.com/tjones-gss/ai-usage-overlays/master/install.ps1 | iex

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$repo    = 'https://github.com/tjones-gss/ai-usage-overlays/archive/refs/heads/master.zip'
$zip     = Join-Path $env:TEMP 'ai-usage-overlays.zip'
$extract = Join-Path $env:TEMP 'ai-usage-overlays-extract'
$src     = Join-Path $extract  'ai-usage-overlays-master'

Write-Host 'Downloading AI Usage Overlays...'
Invoke-WebRequest $repo -OutFile $zip -UseBasicParsing

Write-Host 'Extracting...'
if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
Expand-Archive $zip $extract -Force

# Prefer pwsh if available, fall back to built-in powershell.exe
$ps = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }

# --- Claude overlay ---
Write-Host 'Installing Claude overlay...'
$claudeDest = "$env:LOCALAPPDATA\ClaudeUsageOverlay"
New-Item -ItemType Directory -Force $claudeDest | Out-Null
Copy-Item "$src\overlay.ps1"        $claudeDest -Force
Copy-Item "$src\Start-Overlay.vbs"  $claudeDest -Force
Copy-Item "$src\Install.bat"        $claudeDest -Force
Copy-Item "$src\Uninstall.bat"      $claudeDest -Force
if (Test-Path "$src\src") {
    if (-not (Test-Path "$claudeDest\src")) { New-Item -ItemType Directory "$claudeDest\src" | Out-Null }
    Copy-Item "$src\src\*" "$claudeDest\src\" -Force
}
& $ps -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$claudeDest\overlay.ps1" -Install

# --- Cursor overlay ---
Write-Host 'Installing Cursor overlay...'
$cursorDest = "$env:LOCALAPPDATA\CursorUsageOverlay"
New-Item -ItemType Directory -Force $cursorDest | Out-Null
Copy-Item "$src\cursor-overlay.ps1"      $cursorDest -Force
Copy-Item "$src\sqlite3.exe"             $cursorDest -Force
Copy-Item "$src\Start-CursorOverlay.vbs" $cursorDest -Force
Copy-Item "$src\Install.bat"             $cursorDest -Force
Copy-Item "$src\Uninstall.bat"           $cursorDest -Force
& $ps -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$cursorDest\cursor-overlay.ps1" -Install

# Cleanup
Remove-Item $zip     -Force        -ErrorAction SilentlyContinue
Remove-Item $extract -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host 'Done! Both overlays are installed and running.'
Write-Host 'Look for the C (Claude) and Cu (Cursor) icons in your system tray.'
Write-Host 'Right-click either icon for options, themes, and opacity.'
