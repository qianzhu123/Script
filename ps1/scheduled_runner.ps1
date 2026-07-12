param(
    [Parameter(Position = 0)]
    [string]$ScriptPath = "",

    [Parameter(Position = 1)]
    [int]$IntervalSeconds = 0,

    [Parameter(Position = 2)]
    [double]$DurationMinutes = 0,

    [int]$DurationSeconds = 0,
    [double]$IntervalMinutes = 0,
    [switch]$ContinueOnError,
    [switch]$NoPause
)

$ErrorActionPreference = "Stop"

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-WarnMsg {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Read-RequiredText {
    param([string]$Prompt)

    while ($true) {
        $value = Read-Host $Prompt
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value.Trim()
        }

        Write-WarnMsg "This value is required."
    }
}

function Read-PositiveNumber {
    param(
        [string]$Prompt,
        [string]$UnitName
    )

    while ($true) {
        $rawValue = Read-RequiredText -Prompt $Prompt
        $number = 0.0
        if ([double]::TryParse($rawValue, [ref]$number) -and $number -gt 0) {
            return $number
        }

        Write-WarnMsg "Enter a positive $UnitName value."
    }
}

function Resolve-TargetPath {
    param([string]$InputPath)

    if ([string]::IsNullOrWhiteSpace($InputPath)) {
        $InputPath = Read-RequiredText -Prompt "Script path"
    }

    $expandedPath = [Environment]::ExpandEnvironmentVariables($InputPath.Trim().Trim('"'))
    if (-not [System.IO.Path]::IsPathRooted($expandedPath)) {
        $expandedPath = Join-Path (Get-Location).Path $expandedPath
    }

    $fullPath = [System.IO.Path]::GetFullPath($expandedPath)
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "Script file was not found: $fullPath"
    }

    return $fullPath
}

function Get-SecondsValue {
    param(
        [int]$Seconds,
        [double]$Minutes,
        [string]$Prompt,
        [string]$PromptUnit,
        [double]$PromptMultiplier
    )

    $totalSeconds = ([double]$Seconds) + ($Minutes * 60)
    if ($totalSeconds -le 0) {
        $inputValue = Read-PositiveNumber -Prompt $Prompt -UnitName $PromptUnit
        $totalSeconds = $inputValue * $PromptMultiplier
    }

    if ($totalSeconds -le 0) {
        throw "The time value must be greater than zero."
    }

    return [int][Math]::Ceiling($totalSeconds)
}

function Invoke-TargetScript {
    param([string]$Path)

    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()

    switch ($extension) {
        ".ps1" {
            & powershell -NoProfile -ExecutionPolicy Bypass -File $Path
            break
        }
        ".bat" {
            & cmd.exe /d /c "`"$Path`""
            break
        }
        ".cmd" {
            & cmd.exe /d /c "`"$Path`""
            break
        }
        default {
            & $Path
            break
        }
    }

    if ($null -eq $LASTEXITCODE) {
        return 0
    }

    return [int]$LASTEXITCODE
}

$targetPath = Resolve-TargetPath -InputPath $ScriptPath
$intervalTotalSeconds = Get-SecondsValue `
    -Seconds $IntervalSeconds `
    -Minutes $IntervalMinutes `
    -Prompt "Interval seconds" `
    -PromptUnit "seconds" `
    -PromptMultiplier 1
$durationTotalSeconds = Get-SecondsValue `
    -Seconds $DurationSeconds `
    -Minutes $DurationMinutes `
    -Prompt "Total duration minutes" `
    -PromptUnit "minutes" `
    -PromptMultiplier 60

$startedAt = Get-Date
$deadline = $startedAt.AddSeconds($durationTotalSeconds)
$runCount = 0
$failedCount = 0

Write-Info "Scheduled runner started."
Write-Info "Target: $targetPath"
Write-Info "Interval: $intervalTotalSeconds seconds"
Write-Info "Total duration: $durationTotalSeconds seconds"
Write-Info "Deadline: $($deadline.ToString('yyyy-MM-dd HH:mm:ss'))"

while ((Get-Date) -lt $deadline) {
    $runCount++
    $runStartedAt = Get-Date
    Write-Info "Run #$runCount started at $($runStartedAt.ToString('yyyy-MM-dd HH:mm:ss'))."

    try {
        $exitCode = Invoke-TargetScript -Path $targetPath
    }
    catch {
        $failedCount++
        Write-WarnMsg "Run #$runCount failed: $($_.Exception.Message)"
        if (-not $ContinueOnError) {
            exit 1
        }
        $exitCode = 1
    }

    if ($exitCode -ne 0) {
        $failedCount++
        Write-WarnMsg "Run #$runCount exited with code $exitCode."
        if (-not $ContinueOnError) {
            exit $exitCode
        }
    }
    else {
        Write-Ok "Run #$runCount completed successfully."
    }

    $now = Get-Date
    if ($now -ge $deadline) {
        break
    }

    $remainingSeconds = [int][Math]::Floor(($deadline - $now).TotalSeconds)
    if ($remainingSeconds -lt $intervalTotalSeconds) {
        break
    }

    $sleepSeconds = [Math]::Min($intervalTotalSeconds, $remainingSeconds)
    Write-Info "Waiting $sleepSeconds seconds before the next run."
    Start-Sleep -Seconds $sleepSeconds
}

Write-Info "Scheduled runner finished."
Write-Info "Runs: $runCount"
Write-Info "Failures: $failedCount"

if ($failedCount -gt 0) {
    exit 1
}

exit 0
