<# rn.SYNOPSISrn    Anime.js 项目安装器 - 在指定项目中安装 animejs npm 包rn.DESCRIPTIONrn    输入项目路径，自动在该项目中执行 npm install animejsrn.NOTESrn    版本: 1.0rn    groupId: skillrn    order: 59rn#>rnrn$ErrorActionPreference = "Stop"rn[Console]::OutputEncoding = [Text.Encoding]::UTF8rnrnWrite-Host ""rnWrite-Host "========================================" -ForegroundColor CyanrnWrite-Host "     Anime.js 项目安装器" -ForegroundColor CyanrnWrite-Host "========================================" -ForegroundColor CyanrnWrite-Host ""rnWrite-Host "功能: 在指定项目中安装 animejs npm 包" -ForegroundColor GrayrnWrite-Host ""

do {
    $projectPath = Read-Host "请输入项目路径（或拖拽文件夹到此处）"
    $projectPath = $projectPath.Trim('"').Trim("'").Trim()
    
    if ([string]::IsNullOrWhiteSpace($projectPath)) {
        Write-Host "[错误] 路径不能为空，请重新输入" -ForegroundColor Red
        continue
    }
    
    if (-not (Test-Path $projectPath)) {
        Write-Host "[错误] 路径不存在: $projectPath" -ForegroundColor Red
        continue
    }
    
    break
} while ($true)

Write-Host ""
Write-Host "目标路径: $projectPath" -ForegroundColor Yellow

if (-not (Test-Path (Join-Path $projectPath "package.json"))) {
    Write-Host ""
    Write-Host "[步骤 1/2] 初始化项目..." -ForegroundColor Cyan
    
    Push-Location $projectPath
    
    try {
        npm init -y
        
        if ($LASTEXITCODE -ne 0) {
            throw "npm init -y 执行失败"
        }
        
        Write-Host "   ✓ package.json 创建成功" -ForegroundColor Green
        
        node -e "const fs=require('fs');const pkg=JSON.parse(fs.readFileSync('package.json','utf8'));pkg.type='module';fs.writeFileSync('package.json',JSON.stringify(pkg,null,2)+'\n');"

        Write-Host "   ✓ package.json type 已设为 module（支持 ESM import）" -ForegroundColor Green

    } catch {
        Pop-Location
        Write-Host "[错误] $_" -ForegroundColor Red
        pause
        exit 1
    }

} else {
    Write-Host "[步骤 1/2] package.json 已存在，跳过初始化" -ForegroundColor Gray
}

Write-Host ""
Write-Host "[步骤 2/2] 安装 animejs..." -ForegroundColor Cyan

Push-Location $projectPath

try {
    npm install animejs --save

    if ($LASTEXITCODE -ne 0) {
        throw "npm install animejs 执行失败"
    }

    Write-Host "   ✓ animejs 安装成功!" -ForegroundColor Green

} catch {
    Pop-Location
    Write-Host "[错误] $_" -ForegroundColor Red
    pause
    exit 1
}

Pop-Location

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "     安装完成!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

$pkgJson = Get-Content (Join-Path $projectPath "package.json") | ConvertFrom-Json

if ($pkgJson.dependencies.animejs) {
    Write-Host ""
    Write-Host "📦 animejs 版本: $($pkgJson.dependencies.animejs)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "使用方法:" -ForegroundColor Yellow
    Write-Host "  import { animate, stagger, timeline } from 'animejs';" -ForegroundColor White
    Write-Host ""
    Write-Host "  animate('.box', { x: 300, duration: 800 });" -ForegroundColor Gray
} else {
    Write-Host "[警告] 未在 package.json 中找到 animejs 依赖" -ForegroundColor Yellow
}

pause