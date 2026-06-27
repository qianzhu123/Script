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

$driveLetterUpper = $DriveLetter.Substring(0, 1).ToUpper()
$drive = "${driveLetterUpper}:"
$root = "$drive\"
$user = $env:USERPROFILE

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
  return ($path -and $path.Length -ge 2 -and $path.Substring(0, 1).ToUpper() -eq $driveLetterUpper)
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

  if ($p -match '\$recycle\.bin') { return @{ Type='Recycle Bin'; Risk='Medium'; Note='Size only. This report does not empty it.' } }
  if ($p -match 'docker|\.docker') { return @{ Type='Docker data'; Risk='High'; Note='Use docker prune commands instead of manual deletion.' } }
  if ($p -match '\\temp\\|\\tmp\\|\\cache\\|\.cache') { return @{ Type='Temp or cache'; Risk='Low'; Note='Usually rebuildable after closing related apps.' } }
  if ($p -match 'node_modules|\.npm|npm-cache') { return @{ Type='Node.js cache or deps'; Risk='Low'; Note='Can usually be restored with npm install.' } }
  if ($p -match '\.m2\\repository') { return @{ Type='Maven cache'; Risk='Low'; Note='Builds may download dependencies again.' } }
  if ($p -match '\.gradle\\caches') { return @{ Type='Gradle cache'; Risk='Low'; Note='Builds may rebuild indexes.' } }
  if ($p -match 'windows\\softwaredistribution\\download') { return @{ Type='Windows Update cache'; Risk='Medium'; Note='Windows Update may download files again.' } }
  if ($p -match 'windows\\prefetch') { return @{ Type='Prefetch cache'; Risk='Low'; Note='Windows rebuilds it automatically.' } }

  return @{ Type='Other'; Risk='Unknown'; Note='Review manually before deleting anything.' }
}

function Add-Candidate([System.Collections.Generic.List[object]]$list, [string]$path) {
  if (-not $path) { return }
  if (-not (Is-OnDrive $path)) { return }

  $size = Get-PathSize $path
  if (-not $size.Exists -or $size.SizeBytes -le 0) { return }

  $category = Get-Category $path
  $list.Add([pscustomobject]@{
    Path=$path
    SizeBytes=$size.SizeBytes
    Size=(Format-Size $size.SizeBytes)
    Files=$size.Files
    Errors=$size.Errors
    Type=$category.Type
    Risk=$category.Risk
    Note=$category.Note
  }) | Out-Null
}

Write-Host "Scanning drive $drive..."

$candidates = [System.Collections.Generic.List[object]]::new()
$knownPaths = @(
  "$drive\`$Recycle.Bin",
  "$drive\Windows\Temp",
  "$drive\Windows\Prefetch",
  "$drive\Windows\SoftwareDistribution\Download",
  (Join-Path $user 'AppData\Local\Temp'),
  (Join-Path $user 'AppData\Local\Microsoft\Windows\INetCache'),
  (Join-Path $user 'AppData\Local\Google\Chrome\User Data\Default\Cache'),
  (Join-Path $user 'AppData\Local\Microsoft\Edge\User Data\Default\Cache'),
  (Join-Path $user 'AppData\Local\npm-cache'),
  (Join-Path $user '.npm'),
  (Join-Path $user '.cache'),
  (Join-Path $user '.m2\repository'),
  (Join-Path $user '.gradle\caches'),
  (Join-Path $user '.nuget\packages'),
  (Join-Path $user 'AppData\Local\Docker'),
  (Join-Path $user 'AppData\Roaming\Docker')
)

foreach ($path in $knownPaths) {
  Add-Candidate $candidates $path
}

$topDirectories = @()
if (Test-Path -LiteralPath $root) {
  Get-ChildItem -LiteralPath $root -Force -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $size = Get-PathSize $_.FullName
    if ($size.Exists -and $size.SizeBytes -gt 0) {
      $topDirectories += [pscustomobject]@{
        Path=$_.FullName
        SizeBytes=$size.SizeBytes
        Size=(Format-Size $size.SizeBytes)
        Files=$size.Files
      }
    }
  }
}

$largeFiles = @()
foreach ($scanRoot in @($user, (Join-Path $drive 'ProgramData'))) {
  if (Test-Path -LiteralPath $scanRoot) {
    $largeFiles += Get-ChildItem -LiteralPath $scanRoot -Force -Recurse -File -ErrorAction SilentlyContinue |
      Where-Object { $_.Length -ge $LargeFileBytes -and (Is-OnDrive $_.FullName) } |
      Sort-Object Length -Descending |
      Select-Object -First $TopLargeFileCount FullName, Length
  }
}

$candidates = $candidates | Sort-Object SizeBytes -Descending | Select-Object -First $TopCandidateCount
$topDirectories = $topDirectories | Sort-Object SizeBytes -Descending | Select-Object -First $TopDirectoryCount
$largeFiles = $largeFiles | Sort-Object Length -Descending | Select-Object -First $TopLargeFileCount
$totalCandidateBytes = ($candidates | Measure-Object SizeBytes -Sum).Sum
$driveInfo = Get-PSDrive -Name $driveLetterUpper -ErrorAction SilentlyContinue

$md = [System.Text.StringBuilder]::new()
[void]$md.AppendLine("# Disk scan report for $drive")
[void]$md.AppendLine('')
[void]$md.AppendLine("Generated: $($scanStarted.ToString('yyyy-MM-dd HH:mm:ss'))")
[void]$md.AppendLine("Report mode: scan only. No files were deleted.")
if ($driveInfo) {
  [void]$md.AppendLine("Free space: $(Format-Size $driveInfo.Free)")
  [void]$md.AppendLine("Used space: $(Format-Size $driveInfo.Used)")
}
[void]$md.AppendLine("Candidate total: $(Format-Size $totalCandidateBytes)")
[void]$md.AppendLine('')
[void]$md.AppendLine('## Cleanup candidates')
[void]$md.AppendLine('')
[void]$md.AppendLine('| Rank | Size | Files | Risk | Type | Path | Note |')
[void]$md.AppendLine('|---:|---:|---:|---|---|---|---|')
$rank = 1
foreach ($item in $candidates) {
  [void]$md.AppendLine(('| {0} | {1} | {2} | {3} | {4} | `{5}` | {6} |' -f $rank, $item.Size, $item.Files, $item.Risk, (Escape-Md $item.Type), (Escape-Md $item.Path), (Escape-Md $item.Note)))
  $rank++
}

[void]$md.AppendLine('')
[void]$md.AppendLine('## Large files')
[void]$md.AppendLine('')
[void]$md.AppendLine('| Rank | Size | Path | Recommendation |')
[void]$md.AppendLine('|---:|---:|---|---|')
$rank = 1
foreach ($file in $largeFiles) {
  [void]$md.AppendLine(('| {0} | {1} | `{2}` | Review manually before moving or deleting. |' -f $rank, (Format-Size $file.Length), (Escape-Md $file.FullName)))
  $rank++
}

[void]$md.AppendLine('')
[void]$md.AppendLine('## Top directories')
[void]$md.AppendLine('')
[void]$md.AppendLine('| Rank | Size | Files | Path | Note |')
[void]$md.AppendLine('|---:|---:|---:|---|---|')
$rank = 1
foreach ($dir in $topDirectories) {
  [void]$md.AppendLine(('| {0} | {1} | {2} | `{3}` | Review manually. System and app folders may contain required files. |' -f $rank, $dir.Size, $dir.Files, (Escape-Md $dir.Path)))
  $rank++
}

[void]$md.AppendLine('')
[void]$md.AppendLine('## Safe cleanup notes')
[void]$md.AppendLine('')
[void]$md.AppendLine('- Prefer Windows Settings > System > Storage > Temporary files for system cleanup.')
[void]$md.AppendLine('- Prefer package-manager cleanup commands for npm, Maven, Gradle, NuGet, Docker, and browser caches.')
[void]$md.AppendLine('- Do not delete backup folders, personal files, virtual disks, or unknown project folders from this report automatically.')

Set-Content -LiteralPath $ReportPath -Value $md.ToString() -Encoding UTF8
Write-Host "Report: $ReportPath"
Write-Host "Candidates: $($candidates.Count)"
Write-Host "Candidate total: $(Format-Size $totalCandidateBytes)"
