$ErrorActionPreference = 'Stop'

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Test-CommandExists {
    param([string]$CommandName)
    return $null -ne (Get-Command $CommandName -ErrorAction SilentlyContinue)
}

function Read-ProjectPath {
    while ($true) {
        $inputPath = Read-Host 'Enter project path'
        $projectPath = $inputPath.Trim().Trim('"').Trim("'")

        if ([string]::IsNullOrWhiteSpace($projectPath)) {
            Write-Warn 'Project path cannot be empty.'
            continue
        }

        if (Test-Path -LiteralPath $projectPath -PathType Container) {
            return (Resolve-Path -LiteralPath $projectPath).Path
        }

        Write-Err "Path does not exist: $projectPath"
    }
}

Clear-Host
Write-Host '========================================' -ForegroundColor Magenta
Write-Host ' Anime.js Installer' -ForegroundColor Magenta
Write-Host '========================================' -ForegroundColor Magenta
Write-Host ''

if (-not (Test-CommandExists 'node')) {
    Write-Err 'Node.js is not installed or not available in PATH.'
    Write-Host 'Download Node.js: https://nodejs.org/' -ForegroundColor Yellow
    exit 1
}

if (-not (Test-CommandExists 'npm')) {
    Write-Err 'npm is not installed or not available in PATH.'
    Write-Host 'Install Node.js with npm: https://nodejs.org/' -ForegroundColor Yellow
    exit 1
}

$projectPath = Read-ProjectPath
Write-Info "Selected project: $projectPath"
Set-Location -LiteralPath $projectPath

if (-not (Test-Path -LiteralPath 'package.json' -PathType Leaf)) {
    Write-Warn 'No package.json found. Initializing project automatically...'
    npm init -y
    if ($LASTEXITCODE -ne 0) {
        Write-Err 'npm init failed.'
        exit $LASTEXITCODE
    }
}

Write-Info 'Installing animejs...'
npm install animejs

if ($LASTEXITCODE -ne 0) {
    Write-Err 'npm install animejs failed.'
    exit $LASTEXITCODE
}

Write-Host ''
Write-Ok 'animejs installed successfully.'
Write-Host ''
Write-Host 'Usage example:' -ForegroundColor Cyan
Write-Host "import { animate } from 'animejs';" -ForegroundColor Gray
Write-Host "animate('.box', { x: 250, rotate: '1turn', duration: 800 });" -ForegroundColor Gray
Write-Host ''
Write-Host 'Documentation: https://animejs.com/documentation' -ForegroundColor Cyan
Write-Host ''
Read-Host 'Press Enter to exit'
