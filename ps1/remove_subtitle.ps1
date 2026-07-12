param(
    [Alias("Path")]
    [string]$VideoPath,

    [ValidateSet("1", "2", "3")]
    [string]$Mode,

    [string]$SubLang,

    [int]$CropTop = -1,
    [int]$CropBottom = -1,
    [int]$CropLeft = -1,
    [int]$CropRight = -1,

    [int]$DelogoX = -1,
    [int]$DelogoY = -1,
    [int]$DelogoW = -1,
    [int]$DelogoH = -1
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Title {
    Write-Host ""
    Write-Host "Remove Subtitle Tool" -ForegroundColor Cyan
    Write-Host "=====================" -ForegroundColor Cyan
}

function Read-RequiredValue {
    param(
        [string]$PromptText
    )

    while ($true) {
        $value = Read-Host $PromptText
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value.Trim().Trim('"')
        }
        Write-Host "Value cannot be empty." -ForegroundColor Yellow
    }
}

function Test-CommandExists {
    param(
        [string]$CommandName
    )

    return [bool](Get-Command $CommandName -ErrorAction SilentlyContinue)
}

function Read-PositiveInt {
    param(
        [string]$PromptText,
        [int]$PresetValue
    )

    if ($PresetValue -ge 0) {
        return $PresetValue
    }

    while ($true) {
        $rawValue = Read-RequiredValue $PromptText
        $parsedValue = 0
        if ([int]::TryParse($rawValue, [ref]$parsedValue) -and $parsedValue -ge 0) {
            return $parsedValue
        }
        Write-Host "Please enter a non-negative integer." -ForegroundColor Yellow
    }
}

function Get-SubtitleStreams {
    param(
        [string]$InputPath
    )

    if (-not (Test-CommandExists "ffprobe")) {
        throw "ffprobe was not found. It is usually installed with ffmpeg. Please add ffprobe to PATH."
    }

    $jsonOutput = & ffprobe -v error -select_streams s -show_entries stream=index:stream_tags=language,title -of json -- $InputPath
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($jsonOutput)) {
        return @()
    }

    $probeData = $jsonOutput | ConvertFrom-Json
    $streams = @()

    if ($null -ne $probeData.streams) {
        foreach ($stream in $probeData.streams) {
            if ($null -eq $stream) { continue }
            $entry = @{
                Index    = $stream.index
                Language = if ($null -ne $stream.tags -and $null -ne $stream.tags.language) { $stream.tags.language } else { "unknown" }
                Title    = if ($null -ne $stream.tags -and $null -ne $stream.tags.title) { $stream.tags.title } else { "" }
            }
            $streams += $entry
        }
    }

    return $streams
}

function Get-OutputPath {
    param(
        [string]$InputPath,
        [string]$Suffix
    )

    $directory = Split-Path -Parent $InputPath
    $baseName = [IO.Path]::GetFileNameWithoutExtension($InputPath)
    $extension = [IO.Path]::GetExtension($InputPath)
    $safeSuffix = ($Suffix -replace '[^a-zA-Z0-9._-]', '_')
    $candidate = Join-Path $directory "$baseName`_$safeSuffix$extension"
    $index = 1

    while (Test-Path -LiteralPath $candidate) {
        $candidate = Join-Path $directory "$baseName`_$safeSuffix`_$index$extension"
        $index++
    }

    return $candidate
}

function Get-VideoResolution {
    param(
        [string]$InputPath
    )

    $widthText = & ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 -- $InputPath
    $heightText = & ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 -- $InputPath

    $width = 0
    $height = 0
    if ([string]::IsNullOrWhiteSpace($widthText) -or [string]::IsNullOrWhiteSpace($heightText)) {
        throw "Could not read the video resolution from ffprobe."
    }
    if (-not [int]::TryParse($widthText.Trim(), [ref]$width) -or -not [int]::TryParse($heightText.Trim(), [ref]$height)) {
        throw "Could not parse the video resolution."
    }

    return @{
        Width  = $width
        Height = $height
    }
}

function Get-DefaultDelogoRegion {
    param(
        [hashtable]$Resolution
    )

    $w = $Resolution.Width
    $h = $Resolution.Height

    $marginX = [Math]::Max(20, [int]($w * 0.05))
    $delogoH = [Math]::Max(40, [int]($h * 0.1))
    $delogoY = $h - $delogoH - [int]($delogoH * 0.3)
    if (($delogoY + $delogoH) -gt $h) {
        $delogoY = $h - $delogoH
    }
    if ($delogoY -lt 0) { $delogoY = 0 }

    $delogoX = $marginX
    $delogoW = [Math]::Max(100, $w - ($marginX * 2))

    return @{
        X = $delogoX
        Y = $delogoY
        W = $delogoW
        H = $delogoH
    }
}

function Invoke-RemoveSoftSubtitles {
    param(
        [string]$InputPath,
        [string]$OutputPath,
        [string]$LanguageFilter
    )

    $subtitleStreams = @(Get-SubtitleStreams $InputPath)

    if ($subtitleStreams.Count -eq 0) {
        Write-Host "No subtitle streams found in the video." -ForegroundColor Yellow
        return $false
    }

    Write-Host ""
    Write-Host "Found subtitle streams:" -ForegroundColor Cyan
    foreach ($s in $subtitleStreams) {
        Write-Host ("  Stream #{0}: lang={1}, title={2}" -f $s.Index, $s.Language, $s.Title)
    }

    $arguments = New-Object System.Collections.Generic.List[string]
    $arguments.Add("-hide_banner")
    $arguments.Add("-y")
    $arguments.Add("-i")
    $arguments.Add($InputPath)

    if (-not [string]::IsNullOrWhiteSpace($LanguageFilter)) {
        $removeIndexes = @()
        foreach ($s in $subtitleStreams) {
            if ($s.Language -eq $LanguageFilter) {
                $removeIndexes += $s.Index
            }
        }

        if ($removeIndexes.Count -eq 0) {
            Write-Host "No subtitle streams found with language code '$LanguageFilter'." -ForegroundColor Yellow
            return $false
        }

        Write-Host ("Removing {0} subtitle stream(s) with language '{1}'." -f $removeIndexes.Count, $LanguageFilter) -ForegroundColor Cyan

        $arguments.Add("-map")
        $arguments.Add("0")
        foreach ($idx in $removeIndexes) {
            $arguments.Add("-map")
            $arguments.Add("-0:s:$idx")
        }
    }
    else {
        Write-Host "Removing ALL subtitle streams." -ForegroundColor Cyan
        $arguments.Add("-map")
        $arguments.Add("0:v")
        $arguments.Add("-map")
        $arguments.Add("0:a")
    }

    $arguments.Add("-c")
    $arguments.Add("copy")
    $arguments.Add($OutputPath)

    Write-Host ""
    Write-Host "Running ffmpeg..." -ForegroundColor Cyan
    & ffmpeg @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "ffmpeg failed with exit code $LASTEXITCODE."
    }

    return $true
}

function Invoke-CropSubtitle {
    param(
        [string]$InputPath,
        [string]$OutputPath,
        [int]$CropTopPx,
        [int]$CropBottomPx,
        [int]$CropLeftPx,
        [int]$CropRightPx
    )

    $res = Get-VideoResolution $InputPath
    $newWidth = $res.Width - $CropLeftPx - $CropRightPx
    $newHeight = $res.Height - $CropTopPx - $CropBottomPx

    if ($newWidth -le 0 -or $newHeight -le 0) {
        throw "Crop values result in zero or negative resolution."
    }

    if (($newWidth % 2) -ne 0) { $newWidth-- }
    if (($newHeight % 2) -ne 0) { $newHeight-- }

    Write-Host ""
    Write-Host ("Original resolution: {0}x{1}" -f $res.Width, $res.Height) -ForegroundColor Cyan
    Write-Host ("Output resolution:   {0}x{1}" -f $newWidth, $newHeight) -ForegroundColor Cyan

    $filter = "crop={0}:{1}:{2}:{3}" -f $newWidth, $newHeight, $CropLeftPx, $CropTopPx

    $arguments = New-Object System.Collections.Generic.List[string]
    $arguments.Add("-hide_banner")
    $arguments.Add("-y")
    $arguments.Add("-i")
    $arguments.Add($InputPath)
    $arguments.Add("-vf")
    $arguments.Add($filter)
    $arguments.Add("-c:a")
    $arguments.Add("copy")
    $arguments.Add("-movflags")
    $arguments.Add("+faststart")
    $arguments.Add($OutputPath)

    Write-Host ""
    Write-Host "Running ffmpeg..." -ForegroundColor Cyan
    & ffmpeg @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "ffmpeg failed with exit code $LASTEXITCODE."
    }

    return $true
}

function Invoke-DelogoSubtitle {
    param(
        [string]$InputPath,
        [string]$OutputPath,
        [int]$X,
        [int]$Y,
        [int]$W,
        [int]$H
    )

    if ($W -le 0 -or $H -le 0) {
        throw "Delogo width and height must be greater than zero."
    }

    Write-Host ""
    Write-Host ("Delogo region: x={0}, y={1}, w={2}, h={3}" -f $X, $Y, $W, $H) -ForegroundColor Cyan

    $filter = "delogo=x={0}:y={1}:w={2}:h={3}" -f $X, $Y, $W, $H

    $arguments = New-Object System.Collections.Generic.List[string]
    $arguments.Add("-hide_banner")
    $arguments.Add("-y")
    $arguments.Add("-i")
    $arguments.Add($InputPath)
    $arguments.Add("-vf")
    $arguments.Add($filter)
    $arguments.Add("-c:a")
    $arguments.Add("copy")
    $arguments.Add("-movflags")
    $arguments.Add("+faststart")
    $arguments.Add($OutputPath)

    Write-Host ""
    Write-Host "Running ffmpeg..." -ForegroundColor Cyan
    & ffmpeg @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "ffmpeg failed with exit code $LASTEXITCODE."
    }

    return $true
}

function Read-MenuChoice {
    param(
        [string]$PresetMode
    )

    if (-not [string]::IsNullOrWhiteSpace($PresetMode)) {
        return $PresetMode
    }

    Write-Host ""
    Write-Host "Choose a removal mode:"
    Write-Host "1. Remove soft/embedded subtitle streams (no re-encode)"
    Write-Host "2. Crop video to cut off hardcoded subtitle area"
    Write-Host "3. Blur/cover hardcoded subtitle area (delogo filter)"
    Write-Host ""

    while ($true) {
        $choice = Read-RequiredValue "Enter 1, 2, or 3"
        if ($choice -in @("1", "2", "3")) {
            return $choice
        }
        Write-Host "Invalid choice." -ForegroundColor Yellow
    }
}

try {
    Write-Title

    if (-not (Test-CommandExists "ffmpeg")) {
        throw "ffmpeg was not found in PATH."
    }

    $inputPath = $VideoPath
    if ([string]::IsNullOrWhiteSpace($inputPath)) {
        $inputPath = Read-RequiredValue "Enter the video file path"
    }
    else {
        $inputPath = $inputPath.Trim().Trim('"')
    }

    if (-not (Test-Path -LiteralPath $inputPath -PathType Leaf)) {
        throw "Input file does not exist: $inputPath"
    }
    $inputPath = (Resolve-Path -LiteralPath $inputPath).Path

    $choice = Read-MenuChoice -PresetMode $Mode
    $outputPath = $null

    switch ($choice) {
        "1" {
            $outputPath = Get-OutputPath -InputPath $inputPath -Suffix "no_sub"
            $success = Invoke-RemoveSoftSubtitles -InputPath $inputPath -OutputPath $outputPath -LanguageFilter $SubLang

            if (-not $success) {
                Write-Host ""
                Write-Host "Falling back to delogo for hardcoded subtitles..." -ForegroundColor Cyan
                $res = Get-VideoResolution $inputPath
                Write-Host ("Video resolution: {0}x{1}" -f $res.Width, $res.Height) -ForegroundColor Cyan

                $delogoX = $DelogoX
                $delogoY = $DelogoY
                $delogoW = $DelogoW
                $delogoH = $DelogoH

                if ($delogoX -lt 0 -or $delogoY -lt 0 -or $delogoW -le 0 -or $delogoH -le 0) {
                    $default = Get-DefaultDelogoRegion $res
                    $delogoX = $default.X
                    $delogoY = $default.Y
                    $delogoW = $default.W
                    $delogoH = $default.H
                    Write-Host ("Using auto-detected region: x={0}, y={1}, w={2}, h={3}" -f $delogoX, $delogoY, $delogoW, $delogoH) -ForegroundColor Cyan
                }

                $outputPath = Get-OutputPath -InputPath $inputPath -Suffix "delogo"
                Invoke-DelogoSubtitle -InputPath $inputPath -OutputPath $outputPath -X $delogoX -Y $delogoY -W $delogoW -H $delogoH
                Write-Host ""
                Write-Host "Delogo fallback completed." -ForegroundColor Green
            }
            else {
                Write-Host ""
                Write-Host "Soft subtitle removal completed." -ForegroundColor Green
            }
        }
        "2" {
            $res = Get-VideoResolution $inputPath
            Write-Host ("Video resolution: {0}x{1}" -f $res.Width, $res.Height) -ForegroundColor Cyan

            $cropTop = Read-PositiveInt -PromptText "Crop pixels from TOP (0)" -PresetValue $CropTop
            $cropBottom = Read-PositiveInt -PromptText "Crop pixels from BOTTOM (e.g. 80)" -PresetValue $CropBottom
            $cropLeft = Read-PositiveInt -PromptText "Crop pixels from LEFT (0)" -PresetValue $CropLeft
            $cropRight = Read-PositiveInt -PromptText "Crop pixels from RIGHT (0)" -PresetValue $CropRight

            if ($cropTop -eq 0 -and $cropBottom -eq 0 -and $cropLeft -eq 0 -and $cropRight -eq 0) {
                throw "At least one crop value must be greater than zero."
            }

            $outputPath = Get-OutputPath -InputPath $inputPath -Suffix "cropped"
            Invoke-CropSubtitle -InputPath $inputPath -OutputPath $outputPath -CropTopPx $cropTop -CropBottomPx $cropBottom -CropLeftPx $cropLeft -CropRightPx $cropRight
            Write-Host ""
            Write-Host "Crop subtitle removal completed." -ForegroundColor Green
        }
        "3" {
            $res = Get-VideoResolution $inputPath
            Write-Host ("Video resolution: {0}x{1}" -f $res.Width, $res.Height) -ForegroundColor Cyan

            $delogoX = $DelogoX
            $delogoY = $DelogoY
            $delogoW = $DelogoW
            $delogoH = $DelogoH

            if ($delogoX -ge 0 -and $delogoY -ge 0 -and $delogoW -gt 0 -and $delogoH -gt 0) {
                Write-Host ("Using provided region: x={0}, y={1}, w={2}, h={3}" -f $delogoX, $delogoY, $delogoW, $delogoH) -ForegroundColor Cyan
            }
            else {
                $default = Get-DefaultDelogoRegion $res
                Write-Host ("Suggested region: x={0}, y={1}, w={2}, h={3}" -f $default.X, $default.Y, $default.W, $default.H) -ForegroundColor Cyan
                Write-Host "Press Enter to accept, or type custom values." -ForegroundColor Cyan

                $delogoX = Read-PositiveInt -PromptText "X position of subtitle area" -PresetValue $default.X
                $delogoY = Read-PositiveInt -PromptText "Y position of subtitle area" -PresetValue $default.Y
                $delogoW = Read-PositiveInt -PromptText "Width of subtitle area" -PresetValue $default.W
                $delogoH = Read-PositiveInt -PromptText "Height of subtitle area" -PresetValue $default.H
            }

            $outputPath = Get-OutputPath -InputPath $inputPath -Suffix "delogo"
            Invoke-DelogoSubtitle -InputPath $inputPath -OutputPath $outputPath -X $delogoX -Y $delogoY -W $delogoW -H $delogoH
            Write-Host ""
            Write-Host "Delogo subtitle removal completed." -ForegroundColor Green
        }
    }

    if ($null -ne $outputPath -and (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
        Write-Host ""
        Write-Host "Completed successfully." -ForegroundColor Green
        Write-Host "Output file: $outputPath" -ForegroundColor Green
    }
    elseif ($null -eq $outputPath) {
        Write-Host ""
        Write-Host "No output was produced." -ForegroundColor Yellow
    }
}
catch {
    Write-Host ""
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
