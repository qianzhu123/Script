param(
  [Parameter(Mandatory=$true)]
  [ValidatePattern('^[A-Za-z]$')]
  [string]$DriveLetter,

  [Parameter(Mandatory=$true)]
  [string]$ReportPath,

  [string]$TempDir = $env:SCRIPT_STUDIO_TEMP_DIR,

  [switch]$FastMode
)

$ErrorActionPreference = 'Stop'

$script = Join-Path $PSScriptRoot 'Scan-CleanReport.ps1'
if (-not (Test-Path -LiteralPath $script)) {
  throw "Scan-CleanReport.ps1 was not found: $script"
}

& $script -DriveLetter $DriveLetter -ReportPath $ReportPath -TempDir $TempDir
