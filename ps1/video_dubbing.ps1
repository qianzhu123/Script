<#
.SYNOPSIS
    Video dubbing and subtitle generator using Edge-TTS and FFmpeg.
.DESCRIPTION
    Interactively add AI-generated voice and subtitles to a video.
    User specifies time segments and text; script generates TTS audio,
    aligns it to the timeline, and merges everything with FFmpeg.
.NOTES
    Requirements: edge-tts (pip install edge-tts), ffmpeg
#>

$ErrorActionPreference = "Stop"

# ============================================================
# Helper Functions
# ============================================================

function Show-Banner {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "  Video Dubbing & Subtitle Generator" -ForegroundColor Cyan
    Write-Host "  Edge-TTS + FFmpeg Automation" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
}

function Test-Dependency {
    param([string]$Name, [string]$Command)

    try {
        $null = Get-Command $Command -ErrorAction Stop
    }
    catch {
        Write-Host "[ERROR] '$Name' is not installed or not in PATH." -ForegroundColor Red
        Write-Host "  Install: $Name" -ForegroundColor Yellow
        if ($Name -eq "edge-tts") {
            Write-Host "    pip install edge-tts" -ForegroundColor Yellow
        }
        elseif ($Name -eq "ffmpeg") {
            Write-Host "    https://ffmpeg.org/download.html" -ForegroundColor Yellow
        }
        exit 1
    }
}

function ConvertTo-SrtTime {
    param([double]$Seconds)

    $ts = [TimeSpan]::FromSeconds($Seconds)
    return "{0:00}:{1:00}:{2:00},{3:000}" -f $ts.Hours, $ts.Minutes, $ts.Seconds, $ts.Milliseconds
}

# Run ffmpeg with array arguments using Start-Process (handles Chinese paths correctly)
function Run-FFmpeg {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ArgList
    )

    $savedEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    try {
        $logFile = Join-Path $script:tempDir "ffmpeg_$(Get-Random).log"
        $p = Start-Process ffmpeg -ArgumentList $ArgList -NoNewWindow -Wait -PassThru `
            -RedirectStandardError $logFile 2>$null
        if (-not $p) {
            # Fallback: System.Diagnostics.Process
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "ffmpeg"
            $psi.Arguments = $ArgList -join ' '
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $proc = [System.Diagnostics.Process]::Start($psi)
            $null = $proc.StandardOutput.ReadToEnd()
            $null = $proc.StandardError.ReadToEnd()
            $proc.WaitForExit()
            return $proc.ExitCode
        }
        return $p.ExitCode
    }
    finally {
        $ErrorActionPreference = $savedEAP
    }
}

# Run ffprobe and return stdout
function Run-FFprobe {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ArgList
    )

    $savedEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    try {
        # Use cmd /c to avoid PowerShell stderr handling, but capture stdout
        $allArgs = $ArgList -join ' '
        $result = cmd /c "ffprobe $allArgs 2>NUL"
        return $result
    }
    finally {
        $ErrorActionPreference = $savedEAP
    }
}

function Get-AudioDuration {
    param([string]$FilePath)

    $output = Run-FFprobe @("-v", "quiet", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", $FilePath)
    if ($output) {
        $trimmed = $output.Trim()
        if ($trimmed -match '^\d+\.?\d*$') {
            return [double]$trimmed
        }
    }
    return 0
}

function Get-VideoDuration {
    param([string]$FilePath)

    $output = Run-FFprobe @("-v", "quiet", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", $FilePath)
    if ($output) {
        $trimmed = $output.Trim()
        if ($trimmed -match '^\d+\.?\d*$') {
            return [double]$trimmed
        }
    }
    return 0
}

function Get-VoiceList {
    param([string]$Language)

    Write-Host "[INFO] Fetching available voices for language: $Language ..." -ForegroundColor Yellow
    $rawVoices = edge-tts --list-voices 2>$null
    $voices = $rawVoices | Where-Object { $_ -match "\b$Language\b" }

    if (-not $voices) {
        Write-Host "[WARN] No voices found for language '$Language'. Showing all voices." -ForegroundColor Yellow
        $voices = $rawVoices
    }

    $voiceList = @()
    $index = 1
    foreach ($line in $voices) {
        if ($line -match "(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(.+)") {
            $voiceList += [PSCustomObject]@{
                Index    = $index
                Name     = $Matches[1]
                Gender   = $Matches[3]
                Language = $Matches[4]
            }
            $index++
        }
    }

    # Limit display to first 20
    $display = $voiceList | Select-Object -First 20
    foreach ($v in $display) {
        Write-Host ("  {0,3}. {1}  [{2}]  {3}" -f $v.Index, $v.Name, $v.Gender, $v.Language) -ForegroundColor White
    }

    if ($voiceList.Count -gt 20) {
        Write-Host "  ... ($($voiceList.Count - 20) more voices omitted)" -ForegroundColor DarkGray
    }

    return $voiceList
}

# ============================================================
# Main Script
# ============================================================

Show-Banner

# --- Check dependencies ---
Write-Host "[1/6] Checking dependencies..." -ForegroundColor Green
Test-Dependency -Name "edge-tts" -Command "edge-tts"
Test-Dependency -Name "ffmpeg" -Command "ffmpeg"
Write-Host "  All dependencies OK." -ForegroundColor Green
Write-Host ""

# --- Input video path ---
Write-Host "[2/6] Select video file" -ForegroundColor Green
$videoPath = Read-Host "  Enter video file path (drag & drop or type)"

# Remove surrounding quotes from drag-and-drop
$videoPath = $videoPath.Trim('"').Trim("'")

if (-not (Test-Path $videoPath)) {
    Write-Host "[ERROR] File not found: $videoPath" -ForegroundColor Red
    exit 1
}

$videoDir = Split-Path $videoPath -Parent
$videoName = [System.IO.Path]::GetFileNameWithoutExtension($videoPath)
$videoExt = [System.IO.Path]::GetExtension($videoPath)
$videoDuration = Get-VideoDuration $videoPath

Write-Host "  Video: $videoName$videoExt" -ForegroundColor White
Write-Host "  Duration: $([math]::Round($videoDuration, 2))s" -ForegroundColor White
Write-Host ""

# --- Voice configuration ---
Write-Host "[3/6] Voice configuration" -ForegroundColor Green
$langCode = Read-Host "  Language code (e.g. zh, en, ja, ko) [default: zh]"
if ([string]::IsNullOrWhiteSpace($langCode)) { $langCode = "zh" }

$voiceList = Get-VoiceList -Language $langCode
Write-Host ""

$voiceName = Read-Host "  Enter voice name (e.g. zh-CN-XiaoxiaoNeural) or press Enter for default"
if ([string]::IsNullOrWhiteSpace($voiceName)) {
    # Pick the first matching voice
    $firstVoice = $voiceList | Select-Object -First 1
    if ($firstVoice) {
        $voiceName = $firstVoice.Name
    }
    else {
        $voiceName = "$langCode-CN-XiaoxiaoNeural"
    }
    Write-Host "  Using default voice: $voiceName" -ForegroundColor Yellow
}

$speechRate = Read-Host "  Speech rate (e.g. +0%%, -10%%, +20%%) [default: +0%%]"
if ([string]::IsNullOrWhiteSpace($speechRate)) { $speechRate = "+0%" }

Write-Host ""

# --- Collect dubbing segments ---
Write-Host "[4/6] Define dubbing segments" -ForegroundColor Green
Write-Host "  Format: start>end>text   (with voice)" -ForegroundColor White
Write-Host "  Format: start>end         (no voice, subtitle only)" -ForegroundColor White
Write-Host "  Example: 0>5>Welcome to this video" -ForegroundColor DarkGray
Write-Host "  Example: 10>37.85         (subtitle only, no voice)" -ForegroundColor DarkGray
Write-Host "  Press Enter with '0' or empty to finish and go to next step" -ForegroundColor DarkGray
Write-Host "  Type 'list' to review, 'undo' to remove last" -ForegroundColor DarkGray
Write-Host "  Video duration: $([math]::Round($videoDuration, 2))s" -ForegroundColor Cyan
Write-Host ""

$segments = @()
$segIndex = 1

while ($true) {
    $rawInput = Read-Host "  Segment #$segIndex"

    # Empty input or '0' = finish
    if ([string]::IsNullOrWhiteSpace($rawInput) -or $rawInput.Trim() -eq "0") {
        break
    }

    if ($rawInput -eq "list") {
        Write-Host ""
        Write-Host "  --- Current segments ---" -ForegroundColor Cyan
        for ($i = 0; $i -lt $segments.Count; $i++) {
            $s = $segments[$i]
            $srtStart = ConvertTo-SrtTime $s.Start
            $srtEnd = ConvertTo-SrtTime $s.End
            $label = if ($s.NoVoice) { "(subtitle only)" } else { $s.Text }
            Write-Host ("  {0}. [{1}] -> [{2}] {3}" -f ($i + 1), $srtStart, $srtEnd, $label) -ForegroundColor White
        }
        if ($segments.Count -eq 0) {
            Write-Host "  (no segments yet)" -ForegroundColor DarkGray
        }
        Write-Host ""
        continue
    }

    if ($rawInput -eq "undo") {
        if ($segments.Count -gt 0) {
            $removed = $segments[$segments.Count - 1]
            $segments = $segments[0..($segments.Count - 2)]
            Write-Host "  Removed last segment." -ForegroundColor Yellow
        }
        else {
            Write-Host "  Nothing to undo." -ForegroundColor DarkGray
        }
        continue
    }

    # Parse input using '>' as delimiter: start>end>text or start>end
    $parts = $rawInput -split '>', 3
    if ($parts.Count -lt 2) {
        Write-Host "  [ERROR] Format: start>end>text or start>end" -ForegroundColor Red
        Write-Host "          Example: 0>5>Hello world" -ForegroundColor DarkGray
        Write-Host "          Example: 10>37.85  (subtitle only)" -ForegroundColor DarkGray
        continue
    }

    $startSec = 0
    $endSec = 0
    try {
        $startSec = [double]($parts[0].Trim())
        $endSec = [double]($parts[1].Trim())
    }
    catch {
        Write-Host "  [ERROR] Start and end must be numbers (seconds)." -ForegroundColor Red
        continue
    }

    if ($startSec -ge $endSec) {
        Write-Host "  [ERROR] Start must be less than end." -ForegroundColor Red
        continue
    }

    if ($endSec -gt $videoDuration) {
        Write-Host "  [WARN] End time exceeds video duration ($videoDuration). Clamping." -ForegroundColor Yellow
        $endSec = $videoDuration
    }

    # Determine if this segment has voice or is subtitle-only
    $noVoice = $false
    $text = ""
    if ($parts.Count -ge 3 -and -not [string]::IsNullOrWhiteSpace($parts[2].Trim())) {
        $text = $parts[2].Trim()
    }
    else {
        $noVoice = $true
    }

    $segments += [PSCustomObject]@{
        Start   = $startSec
        End     = $endSec
        Text    = $text
        NoVoice = $noVoice
    }

    $srtStart = ConvertTo-SrtTime $startSec
    $srtEnd = ConvertTo-SrtTime $endSec
    if ($noVoice) {
        Write-Host "  Added: [$srtStart] -> [$srtEnd] (subtitle only, no voice)" -ForegroundColor Yellow
    }
    else {
        Write-Host "  Added: [$srtStart] -> [$srtEnd] $text" -ForegroundColor Green
    }
    $segIndex++
}

if ($segments.Count -eq 0) {
    Write-Host "[ERROR] No segments defined. Exiting." -ForegroundColor Red
    exit 1
}

# Count voice vs subtitle-only segments
$voiceCount = ($segments | Where-Object { -not $_.NoVoice }).Count
$subOnlyCount = ($segments | Where-Object { $_.NoVoice }).Count

Write-Host ""
Write-Host "  Total segments: $($segments.Count) ($voiceCount with voice, $subOnlyCount subtitle only)" -ForegroundColor White

# --- Subtitle mode ---
Write-Host ""
$subMode = Read-Host "  Subtitle mode? (soft/hard/none) [default: soft]"
if ([string]::IsNullOrWhiteSpace($subMode)) { $subMode = "soft" }

# --- Output path ---
$outputPath = Join-Path $videoDir "${videoName}_dubbed${videoExt}"

Write-Host ""
Write-Host "[5/6] Generating dubbing..." -ForegroundColor Green

# Create temp directory
$tempDir = Join-Path $videoDir "dubbing_temp_$videoName"
$script:tempDir = $tempDir
if (Test-Path $tempDir) {
    Remove-Item $tempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

# ---- Generate SRT file ----
$srtPath = Join-Path $tempDir "subtitles.srt"
$srtContent = ""
for ($i = 0; $i -lt $segments.Count; $i++) {
    $s = $segments[$i]
    $srtStart = ConvertTo-SrtTime $s.Start
    $srtEnd = ConvertTo-SrtTime $s.End
    $srtLine = if ($s.NoVoice) { "" } else { $s.Text }
    $srtContent += "{0}`r`n{1} --> {2}`r`n{3}`r`n`r`n" -f ($i + 1), $srtStart, $srtEnd, $srtLine
}
$srtContent | Out-File -FilePath $srtPath -Encoding UTF8 -NoNewline
Write-Host "  SRT file created: $srtPath" -ForegroundColor White

# ---- Generate TTS audio for each segment ----
$ttsFiles = @()
$ttsDurations = @()

for ($i = 0; $i -lt $segments.Count; $i++) {
    $s = $segments[$i]

    # Skip subtitle-only segments (no voice)
    if ($s.NoVoice) {
        Write-Host "  Segment $($i+1): subtitle only, skipping TTS." -ForegroundColor Yellow
        $ttsFiles += $null
        $ttsDurations += 0
        continue
    }

    $mp3File = Join-Path $tempDir "seg_$i.mp3"
    $wavFile = Join-Path $tempDir "seg_$i.wav"

    Write-Host "  Generating TTS [$($i+1)/$($segments.Count)]: $($s.Text)" -ForegroundColor Cyan

    # Edge-TTS generate
    $rateArg = "--rate=$speechRate"
    edge-tts --voice $voiceName --text $s.Text $rateArg --write-media $mp3File 2>$null

    if (-not (Test-Path $mp3File)) {
        Write-Host "    [ERROR] TTS failed for segment $($i+1). Skipping." -ForegroundColor Red
        $ttsFiles += $null
        $ttsDurations += 0
        continue
    }

    # Convert MP3 to WAV
    Run-FFmpeg @("-y", "-i", $mp3File, "-ar", "44100", "-ac", "1", $wavFile) | Out-Null

    # Get actual duration
    $dur = Get-AudioDuration $wavFile
    $slotDur = $s.End - $s.Start

    Write-Host "    TTS duration: $([math]::Round($dur, 2))s, Slot: $([math]::Round($slotDur, 2))s" -ForegroundColor DarkGray

    # Process: adjust speed if needed, then pad with silence
    $processedFile = Join-Path $tempDir "seg_${i}_aligned.wav"

    if ($dur -gt $slotDur -and $dur -gt 0) {
        # TTS is longer than slot: speed up
        $speedFactor = [math]::Round($dur / $slotDur, 4)
        Write-Host "    Speeding up by ${speedFactor}x to fit slot." -ForegroundColor DarkGray
        if ($speedFactor -le 100) {
            Run-FFmpeg @("-y", "-i", $wavFile, "-filter_complex", "atempo=$speedFactor", "-ar", "44100", "-ac", "1", $processedFile) | Out-Null
        }
        else {
            # Chain two atempo filters for extreme speed-up
            $s1 = [math]::Round([math]::Sqrt($speedFactor), 4)
            $s2 = [math]::Round($speedFactor / $s1, 4)
            Run-FFmpeg @("-y", "-i", $wavFile, "-filter_complex", "atempo=$s1,atempo=$s2", "-ar", "44100", "-ac", "1", $processedFile) | Out-Null
        }
    }
    elseif ($dur -gt 0) {
        # TTS is shorter or equal: just copy, we will pad later
        Copy-Item $wavFile $processedFile -Force
    }

    # Now pad: insert silence before and after so total = slot duration
    $alignedDur = Get-AudioDuration $processedFile
    $paddingNeeded = $slotDur - $alignedDur

    if ($paddingNeeded -gt 0.05 -and $alignedDur -gt 0) {
        $preSilence = [math]::Round($paddingNeeded / 2, 3)
        $postSilence = $paddingNeeded - $preSilence

        $preSilenceFile = Join-Path $tempDir "presilence_${i}.wav"
        $postSilenceFile = Join-Path $tempDir "postsilence_${i}.wav"

        Run-FFmpeg @("-y", "-f", "lavfi", "-i", "anullsrc=r=44100:cl=mono", "-t", "$preSilence", "-q:a", "9", "-acodec", "pcm_s16le", $preSilenceFile) | Out-Null
        Run-FFmpeg @("-y", "-f", "lavfi", "-i", "anullsrc=r=44100:cl=mono", "-t", "$postSilence", "-q:a", "9", "-acodec", "pcm_s16le", $postSilenceFile) | Out-Null

        # Concatenate: pre-silence + speech + post-silence
        $concatList = Join-Path $tempDir "concat_${i}.txt"
        "file '$preSilenceFile'" | Out-File $concatList -Encoding utf8
        "file '$processedFile'" | Out-File $concatList -Encoding utf8 -Append
        "file '$postSilenceFile'" | Out-File $concatList -Encoding utf8 -Append

        $finalSegFile = Join-Path $tempDir "seg_${i}_final.wav"
        Run-FFmpeg @("-y", "-f", "concat", "-safe", "0", "-i", $concatList, "-c", "copy", $finalSegFile) | Out-Null

        $ttsFiles += $finalSegFile
    }
    else {
        $ttsFiles += $processedFile
    }

    $ttsDurations += $slotDur
}

# ---- Assemble full audio track ----
Write-Host ""
Write-Host "  Assembling audio track..." -ForegroundColor Yellow

# Build a complete silence base track matching video duration
$baseTrack = Join-Path $tempDir "base_silence.wav"
Run-FFmpeg @("-y", "-f", "lavfi", "-i", "anullsrc=r=44100:cl=mono", "-t", "$videoDuration", "-q:a", "9", "-acodec", "pcm_s16le", $baseTrack) | Out-Null

# Overlay each segment at the correct position
$currentTrack = $baseTrack

for ($i = 0; $i -lt $segments.Count; $i++) {
    if ($null -eq $ttsFiles[$i]) { continue }

    $s = $segments[$i]
    $segFull = Join-Path $tempDir "seg_full_${i}.wav"

    # Get segment duration
    $segDur = Get-AudioDuration $ttsFiles[$i]

    # Create padding before the segment starts
    if ($s.Start -gt 0) {
        $beforeSilence = Join-Path $tempDir "before_${i}.wav"
        Run-FFmpeg @("-y", "-f", "lavfi", "-i", "anullsrc=r=44100:cl=mono", "-t", "$($s.Start)", "-q:a", "9", "-acodec", "pcm_s16le", $beforeSilence) | Out-Null

        # After segment: silence to fill rest of video
        $afterTime = $videoDuration - $s.Start - $segDur
        if ($afterTime -lt 0) { $afterTime = 0 }
        $afterSilence = Join-Path $tempDir "after_${i}.wav"
        Run-FFmpeg @("-y", "-f", "lavfi", "-i", "anullsrc=r=44100:cl=mono", "-t", "$afterTime", "-q:a", "9", "-acodec", "pcm_s16le", $afterSilence) | Out-Null

        # Concat: before silence + segment + after silence
        $segConcatList = Join-Path $tempDir "seg_concat_${i}.txt"
        "file '$beforeSilence'" | Out-File $segConcatList -Encoding utf8
        "file '$($ttsFiles[$i])'" | Out-File $segConcatList -Encoding utf8 -Append
        "file '$afterSilence'" | Out-File $segConcatList -Encoding utf8 -Append

        Run-FFmpeg @("-y", "-f", "concat", "-safe", "0", "-i", $segConcatList, "-c", "copy", $segFull) | Out-Null
    }
    else {
        # Segment starts at 0
        $afterTime = $videoDuration - $segDur
        if ($afterTime -lt 0) { $afterTime = 0 }
        $afterSilence = Join-Path $tempDir "after_${i}.wav"
        Run-FFmpeg @("-y", "-f", "lavfi", "-i", "anullsrc=r=44100:cl=mono", "-t", "$afterTime", "-q:a", "9", "-acodec", "pcm_s16le", $afterSilence) | Out-Null

        $segConcatList = Join-Path $tempDir "seg_concat_${i}.txt"
        "file '$($ttsFiles[$i])'" | Out-File $segConcatList -Encoding utf8
        "file '$afterSilence'" | Out-File $segConcatList -Encoding utf8 -Append

        Run-FFmpeg @("-y", "-f", "concat", "-safe", "0", "-i", $segConcatList, "-c", "copy", $segFull) | Out-Null
    }

    # Mix with current track
    $mixedTrack = Join-Path $tempDir "mixed_${i}.wav"
    Write-Host "  Mixing segment $($i+1) into audio track..." -ForegroundColor DarkGray
    Run-FFmpeg @("-y", "-i", $currentTrack, "-i", $segFull, "-filter_complex", "[0:a][1:a]amix=inputs=2:duration=first:dropout_transition=0", "-ar", "44100", "-ac", "1", $mixedTrack) | Out-Null

    $currentTrack = $mixedTrack
}

# Convert final audio to AAC for video muxing
$finalAudio = Join-Path $tempDir "dubbing_audio.aac"
Run-FFmpeg @("-y", "-i", $currentTrack, "-c:a", "aac", "-b:a", "128k", $finalAudio) | Out-Null

Write-Host "  Audio track assembled." -ForegroundColor Green

# ---- Merge video + audio + subtitles ----
Write-Host ""
Write-Host "[6/6] Merging final video..." -ForegroundColor Green

$mergeExitCode = 0

if ($subMode -eq "hard") {
    # Hard-sub: burn subtitles into video
    $srtPathEscaped = $srtPath -replace '\\', '/' -replace ':', '\\:'
    # Do NOT use -shortest: keep full video length, pad audio if needed
    $mergeExitCode = Run-FFmpeg @("-y", "-i", $videoPath, "-i", $finalAudio, "-map", "0:v", "-map", "1:a", "-vf", "subtitles='${srtPathEscaped}'", "-c:v", "libx264", "-crf", "23", "-preset", "medium", "-c:a", "aac", "-b:a", "128k", $outputPath)
    Write-Host "  Hard subtitles burned into video." -ForegroundColor White
}
elseif ($subMode -eq "soft") {
    # Soft-sub: embed subtitles as a track
    # Do NOT use -shortest: keep full video length, pad audio if needed
    $mergeExitCode = Run-FFmpeg @("-y", "-i", $videoPath, "-i", $finalAudio, "-i", $srtPath, "-map", "0:v", "-map", "1:a", "-map", "2:s", "-c:v", "copy", "-c:a", "aac", "-b:a", "128k", "-c:s", "mov_text", $outputPath)
    Write-Host "  Soft subtitles embedded (toggleable in player)." -ForegroundColor White
}
else {
    # No subtitles: just add audio
    # Do NOT use -shortest: keep full video length, pad audio if needed
    $mergeExitCode = Run-FFmpeg @("-y", "-i", $videoPath, "-i", $finalAudio, "-map", "0:v", "-map", "1:a", "-c:v", "copy", "-c:a", "aac", "-b:a", "128k", $outputPath)
    Write-Host "  No subtitles added." -ForegroundColor White
}

Write-Host "  Merge exit code: $mergeExitCode" -ForegroundColor DarkGray

# Verify output file exists
if (Test-Path $outputPath) {
    $fileSize = (Get-Item $outputPath).Length
    Write-Host "  Output verified: $outputPath ($([math]::Round($fileSize / 1MB, 2)) MB)" -ForegroundColor Green
}
else {
    Write-Host "  [ERROR] Output file was NOT created: $outputPath" -ForegroundColor Red
    Write-Host "  Keeping temp directory for debugging: $tempDir" -ForegroundColor Yellow
    Write-Host "  Merge exit code was: $mergeExitCode" -ForegroundColor Yellow
}

# --- Cleanup ---
Write-Host ""
Write-Host "  Cleaning temp files..." -ForegroundColor DarkGray
if (Test-Path $tempDir) {
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

# --- Done ---
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  DONE!" -ForegroundColor Green
Write-Host "  Output: $outputPath" -ForegroundColor White
Write-Host "  Segments: $($segments.Count)" -ForegroundColor White
Write-Host "  Voice: $voiceName" -ForegroundColor White
Write-Host "  Subtitle mode: $subMode" -ForegroundColor White
Write-Host "============================================" -ForegroundColor Green
