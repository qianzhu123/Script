param(
  [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z]$')][string]$DriveLetter,
  [Parameter(Mandatory=$true)][string]$ReportPath,
  [string]$TempDir = $env:DAILY_TEMP_DIR,
  [int]$TopN = 200,
  [int64]$LargeFileBytes = 500MB,
  [int]$TopLargeFiles = 80,
  [int]$TotalTimeoutSec = 300,
  [switch]$SkipFullDiskScan
)
$ErrorActionPreference = 'Continue'
$t0 = Get-Date
if (-not $TempDir) { $TempDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'temp' }
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ReportPath) | Out-Null
New-Item -ItemType Directory -Force -Path $TempDir | Out-Null
$drv = "$($DriveLetter.Substring(0,1).ToUpper()):"
$root = "$drv\"
$sw = [System.Diagnostics.Stopwatch]::StartNew()

function fmt($b) {
  if ($b -ge 1TB) { return '{0:N2} TB' -f ($b/1TB) }
  if ($b -ge 1GB) { return '{0:N2} GB' -f ($b/1GB) }
  if ($b -ge 1MB) { return '{0:N2} MB' -f ($b/1MB) }
  if ($b -ge 1KB) { return '{0:N2} KB' -f ($b/1KB) }
  return '{0:N0} B' -f $b
}
function esc($t) { if (!$t) {''} else {$t.Replace('|','\|').Replace("`r",' ').Replace("`n",' ')} }

# ── robocopy-based fast size ──
function Get-Size([string]$p) {
  if (-not (Test-Path $p)) { return @{Bytes=0L;Files=0;Ok=$false} }
  try { $it = Get-Item $p -Force -EA Stop; if (!$it.PSIsContainer) { return @{Bytes=[int64]$it.Length;Files=1;Ok=$true} } }
  catch { return @{Bytes=0L;Files=0;Ok=$false} }
  $tmp = New-TemporaryFile
  try {
    $null = & robocopy.exe "$p" "\\localhost\C$\__nonexistent__" /L /E /BYTES /NP /NFL /NDL /NJH /R:0 /W:0 /XJ *> $tmp
    $txt = Get-Content $tmp -Raw -EA SilentlyContinue
    $sz=0L; $fc=0
    if ($txt -match 'Bytes\s*:\s*([\d,]+)') { $sz = [int64]($Matches[1]-replace ',','') }
    if ($txt -match 'Files\s*:\s*([\d,]+)') { $fc = [int]($Matches[1]-replace ',','') }
    return @{Bytes=$sz;Files=$fc;Ok=$true}
  } catch { return @{Bytes=0L;Files=0;Ok=$false} }
  finally { Remove-Item $tmp -Force -EA SilentlyContinue }
}

# ── category ──
function catg([string]$p) {
  $q = $p.ToLowerInvariant()
  if ($q -match '\$recycle\.bin') { return @{T='Recycle Bin';R='Medium';N='Size only.'} }
  if ($q -match 'docker|\.docker') { return @{T='Docker data';R='High';N='Use docker prune.'} }
  if ($q -match '\\temp\\|\\tmp\\|\\cache\\|\.cache') { return @{T='Temp/Cache';R='Low';N='Usually safe.'} }
  if ($q -match '\.m2\\repository') { return @{T='Maven cache';R='Low';N='Rebuildable.'} }
  if ($q -match '\.gradle\\caches') { return @{T='Gradle cache';R='Low';N='Rebuildable.'} }
  if ($q -match 'node_modules|\.npm') { return @{T='Node.js cache';R='Low';N='npm install restores.'} }
  if ($q -match 'appdata\\local\\temp') { return @{T='User Temp';R='Low';N='Windows does not auto-clean.'} }
  if ($q -match 'windows\\temp') { return @{T='System Temp';R='Medium';N='Some files in use.'} }
  if ($q -match 'windows\\prefetch') { return @{T='Prefetch';R='Low';N='Safe periodically.'} }
  if ($q -match 'wechat|weixin|tencent|qq') { return @{T='IM cache';R='Medium';N='Chat history risk.'} }
  if ($q -match 'baidu|baidunetdisk') { return @{T='Baidu Netdisk';R='Low';N='Download cache.'} }
  return @{T='Other';R='Unknown';N=''}
}

Write-Host "`n=== C Drive Scanner v2 === Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===`n" -ForegroundColor Cyan

$cands = [System.Collections.Generic.List[pscustomobject]]@()
$errs  = [System.Collections.Generic.List[string]]@()

# Phase A: known paths
Write-Host "[Phase A] Known heavy paths..." -ForegroundColor Green
$known = @(
  "$env:SystemDrive\`$Recycle.Bin", "$env:LOCALAPPDATA\Temp", "$env:SystemRoot\Temp",
   "$env:SystemRoot\Prefetch", "$env:LOCALAPPDATA\Microsoft\Windows\INetCache",
   "$env:USERPROFILE\.m2\repository", "$env:USERPROFILE\.gradle\caches",
   "$env:USERPROFILE\.npm", "$env:USERPROFILE\.cache",
   "$env:LOCALAPPDATA\Docker", "$env:APPDATA\Docker",
   "$env:LOCALAPPDATA\pip\cache", "$env:APPDATA\pip\cache",
   "$env:USERPROFILE\.nuget\packages"
)
foreach ($p in $known) {
  if ($sw.Elapsed.TotalSeconds -gt $TotalTimeoutSec) { Write-Warning "TIMEOUT"; break }
  if (-not (Test-Path $p)) { continue }
 Write-Host "   Scanning: $p"`````````````````````````