$ErrorActionPreference = "Stop"

# FFmpeg image script
# : imageresolution / () / compressionquality
# Output: directoryfile _replaced, 

function Test-Ffmpeg {
 $cmd = Get-Command ffmpeg -ErrorAction SilentlyContinue
 if (-not $cmd) {
 Write-Host "[ERROR] check ffmpeg, installeradd it to PATH." -ForegroundColor Red
 Write-Host "download: https://ffmpeg.org/download.html" -ForegroundColor Yellow
 return $false
 }
 return $true
}

function Select-ImageFile {
 Add-Type -AssemblyName System.Windows.Forms | Out-Null
 $dialog = New-Object System.Windows.Forms.OpenFileDialog
 $dialog.Title = "select image"
 $dialog.Filter = "imagefile|*.jpg;*.jpeg;*.png;*.bmp;*.webp;*.tif;*.tiff| file|*.*"
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

if (-not (Test-Ffmpeg)) { Read-Host "press Enterexit"; exit 1 }

Write-Host "==== FFmpeg image ====" -ForegroundColor Cyan
$input = Select-ImageFile
if (-not $input) {
 Write-Host " selectfile, Cancelled.led." -ForegroundColor Yellow
 Read-Host "press Enterexit"
 exit 0
}
Write-Host " select: $input" -ForegroundColor Green

Write-Host ""
Write-Host "Select an actiontype:" -ForegroundColor Cyan
Write-Host " 1. resolution ()"
Write-Host " 2. (sharpen)"
Write-Host " 3. compressionquality"
Write-Host " 4. resolution + sharpen + quality ()"
$choice = Read-Host "Input "

$vfParts = @()
$qArgs = @()

switch ($choice) {
 "1" {
 $w = Read-Host " (leave blank, 1920)"
 $h = Read-Host " (leave blank, 1080)"
 if (-not $w) { $w = "-1" }
 if (-not $h) { $h = "-1" }
 if ($w -eq "-1" -and $h -eq "-1") {
 Write-Host "[ERROR]." -ForegroundColor Red
 Read-Host "press Enterexit"; exit 1
 }
 $vfParts += "scale=${w}:${h}"
 }
 "2" {
 $amount = Read-Host "sharpen (0.5~3.0, 1.0, leave blankdefault 1.0)"
 if (-not $amount) { $amount = "1.0" }
 $vfParts += "unsharp=5:5:${amount}:5:5:0.0"
 }
 "3" {
 $q = Read-Host "quality (2= ~ 31=, 2~6, leave blankdefault 3)"
 if (-not $q) { $q = "3" }
 $qArgs = @("-q:v", $q)
 }
 "4" {
 $w = Read-Host " (leave blank)"
 $h = Read-Host " (leave blank)"
 if (-not $w) { $w = "-1" }
 if (-not $h) { $h = "-1" }
 if (-not ($w -eq "-1" -and $h -eq "-1")) {
 $vfParts += "scale=${w}:${h}"
 }
 $amount = Read-Host "sharpen (leave blankdefault 1.0)"
 if (-not $amount) { $amount = "1.0" }
 $vfParts += "unsharp=5:5:${amount}:5:5:0.0"
 $q = Read-Host "quality 2~31 (leave blankdefault 3)"
 if (-not $q) { $q = "3" }
 $qArgs = @("-q:v", $q)
 }
 default {
 Write-Host "Invalidselect, Cancelled.led." -ForegroundColor Yellow
 Read-Host "press Enterexit"; exit 0
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
Write-Host "runcommand:" -ForegroundColor Cyan
Write-Host ("ffmpeg " + ($ffArgs -join " ")) -ForegroundColor DarkGray
Write-Host ""

& ffmpeg @ffArgs

if ($LASTEXITCODE -eq 0) {
 Write-Host ""
 Write-Host "[DONE] : $output" -ForegroundColor Green
} else {
 Write-Host ""
 Write-Host "[FAILED] ffmpeg $LASTEXITCODE" -ForegroundColor Red
}

Read-Host "press Enterexit"
