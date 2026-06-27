param(
  [Parameter(Mandatory=$true)]
  [ValidatePattern('^[A-Za-z]$')]
  [string]$DriveLetter,

  [Parameter(Mandatory=$true)]
  [string]$ReportPath,

  [string]$TempDir = $env:DAILY_TEMP_DIR,

  [int]$TopCandidateCount = 200,

  [int]$TopDirectoryCount = 80,

  [int64]$LargeFileBytes = 500MB,

  [int]$TopLargeFileCount = 80
)

$ErrorActionPreference = 'Continue'
$scanStarted = Get-Date

if (-not $TempDir) {
  $TempDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'temp'
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ReportPath) | Out-Null
New-Item -ItemType Directory -Force -Path $TempDir | Out-Null

$driveLetterUpper = $DriveLetter.Substring(0,1).ToUpper()
$drive = "${driveLetterUpper}:"
$root = "$drive\"
$tempWork = Join-Path $TempDir ("scan-clean-{0}-{1:yyyyMMdd-HHmmss}" -f $driveLetterUpper, $scanStarted)
New-Item -ItemType Directory -Force -Path $tempWork | Out-Null

function Format-Size([double]$bytes) {
  if ($bytes -ge 1TB) { return ('{0:N2} TB' -f ($bytes / 1TB)) }
  if ($bytes -ge 1GB) { return ('{0:N2} GB' -f ($bytes / 1GB)) }
  if ($bytes -ge 1MB) { return ('{0:N2} MB' -f ($bytes / 1MB)) }
  if ($bytes -ge 1KB) { return ('{0:N2} KB' -f ($bytes / 1KB)) }
  return ('{0:N0} B' -f $bytes)
}

function Escape-Md([string]$text) {
  if ($null -eq $text) { return '' }
  return $text.Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ')
}

function Is-OnDrive([string]$path) {
  return ($path -and $path.Length -ge 2 -and $path.Substring(0,1).ToUpper() -eq $driveLetterUpper)
}

function Get-PathSize([string]$path) {
  $size = 0L
  $files = 0
  $errors = 0

  if (-not (Test-Path -LiteralPath $path)) {
    return [pscustomobject]@{ Path=$path; SizeBytes=0L; Files=0; Exists=$false; Errors=0 }
  }

  try {
    $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
    if (-not $item.PSIsContainer) {
      return [pscustomobject]@{ Path=$path; SizeBytes=[int64]$item.Length; Files=1; Exists=$true; Errors=0 }
    }
  } catch {
    return [pscustomobject]@{ Path=$path; SizeBytes=0L; Files=0; Exists=$true; Errors=1 }
  }

  try {
    Get-ChildItem -LiteralPath $path -Force -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
      $size += [int64]$_.Length
      $files++
    }
  } catch {
    $errors++
  }

  return [pscustomobject]@{ Path=$path; SizeBytes=$size; Files=$files; Exists=$true; Errors=$errors }
}

function Get-Category([string]$path) {
  $p = $path.ToLowerInvariant()

  if ($p -match '\$recycle\.bin') { return @{ Type='Recycle Bin contents'; Risk='Medium'; Note='Size only. This script never empties the Recycle Bin.' } }
  if ($p -match 'docker.*(wsl|data|vhdx|desktop)|\.docker') { return @{ Type='Docker Desktop data'; Risk='High'; Note='May contain images, containers, and settings. Prefer docker prune commands.' } }