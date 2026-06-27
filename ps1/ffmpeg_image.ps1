$ErrorActionPreference = "Stop"

# FFmpeg 图片处理脚本
# 功能: 修改图片分辨率 / 清晰度(锐度) / 压缩质量
# 输出: 同目录下原文件名加 _replaced 后缀, 不覆盖原图

function Test-Ffmpeg {
    $cmd = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if (-not $cmd) {
        Write-Host "[错误] 未检测到 ffmpeg, 请先安装并加入 PATH 环境变量。" -ForegroundColor Red
        Write-Host "下载地址: https://ffmpeg.org/download.html" -ForegroundColor Yellow
        return $false
    }
    return $true
}

function Select-ImageFile {
    Add-Type -AssemblyName System.Windows.Forms | Out-Null
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "选择要处理的图片"
    $dialog.Filter = "图片文件|*.jpg;*.jpeg;*.png;*.bmp;*.webp;*.tif;*.tiff|所有文件|*.*"
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.FileName
    }
    return $null
}

function Get-OutputPath {
    param([string]$InputPath)
    $dir = [System.IO.Path]::GetDirectoryName($InputPath)
    $base = [System.IO.Path]::GetFileNameWithoutExtension($InputPath)
    $ext = [System.IO.Path]::GetExtension($InputPath)
    $out = Join-Path $dir ($base + "_replaced" + $ext)
    $i = 1
    while (Test-Path $out) {
        $out = Join-Path $dir ($base + "_replaced_" + $i + $ext)
        $i++
    }
    return $out
}

if (-not (Test-Ffmpeg)) { Read-Host "按回车退出"; exit 1 }

Write-Host "==== FFmpeg 图片处理 ====" -ForegroundColor Cyan
$input = Select-ImageFile
if (-not $input) {
    Write-Host "未选择文件, 已取消。" -ForegroundColor Yellow
    Read-Host "按回车退出"
    exit 0
}
Write-Host "已选择: $input" -ForegroundColor Green

Write-Host ""
Write-Host "请选择处理类型:" -ForegroundColor Cyan
Write-Host "  1. 修改分辨率 (缩放)"
Write-Host "  2. 增强清晰度 (锐化)"
Write-Host "  3. 调整压缩质量"
Write-Host "  4. 分辨率 + 锐化 + 质量 (组合)"
$choice = Read-Host "输入序号"

$vfParts = @()
$qArgs = @()

switch ($choice) {
    "1" {
        $w = Read-Host "目标宽度像素 (留空表示按高度等比, 例 1920)"
        $h = Read-Host "目标高度像素 (留空表示按宽度等比, 例 1080)"
        if (-not $w) { $w = "-1" }
        if (-not $h) { $h = "-1" }
        if ($w -eq "-1" -and $h -eq "-1") {
            Write-Host "[错误] 宽高不能同时为空。" -ForegroundColor Red
            Read-Host "按回车退出"; exit 1
        }
        $vfParts += "scale=${w}:${h}"
    }
    "2" {
        $amount = Read-Host "锐化强度 (0.5~3.0, 推荐 1.0, 留空默认 1.0)"
        if (-not $amount) { $amount = "1.0" }
        $vfParts += "unsharp=5:5:${amount}:5:5:0.0"
    }
    "3" {
        $q = Read-Host "质量值 (2=最好 ~ 31=最差, 推荐 2~6, 留空默认 3)"
        if (-not $q) { $q = "3" }
        $qArgs = @("-q:v", $q)
    }
    "4" {
        $w = Read-Host "目标宽度像素 (留空按高度等比)"
        $h = Read-Host "目标高度像素 (留空按宽度等比)"
        if (-not $w) { $w = "-1" }
        if (-not $h) { $h = "-1" }
        if (-not ($w -eq "-1" -and $h -eq "-1")) {
            $vfParts += "scale=${w}:${h}"
        }
        $amount = Read-Host "锐化强度 (留空默认 1.0)"
        if (-not $amount) { $amount = "1.0" }
        $vfParts += "unsharp=5:5:${amount}:5:5:0.0"
        $q = Read-Host "质量值 2~31 (留空默认 3)"
        if (-not $q) { $q = "3" }
        $qArgs = @("-q:v", $q)
    }
    default {
        Write-Host "无效选择, 已取消。" -ForegroundColor Yellow
        Read-Host "按回车退出"; exit 0
    }
}

$output = Get-OutputPath -InputPath $input

$ffArgs = @("-y", "-i", $input)
if ($vfParts.Count -gt 0) {
    $ffArgs += "-vf"
    $ffArgs += ($vfParts -join ",")
}
$ffArgs += $qArgs
$ffArgs += $output

Write-Host ""
Write-Host "执行命令:" -ForegroundColor Cyan
Write-Host ("ffmpeg " + ($ffArgs -join " ")) -ForegroundColor DarkGray
Write-Host ""

& ffmpeg @ffArgs

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "[完成] 已生成: $output" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "[失败] ffmpeg 返回码 $LASTEXITCODE" -ForegroundColor Red
}

Read-Host "按回车退出"
