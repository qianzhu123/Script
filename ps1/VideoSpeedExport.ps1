param(
    [Alias("Path")]
    [string]$VideoPath,

    [ValidateSet("1", "2", "3", "4")]
    [string]$Mode,

    [object]$Speed,
    [string]$TargetDuration,
    [string]$StartTime,
    [string]$EndTime
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Title {
    Write-Host ""
    Write-Host "Video Speed Export Tool" -ForegroundColor Cyan
    Write-Host "=======================" -ForegroundColor Cyan
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

function Read-PositiveDouble {
    param(
        [string]$PromptText,
        [object]$PresetValue
    )

    if ($null -ne $PresetValue) {
        $numericValue = [double]$PresetValue
        if ($numericValue -gt 0) {
            return $numericValue
        }
        throw "Speed must be greater than zero."
    }

    while ($true) {
        $rawValue = Read-RequiredValue $PromptText
        $parsedValue = 0.0
        if ([double]::TryParse($rawValue, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$parsedValue) -and $parsedValue -gt 0) {
            return $parsedValue
        }
        Write-Host "Please enter a positive number, for example 1.5 or 2." -ForegroundColor Yellow
    }
}

function Convert-TimeInputToSeconds {
    param(
        [string]$Value
    )

    $trimmedValue = $Value.Trim()
    $secondsValue = 0.0
    if ([double]::TryParse($trimmedValue, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$secondsValue)) {
        if ($secondsValue -lt 0) {
            throw "Time cannot be negative."
        }
        return $secondsValue
    }

    $parts = $trimmedValue -split ":"
    if ($parts.Count -lt 2 -or $parts.Count -gt 3) {
        throw "Use seconds, MM:SS, or HH:MM:SS."
    }

    $totalSeconds = 0.0
    foreach ($part in $parts) {
        $number = 0.0
        if (-not [double]::TryParse($part, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
            throw "Invalid time value."
        }
        if ($number -lt 0) {
            throw "Time cannot be negative."
        }
        $totalSeconds = ($totalSeconds * 60) + $number
    }

    return $totalSeconds
}

function Read-TimeSeconds {
    param(
        [string]$PromptText,
        [string]$PresetValue
    )

    if (-not [string]::IsNullOrWhiteSpace($PresetValue)) {
        return Convert-TimeInputToSeconds $PresetValue
    }

    while ($true) {
        $rawValue = Read-RequiredValue $PromptText

        try {
            return Convert-TimeInputToSeconds $rawValue
        }
        catch {
            Write-Host $_.Exception.Message -ForegroundColor Yellow
        }
    }
}

function Get-MediaDurationSeconds {
    param(
        [string]$InputPath
    )

    if (-not (Test-CommandExists "ffprobe")) {
        throw "ffprobe was not found. It is usually installed with ffmpeg. Please add ffprobe to PATH."
    }

    $durationText = & ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 -- $InputPath
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($durationText)) {
        throw "Could not read the media duration with ffprobe."
    }

    $duration = 0.0
    if (-not [double]::TryParse($durationText.Trim(), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$duration) -or $duration -le 0) {
        throw "Invalid media duration returned by ffprobe."
    }

    return $duration
}

function Test-HasAudioStream {
    param(
        [string]$InputPath
    )

    if (-not (Test-CommandExists "ffprobe")) {
        return $true
    }

    $streamText = & ffprobe -v error -select_streams a:0 -show_entries stream=index -of csv=p=0 -- $InputPath
    return ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($streamText))
}

function Get-SafeToken {
    param(
        [string]$Value
    )

    return ($Value -replace '[^a-zA-Z0-9._-]', '_')
}

function Get-OutputPath {
    param(
        [string]$InputPath,
        [string]$Suffix
    )

    $directory = Split-Path -Parent $InputPath
    $baseName = [IO.Path]::GetFileNameWithoutExtension($InputPath)
    $extension = [IO.Path]::GetExtension($InputPath)
    $safeSuffix = Get-SafeToken $Suffix
    $candidate = Join-Path $directory "$baseName`_$safeSuffix$extension"
    $index = 1

    while (Test-Path -LiteralPath $candidate) {
        $candidate = Join-Path $directory "$baseName`_$safeSuffix`_$index$extension"
        $index++
    }

    return $candidate
}

function Get-AtempoFilter {
    param(
        [double]$PlaybackSpeed
    )

    $filters = New-Object System.Collections.Generic.List[string]
    $remainingSpeed = $PlaybackSpeed

    while ($remainingSpeed -gt 2.0) {
        $filters.Add("atempo=2.0")
        $remainingSpeed = $remainingSpeed / 2.0
    }

    while ($remainingSpeed -lt 0.5) {
        $filters.Add("atempo=0.5")
        $remainingSpeed = $remainingSpeed / 0.5
    }

    $filters.Add(("atempo={0}" -f $remainingSpeed.ToString("0.######", [Globalization.CultureInfo]::InvariantCulture)))
    return ($filters -join ",")
}

function Invoke-FfmpegExport {
    param(
        [string]$InputPath,
        [string]$OutputPath,
        [object]$StartSeconds,
        [object]$EndSeconds,
        [object]$PlaybackSpeed
    )

    $arguments = New-Object System.Collections.Generic.List[string]
    $arguments.Add("-hide_banner")
    $arguments.Add("-y")

    if ($null -ne $StartSeconds) {
        $arguments.Add("-ss")
        $arguments.Add(([double]$StartSeconds).ToString("0.###", [Globalization.CultureInfo]::InvariantCulture))
    }

    $arguments.Add("-i")
    $arguments.Add($InputPath)

    if ($null -ne $EndSeconds) {
        $duration = [double]$EndSeconds
        if ($null -ne $StartSeconds) {
            $duration = [double]$EndSeconds - [double]$StartSeconds
        }
        if ($duration -le 0) {
            throw "End time must be greater than start time."
        }
        $arguments.Add("-t")
        $arguments.Add($duration.ToString("0.###", [Globalization.CultureInfo]::InvariantCulture))
    }

    if ($null -ne $PlaybackSpeed -and [Math]::Abs(([double]$PlaybackSpeed) - 1.0) -gt 0.000001) {
        $speedValue = [double]$PlaybackSpeed
        $speedText = $speedValue.ToString("0.######", [Globalization.CultureInfo]::InvariantCulture)
        $videoFilter = "setpts=PTS/$speedText"

        if (Test-HasAudioStream $InputPath) {
            $audioFilter = Get-AtempoFilter $speedValue
            $arguments.Add("-filter_complex")
            $arguments.Add("[0:v]$videoFilter[v];[0:a]$audioFilter[a]")
            $arguments.Add("-map")
            $arguments.Add("[v]")
            $arguments.Add("-map")
            $arguments.Add("[a]")
        }
        else {
            $arguments.Add("-filter:v")
            $arguments.Add($videoFilter)
            $arguments.Add("-an")
        }
    }

    $arguments.Add("-movflags")
    $arguments.Add("+faststart")
    $arguments.Add($OutputPath)

    Write-Host ""
    Write-Host "Running ffmpeg..." -ForegroundColor Cyan
    & ffmpeg @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "ffmpeg failed with exit code $LASTEXITCODE."
    }
}

function Read-MenuChoice {
    param(
        [string]$PresetMode
    )

    if (-not [string]::IsNullOrWhiteSpace($PresetMode)) {
        return $PresetMode
    }

    Write-Host ""
    Write-Host "Choose an export mode:"
    Write-Host "1. Export by speed multiplier"
    Write-Host "2. Export by target output duration"
    Write-Host "3. Export selected time range"
    Write-Host "4. Export selected time range by speed multiplier"
    Write-Host ""

    while ($true) {
        $choice = Read-RequiredValue "Enter 1, 2, 3, or 4"
        if ($choice -in @("1", "2", "3", "4")) {
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
    $startSeconds = $null
    $endSeconds = $null
    $playbackSpeed = $null
    $suffix = "export"

    switch ($choice) {
        "1" {
            $playbackSpeed = Read-PositiveDouble -PromptText "Enter speed multiplier, for example 2 for 2x" -PresetValue $Speed
            $suffix = "speed_$($playbackSpeed.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture))x"
        }
        "2" {
            $sourceDuration = Get-MediaDurationSeconds $inputPath
            $targetSeconds = Read-TimeSeconds -PromptText "Enter target output duration, for example 60 or 00:01:00" -PresetValue $TargetDuration
            if ($targetSeconds -le 0) {
                throw "Target duration must be greater than zero."
            }
            $playbackSpeed = $sourceDuration / $targetSeconds
            $suffix = "duration_$($targetSeconds.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture))s"
            Write-Host ("Calculated speed multiplier: {0}x" -f $playbackSpeed.ToString("0.###", [Globalization.CultureInfo]::InvariantCulture)) -ForegroundColor Cyan
        }
        "3" {
            $startSeconds = Read-TimeSeconds -PromptText "Enter start time, for example 0 or 00:00:10" -PresetValue $StartTime
            $endSeconds = Read-TimeSeconds -PromptText "Enter end time, for example 30 or 00:00:30" -PresetValue $EndTime
            $suffix = "range_$($startSeconds.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture))s_to_$($endSeconds.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture))s"
        }
        "4" {
            $startSeconds = Read-TimeSeconds -PromptText "Enter start time, for example 0 or 00:00:10" -PresetValue $StartTime
            $endSeconds = Read-TimeSeconds -PromptText "Enter end time, for example 30 or 00:00:30" -PresetValue $EndTime
            $playbackSpeed = Read-PositiveDouble -PromptText "Enter speed multiplier, for example 2 for 2x" -PresetValue $Speed
            $suffix = "range_speed_$($playbackSpeed.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture))x"
        }
    }

    $outputPath = Get-OutputPath -InputPath $inputPath -Suffix $suffix
    Invoke-FfmpegExport -InputPath $inputPath -OutputPath $outputPath -StartSeconds $startSeconds -EndSeconds $endSeconds -PlaybackSpeed $playbackSpeed

    Write-Host ""
    Write-Host "Export completed successfully." -ForegroundColor Green
    Write-Host "Output file: $outputPath" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
