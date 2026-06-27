$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$converter = Join-Path $projectRoot 'ps1\ScriptToExe.ps1'
$fixtureRoot = Join-Path $projectRoot 'temp\script-to-exe test'
$sourcePath = Join-Path $fixtureRoot 'relative-path-test.bat'
$markerPath = Join-Path $fixtureRoot 'marker.txt'
$exePath = Join-Path $fixtureRoot 'relative-path-test.exe'
$shortcutPath = Join-Path $fixtureRoot 'relative-path-test.lnk'
$lockedExeStream = $null

Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
[IO.File]::WriteAllText($markerPath, 'same-directory-ok', [Text.Encoding]::ASCII)
[IO.File]::WriteAllText(
    $sourcePath,
    "@echo off`r`nset /p VALUE=<`"%~dp0marker.txt`"`r`necho RESULT=%VALUE%`r`nexit /b 0`r`n",
    [Text.Encoding]::ASCII
)

try {
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $converter -ScriptPath $sourcePath
    if ($LASTEXITCODE -ne 0) {
        throw "Converter exited with code $LASTEXITCODE"
    }
    if (-not (Test-Path -LiteralPath $exePath)) {
        throw "Executable was not created: $exePath"
    }
    if (-not (Test-Path -LiteralPath $shortcutPath)) {
        throw "Shortcut was not created: $shortcutPath"
    }

    $env:SCRIPT_TO_EXE_NO_PAUSE = '1'
    $output = & $exePath 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "Generated executable exited with code $LASTEXITCODE. Output: $output"
    }
    if ($output -notmatch 'RESULT=same-directory-ok') {
        throw "Generated executable did not preserve the source directory. Output: $output"
    }

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    if ($shortcut.TargetPath -ne $exePath) {
        throw "Shortcut target mismatch: $($shortcut.TargetPath)"
    }
    if ($shortcut.WorkingDirectory -ne $fixtureRoot) {
        throw "Shortcut working directory mismatch: $($shortcut.WorkingDirectory)"
    }

    $lockedExeStream = [IO.File]::Open(
        $exePath,
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        [IO.FileShare]::Read
    )
    $savedErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $lockedOutput = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $converter -ScriptPath $sourcePath 2>&1 | Out-String
        $lockedExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $savedErrorActionPreference
    }
    if ($lockedExitCode -eq 0) {
        throw 'Converter unexpectedly overwrote an executable that was in use.'
    }
    if ($lockedOutput -notmatch 'Output executable is currently in use') {
        throw "Converter did not report the locked output clearly. Output: $lockedOutput"
    }

    Write-Host '[PASS] ScriptToExe preserves relative paths and detects locked output files.'
}
finally {
    if ($lockedExeStream) {
        $lockedExeStream.Dispose()
    }
    Remove-Item Env:SCRIPT_TO_EXE_NO_PAUSE -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}
