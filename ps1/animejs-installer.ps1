<# rn.SYNOPSISrn Anime.js project installer - projectInstall animejs npm rn.DESCRIPTIONrn InputprojectPath,automatic project run npm install animejsrn.NOTESrn : 1.0rn groupId: skillrn order: 59rn#>rnrn$ErrorActionPreference = "Stop"rn[Console]::OutputEncoding = [Text.Encoding]::UTF8rnrnWrite-Host ""rnWrite-Host "========================================" -ForegroundColor CyanrnWrite-Host " Anime.js project installer" -ForegroundColor CyanrnWrite-Host "========================================" -ForegroundColor CyanrnWrite-Host ""rnWrite-Host ": projectInstall animejs npm " -ForegroundColor GrayrnWrite-Host ""

do {
 $projectPath = Read-Host "Enter projectPath(folder)"
 $projectPath = $projectPath.Trim('"').Trim("'").Trim()
 
 if ([string]::IsNullOrWhiteSpace($projectPath)) {
 Write-Host "[ERROR] Pathcannot be empty, Input" -ForegroundColor Red
 continue
 }
 
 if (-not (Test-Path $projectPath)) {
 Write-Host "[ERROR] Pathdoes not exist: $projectPath" -ForegroundColor Red
 continue
 }
 
 break
} while ($true)

Write-Host ""
Write-Host " Path: $projectPath" -ForegroundColor Yellow

if (-not (Test-Path (Join-Path $projectPath "package.json"))) {
 Write-Host ""
 Write-Host "[ 1/2] project..." -ForegroundColor Cyan
 
 Push-Location $projectPath
 
 try {
 npm init -y
 
 if ($LASTEXITCODE -ne 0) {
 throw "npm init -y runFailed"
 }
 
 Write-Host " OK package.json createSuccess" -ForegroundColor Green
 
 node -e "const fs=require('fs');const pkg=JSON.parse(fs.readFileSync('package.json','utf8'));pkg.type='module';fs.writeFileSync('package.json',JSON.stringify(pkg,null,2)+'\n');"

 Write-Host " OK package.json type module(ESM import)" -ForegroundColor Green

 } catch {
 Pop-Location
 Write-Host "[ERROR] $_" -ForegroundColor Red
 pause
 exit 1
 }

} else {
 Write-Host "[ 1/2] package.json,skip " -ForegroundColor Gray
}

Write-Host ""
Write-Host "[ 2/2] Install animejs..." -ForegroundColor Cyan

Push-Location $projectPath

try {
 npm install animejs --save

 if ($LASTEXITCODE -ne 0) {
 throw "npm install animejs runFailed"
 }

 Write-Host " OK animejs InstallSuccess!" -ForegroundColor Green

} catch {
 Pop-Location
 Write-Host "[ERROR] $_" -ForegroundColor Red
 pause
 exit 1
}

Pop-Location

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " InstallDone!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

$pkgJson = Get-Content (Join-Path $projectPath "package.json") | ConvertFrom-Json

if ($pkgJson.dependencies.animejs) {
 Write-Host ""
 Write-Host " animejs : $($pkgJson.dependencies.animejs)" -ForegroundColor Cyan
 Write-Host ""
 Write-Host ":" -ForegroundColor Yellow
 Write-Host " import { animate, stagger, timeline } from 'animejs';" -ForegroundColor White
 Write-Host ""
 Write-Host " animate('.box', { x: 300, duration: 800 });" -ForegroundColor Gray
} else {
 Write-Host "[WARN] package.json animejs " -ForegroundColor Yellow
}

pause