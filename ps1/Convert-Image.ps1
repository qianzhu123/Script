param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$ImagePath,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$TargetFormat
)

$ErrorActionPreference = 'Stop'

function Write-Info([string]$Message) {
    Write-Host "[INFO]  $Message"
}

function Write-Ok([string]$Message) {
    Write-Host "[OK]    $Message"
}

function Write-Fail([string]$Message) {
    throw $Message
}

try {
    $ImagePath = $ImagePath.Trim('"', "'")
    $TargetFormat = $TargetFormat.Trim('"', "'").ToLowerInvariant()

    $allowed = @('jpg', 'jpeg', 'png', 'bmp', 'gif', 'tiff', 'ico')
    if ($allowed -notcontains $TargetFormat) {
        Write-Fail "Unsupported target format: $TargetFormat"
    }

    if (-not (Test-Path -LiteralPath $ImagePath -PathType Leaf)) {
        Write-Fail "Source file not found: $ImagePath"
    }

    $srcFull = (Resolve-Path -LiteralPath $ImagePath).Path
    $srcDir = [System.IO.Path]::GetDirectoryName($srcFull)
    $srcName = [System.IO.Path]::GetFileNameWithoutExtension($srcFull)
    $srcExt = [System.IO.Path]::GetExtension($srcFull).TrimStart('.').ToLowerInvariant()

    if ($srcExt -eq 'jpg') { $srcExt = 'jpeg' }
    if ($srcExt -eq $TargetFormat) {
        Write-Fail "Source is already that format. Choose a different format."
    }

    $extMap = @{
        jpg = '.jpg'
        jpeg = '.jpg'
        png = '.png'
        bmp = '.bmp'
        gif = '.gif'
        tiff = '.tiff'
        ico = '.ico'
    }

    $desktopDir = [Environment]::GetFolderPath('Desktop')
    $tempDir = Join-Path $desktopDir 'convert-image-temp'
    if (-not (Test-Path -LiteralPath $tempDir)) {
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    }

    Add-Type -AssemblyName System.Drawing -ErrorAction Stop

    $outPath = Join-Path $srcDir ($srcName + $extMap[$TargetFormat])
    $tempFile = Join-Path $tempDir ($srcName + $extMap[$TargetFormat])

    Write-Info "Source       : $srcFull"
    Write-Info "Output       : $outPath"
    Write-Info "Target format: $TargetFormat"

    $image = $null
    $graphics = $null
    try {
        $image = [System.Drawing.Image]::FromFile($srcFull)
        if ($TargetFormat -in @('jpg', 'jpeg', 'bmp')) {
            $bitmap = New-Object System.Drawing.Bitmap($image.Width, $image.Height)
            $bitmap.SetResolution($image.HorizontalResolution, $image.VerticalResolution)
            $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
            $graphics.Clear([System.Drawing.Color]::White)
            $graphics.DrawImage($image, 0, 0, $image.Width, $image.Height)
            $image.Dispose()
            $image = $bitmap
        }

        $format = switch ($TargetFormat) {
            'jpg' { [System.Drawing.Imaging.ImageFormat]::Jpeg }
            'jpeg' { [System.Drawing.Imaging.ImageFormat]::Jpeg }
            'png' { [System.Drawing.Imaging.ImageFormat]::Png }
            'bmp' { [System.Drawing.Imaging.ImageFormat]::Bmp }
            'gif' { [System.Drawing.Imaging.ImageFormat]::Gif }
            'tiff' { [System.Drawing.Imaging.ImageFormat]::Tiff }
            'ico' { [System.Drawing.Imaging.ImageFormat]::Icon }
        }

        $image.Save($tempFile, $format)
        if (Test-Path -LiteralPath $outPath) {
            Remove-Item -LiteralPath $outPath -Force
        }
        Move-Item -LiteralPath $tempFile -Destination $outPath -Force
        Write-Ok "Conversion complete: $outPath"
    }
    finally {
        if ($graphics) { $graphics.Dispose() }
        if ($image) { $image.Dispose() }
        if (Test-Path -LiteralPath $tempDir) {
            Get-ChildItem -LiteralPath $tempDir -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tempDir -Force -ErrorAction SilentlyContinue
        }
    }
}
catch {
    Write-Host "[ERROR] Conversion failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
