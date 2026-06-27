$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Anime.js Installer" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Get project path from user
$projectPath = Read-Host "Enter your project path (drag folder here or type path)"

# Remove surrounding quotes if present
$projectPath = $projectPath.Trim('"').Trim("'")

# Validate path exists
if (-not (Test-Path $projectPath)) {
    Write-Host ""
    Write-Host "[ERROR] Path does not exist: $projectPath" -ForegroundColor Red
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

# Check for package.json
$pkgJson = Join-Path $projectPath "package.json"
if (-not (Test-Path $pkgJson)) {
    Write-Host ""
    Write-Host "[WARNING] No package.json found in: $projectPath" -ForegroundColor Yellow
    Write-Host "This doesn't look like a Node.js project." -ForegroundColor Yellow
    
    $initChoice = Read-Host "Run 'npm init -y' to initialize? (y/n)"
    if ($initChoice -eq 'y') {
        Push-Location $projectPath
        npm init -y
        Pop-Location
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[ERROR] npm init failed." -ForegroundColor Red
            Read-Host "Press Enter to exit"
            exit 1
        }
        Write-Host "[OK] package.json created." -ForegroundColor Green
    } else {
        Write-Host "Aborted. A Node.js project with package.json is required." -ForegroundColor Yellow
        Read-Host "Press Enter to exit"
        exit 0
    }
}

Write-Host ""
Write-Host "[INFO] Installing animejs into: $projectPath" -ForegroundColor White

Push-Location $projectPath

# Run npm install animejs
npm install animejs

if ($LASTEXITCODE -ne 0) {
    Pop-Location
    Write-Host ""
    Write-Host "[ERROR] npm install animejs failed." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

Pop-Location

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Anime.js installed successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Usage in your project:" -ForegroundColor White
Write-Host ""
Write-Host "  import { animate, stagger, timeline } from 'animejs';" -ForegroundColor Yellow
Write-Host ""
Write-Host "Quick example:" -ForegroundColor White
Write-Host '  animate(".box", {' -ForegroundColor DarkGray
Write-Host '      x: [0, 200],' -ForegroundColor DarkGray
Write-Host '      rotate: { from: -180 },' -ForegroundColor DarkGray
Write-Host '      duration: 1000,' -ForegroundColor DarkGray
Write-Host '      ease: "outExpo"' -ForegroundColor DarkGray
Write-Host '  });' -ForegroundColor DarkGray
Write-Host ""
Write-Host "Docs: https://animejs.com/documentation" -ForegroundColor Cyan

Read-Host "Press Enter to exit"
