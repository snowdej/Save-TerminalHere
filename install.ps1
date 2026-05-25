# Save-TerminalHere one-liner installer.
#
# Usage:
#   irm https://raw.githubusercontent.com/snowdej/Save-TerminalHere/main/install.ps1 | iex
#
# What it does:
#   1. Verifies PowerShell 7+ (the module uses pwsh-only syntax).
#   2. Finds your user-scope PowerShell modules directory.
#   3. Clones (or updates) the repo into it.
#   4. Imports the module and wires $PROFILE so it autoloads.

$ErrorActionPreference = 'Stop'

# #Requires is only honoured when a script is invoked directly. iex executes
# the body as a string, so we runtime-check the version ourselves.
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host ""
    Write-Host "Save-TerminalHere requires PowerShell 7 or later." -ForegroundColor Red
    Write-Host "You are currently running PowerShell $($PSVersionTable.PSVersion)." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Open a 'PowerShell' tab (pwsh.exe) in Windows Terminal and re-run, or install pwsh:" -ForegroundColor Yellow
    Write-Host "  winget install --id Microsoft.PowerShell" -ForegroundColor Cyan
    Write-Host ""
    return
}

$repoUrl = 'https://github.com/snowdej/Save-TerminalHere.git'
$moduleName = 'Save-TerminalHere'

function Resolve-UserModulePath {
    $candidates = $env:PSModulePath -split [System.IO.Path]::PathSeparator |
        Where-Object { $_ -and $_ -match 'Documents.PowerShell.Modules$' } |
        Sort-Object -Unique

    if (-not $candidates) {
        $fallback = Join-Path $HOME 'Documents\PowerShell\Modules'
        Write-Warning "Could not find a pwsh user-scope modules path on PSModulePath. Falling back to: $fallback"
        return $fallback
    }

    $candidates | Select-Object -First 1
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git is required and not on PATH. Install git (winget install Git.Git), reopen PowerShell, then retry."
}

$modulesRoot = Resolve-UserModulePath
$dest = Join-Path $modulesRoot $moduleName

if (-not (Test-Path $modulesRoot)) {
    New-Item -ItemType Directory -Path $modulesRoot -Force | Out-Null
}

if (Test-Path $dest) {
    Write-Host "[$moduleName] Already installed at $dest. Pulling latest..." -ForegroundColor Cyan
    Push-Location $dest
    try {
        # Let git's own output stream to the console; git uses stderr for normal
        # status messages and we don't want PS to dramatize them as errors.
        git pull --ff-only
        if ($LASTEXITCODE -ne 0) { throw "git pull failed (exit $LASTEXITCODE)" }
    } finally {
        Pop-Location
    }
} else {
    Write-Host "[$moduleName] Cloning to $dest..." -ForegroundColor Cyan
    git clone --depth 1 $repoUrl $dest
    if ($LASTEXITCODE -ne 0) { throw "git clone failed (exit $LASTEXITCODE)" }
}

Remove-Module $moduleName -Force -ErrorAction SilentlyContinue
Import-Module $moduleName -Force

Write-Host "[$moduleName] Wiring `$PROFILE..." -ForegroundColor Cyan
Install-SaveTerminalHere | Format-List

$installedVersion = (Get-Module $moduleName).Version
Write-Host ""
Write-Host "  Save-TerminalHere $installedVersion installed." -ForegroundColor Green
Write-Host "  Repo: https://github.com/snowdej/Save-TerminalHere" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Quick reference:" -ForegroundColor Cyan
Write-Host ""
Write-Host "  # Bookmark the current directory:"
Write-Host "  Save-TerminalHere work" -ForegroundColor White
Write-Host ""
Write-Host "  # Bookmark with a coloured tab:"
Write-Host "  Save-TerminalHere notes -TabColor `"#2EA043`"" -ForegroundColor White
Write-Host ""
Write-Host "  # Bookmark + auto-launch a fresh Claude session:"
Write-Host "  Save-TerminalHere claude-work -Claude `"`"" -ForegroundColor White
Write-Host ""
Write-Host "  # Bookmark + resume latest Claude session matching <id> (name defaults to id):"
Write-Host "  Save-TerminalHere -Claude note-2026" -ForegroundColor White
Write-Host ""
Write-Host "  # Browse, rename, delete:"
Write-Host "  Get-TerminalHere" -ForegroundColor White
Write-Host "  Rename-TerminalHere work work-archive" -ForegroundColor White
Write-Host "  Remove-TerminalHere work-archive" -ForegroundColor White
Write-Host ""
Write-Host "  # Move bookmarks to another machine:"
Write-Host "  Export-TerminalHere -IncludeSchemes      # writes to ~\Desktop" -ForegroundColor White
Write-Host "  Import-TerminalHere <path>               # on the other machine" -ForegroundColor White
Write-Host ""
Write-Host "Bookmarks appear at the top of your Windows Terminal dropdown." -ForegroundColor DarkGray
