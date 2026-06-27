// 临时生成器 - 用完即删
const fs = require('fs');

const ps1 = `# ============================================================
# install-animejs.ps1
# 在指定项目中安装 anime.js 动画库
# ============================================================

Write-Host ''
Write-Host '========================================' -ForegroundColor Cyan
Write-Host '  Anime.js Installer' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Anime.js - JavaScript 动画引擎' -ForegroundColor Yellow
Write-Host '官网: https://animejs.com' -ForegroundColor DarkGray
Write-Host 'GitHub: https://github.com/juliangarnier/anime' -ForegroundColor DarkGray
Write-Host ''

# ── 获取项目路径 ──────────────────────────
do {
    $projectPath = Read-Host '请输入项目路径（文件夹路径）'
    $projectPath = $projectPath.Trim()
    if ([string]::IsNullOrWhiteSpace($projectPath)) {
        Write-Host '[错误] 路径不能为空，请重新输入' -ForegroundColor Red
        continue
    }
    # 去掉引号
    $projectPath = $projectPath.Trim('"').Trim("'")
    if (-not (Test-Path $projectPath -PathType Container)) {
        Write-Host "[错误] 目录不存在: $projectPath" -ForegroundColor Red
        continue
    }
    break
} while ($true)

Write-Host "目标项目: $projectPath" -ForegroundColor Green

# ── 检查 Node.js ──────────────────────────
$nodeVersion = $null
try { $nodeVersion = (node --version 2>$null) } catch {}
if (-not $nodeVersion) {
    Write-Host '[错误] 未检测到 Node.js，请先安装 Node.js' -ForegroundColor Red
    Write-Host '下载地址: https://nodejs.org/' -ForegroundColor DarkGray
    Read-Host '按 Enter 退出'
    exit 1
}
Write-Host "Node.js: $nodeVersion" -ForegroundColor Green

# ── npm version ───────────────────────────
$npmVersion = (npm --version 2>$null)
if ($npmVersion) {
    Write-Host "npm: v$npmVersion" -ForegroundColor Green
}

# ── cd + install ──────────────────────────
Set-Location $projectPath

if (-not (Test-Path 'package.json')) {
    Write-Host ''
    Write-Host '[提示] 当前目录没有 package.json' -ForegroundColor Yellow
    
    $confirm = Read-Host '是否执行 npm init -y 初始化项目? (Y/n)'
    if ($confirm -eq 'n' -or $confirm -eq 'N') {
        Write-Host '已取消。需要 package.json 才能安装依赖。' -ForegroundColor Gray
        Read-Host '按 Enter 退出'
        exit 0
    }
    
    Write-Host '正在初始化...'
    npm init -y
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host '[错误] npm init 失败，请检查 npm 配置' -ForegroundColor Red
        Read-Host '按 Enter 退出'
        exit 1
    }
    
    Write-Host '[OK] package.json created' -ForegroundColor Green
    
} else {
    
}

Write-Host ''
Write-Host 'Installing animejs...' -ForegroundColor Cyan

npm install animejs

if ($LASTEXITCODE -ne 0) {
    
}

Write-Host ''
Write-Host '========================================' -ForegroundColor Green
    
    
    
    

Read-Host`;

fs.writeFileSync('D:/code/myweb/daily/ps1/install-animejs.ps1', ps1, 'utf8');
console.log('PS1 written OK');