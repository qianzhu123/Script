param(
    [Parameter(Position = 0)]
    [string]$ScriptPath,

    [Parameter(Position = 1)]
    [string]$IconPath,

    [Parameter(Position = 2)]
    [string]$OutputName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Message)
    Write-Host $Message
}

function Resolve-ExistingFile {
    param(
        [string]$Path,
        [string]$Description
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    $resolved = Resolve-Path -LiteralPath $Path.Trim().Trim('"') -ErrorAction Stop
    if (-not (Test-Path -LiteralPath $resolved.Path -PathType Leaf)) {
        throw "$Description is not a file: $Path"
    }
    return $resolved.Path
}

function Get-OutputStem {
    param(
        [string]$Name,
        [string]$DefaultStem
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $DefaultStem
    }

    $cleanName = $Name.Trim().Trim('"')
    $fileName = [IO.Path]::GetFileName($cleanName)
    if ($fileName -ne $cleanName) {
        throw 'Output exe name must be a file name only, not a path.'
    }

    $stem = [IO.Path]::GetFileNameWithoutExtension($fileName)
    $extension = [IO.Path]::GetExtension($fileName)
    if ($extension -and $extension -ine '.exe') {
        throw 'Output exe name must either have no extension or use the .exe extension.'
    }
    if ([string]::IsNullOrWhiteSpace($stem)) {
        throw 'Output exe name cannot be empty.'
    }

    $invalidChars = [IO.Path]::GetInvalidFileNameChars()
    foreach ($char in $invalidChars) {
        if ($stem.Contains($char)) {
            throw "Output exe name contains an invalid character: $char"
        }
    }

    return $stem
}

function Get-PythonExecutable {
    $command = Get-Command python.exe -ErrorAction SilentlyContinue
    if (-not $command) {
        $command = Get-Command python -ErrorAction SilentlyContinue
    }
    if (-not $command) {
        throw 'Python was not found in PATH.'
    }

    & $command.Source -m PyInstaller --version *> $null
    if ($LASTEXITCODE -ne 0) {
        throw 'PyInstaller is not available. Install it with: python -m pip install pyinstaller'
    }
    return $command.Source
}

function Assert-OutputExecutableAvailable {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return
    }

    $stream = $null
    try {
        $stream = [IO.File]::Open(
            $Path,
            [IO.FileMode]::Open,
            [IO.FileAccess]::ReadWrite,
            [IO.FileShare]::None
        )
    }
    catch {
        throw "Output executable is currently in use or is not writable: $Path`nClose the running executable and try again, or choose a different output name."
    }
    finally {
        if ($stream) {
            $stream.Dispose()
        }
    }
}

function New-PythonRunnerScript {
    param(
        [string]$EncodedScript,
        [string]$Extension,
        [string]$SourceStem
    )

    $template = @'
import base64
import os
import shutil
import subprocess
import sys
import tempfile

SCRIPT_EXT = __EXTENSION_JSON__
SCRIPT_BASE64 = __ENCODED_JSON__
SCRIPT_STEM = __STEM_JSON__


def get_base_dir():
    if getattr(sys, "frozen", False):
        return os.path.dirname(os.path.abspath(sys.executable))
    return os.path.dirname(os.path.abspath(__file__))


def wait_before_exit(code):
    if os.environ.get("SCRIPT_TO_EXE_NO_PAUSE") == "1":
        return code
    print("")
    print("Process finished with exit code %s" % code)
    try:
        input("Press Enter to close this window...")
    except EOFError:
        pass
    return code


def find_command(*names):
    for name in names:
        command = shutil.which(name)
        if command:
            return command
    return None


def build_command(script_path):
    extension = SCRIPT_EXT.lower()
    if extension in (".bat", ".cmd"):
        return ["cmd.exe", "/d", "/s", "/c", "call", script_path]
    if extension == ".ps1":
        powershell = find_command("pwsh.exe", "pwsh", "powershell.exe", "powershell")
        if not powershell:
            raise RuntimeError("PowerShell was not found in PATH.")
        return [powershell, "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script_path]
    if extension == ".py":
        python = find_command("python.exe", "python", "python3.exe", "python3")
        if not python:
            raise RuntimeError("Python was not found in PATH.")
        return [python, script_path]
    raise RuntimeError("Unsupported script extension: %s" % SCRIPT_EXT)


def remove_temp_script(script_path):
    if not script_path:
        return
    try:
        os.remove(script_path)
    except OSError:
        pass


def main():
    # Extract beside the executable so script-native directory lookups such as
    # %~dp0, $PSScriptRoot, and __file__ keep pointing at the original script
    # directory. A working directory alone cannot preserve those semantics.
    base_dir = get_base_dir()
    safe_stem = "".join(ch if ch.isalnum() or ch in "-_" else "_" for ch in SCRIPT_STEM)
    fd, script_path = tempfile.mkstemp(
        suffix=SCRIPT_EXT,
        prefix=".__script_to_exe_%s_" % safe_stem,
        dir=base_dir,
    )
    try:
        with os.fdopen(fd, "wb") as script_file:
            script_file.write(base64.b64decode(SCRIPT_BASE64))
        env = os.environ.copy()
        env["SCRIPT_TO_EXE_BASE_DIR"] = base_dir
        completed = subprocess.run(build_command(script_path), cwd=base_dir, env=env)
        remove_temp_script(script_path)
        script_path = None
        return wait_before_exit(completed.returncode)
    except Exception as exc:
        remove_temp_script(script_path)
        script_path = None
        print("[ERROR] %s" % exc)
        return wait_before_exit(1)
    finally:
        remove_temp_script(script_path)


if __name__ == "__main__":
    raise SystemExit(main())
'@

    return $template.
        Replace('__EXTENSION_JSON__', (ConvertTo-Json $Extension -Compress)).
        Replace('__ENCODED_JSON__', (ConvertTo-Json $EncodedScript -Compress)).
        Replace('__STEM_JSON__', (ConvertTo-Json $SourceStem -Compress))
}

function New-ExecutableShortcut {
    param(
        [string]$TargetPath,
        [string]$ShortcutPath,
        [string]$WorkingDirectory
    )

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $TargetPath
    $shortcut.WorkingDirectory = $WorkingDirectory
    $shortcut.IconLocation = "$TargetPath,0"
    $shortcut.Save()
}

if ([string]::IsNullOrWhiteSpace($ScriptPath)) {
    $ScriptPath = Read-Host 'Enter the source script path (.bat, .cmd, .ps1, or .py)'
}
$sourceScript = Resolve-ExistingFile -Path $ScriptPath -Description 'Source script'
if (-not $sourceScript) {
    throw 'A source script path is required.'
}

$extension = [IO.Path]::GetExtension($sourceScript).ToLowerInvariant()
if ($extension -notin @('.bat', '.cmd', '.ps1', '.py')) {
    throw "Unsupported script extension: $extension"
}

$resolvedIcon = Resolve-ExistingFile -Path $IconPath -Description 'Icon'
if ($resolvedIcon -and [IO.Path]::GetExtension($resolvedIcon) -ine '.ico') {
    throw 'The custom icon must be an .ico file.'
}

$sourceDir = Split-Path -Parent $sourceScript
$sourceStem = [IO.Path]::GetFileNameWithoutExtension($sourceScript)
$outputStem = Get-OutputStem -Name $OutputName -DefaultStem $sourceStem
$outPath = Join-Path $sourceDir ($outputStem + '.exe')
$shortcutPath = Join-Path $sourceDir ($outputStem + '.lnk')
Assert-OutputExecutableAvailable -Path $outPath
$projectRoot = Split-Path -Parent $PSScriptRoot
$buildRoot = Join-Path $projectRoot ('temp\script-to-exe-build-' + [Guid]::NewGuid().ToString('N'))
$runnerPath = Join-Path $buildRoot 'runner.py'
$pythonExe = Get-PythonExecutable

New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null

try {
    Write-Step "Reading source script: $sourceScript"
    $encoded = [Convert]::ToBase64String([IO.File]::ReadAllBytes($sourceScript))
    $runner = New-PythonRunnerScript -EncodedScript $encoded -Extension $extension -SourceStem $sourceStem
    [IO.File]::WriteAllText($runnerPath, $runner, [Text.UTF8Encoding]::new($false))

    $pyinstallerArgs = @(
        '-m', 'PyInstaller',
        '--onefile',
        '--console',
        '--clean',
        '--noconfirm',
        '--distpath', $sourceDir,
        '--workpath', (Join-Path $buildRoot 'work'),
        '--specpath', (Join-Path $buildRoot 'spec'),
        '--name', $outputStem
    )
    if ($resolvedIcon) {
        $pyinstallerArgs += @('--icon', $resolvedIcon)
    }
    $pyinstallerArgs += $runnerPath

    Write-Step 'Building executable...'
    & $pythonExe @pyinstallerArgs
    if ($LASTEXITCODE -ne 0) {
        throw "PyInstaller failed with exit code $LASTEXITCODE"
    }
    if (-not (Test-Path -LiteralPath $outPath -PathType Leaf)) {
        throw "Expected executable was not created: $outPath"
    }

    New-ExecutableShortcut -TargetPath $outPath -ShortcutPath $shortcutPath -WorkingDirectory $sourceDir
    Write-Step "Created executable: $outPath"
    Write-Step "Created shortcut: $shortcutPath"
}
finally {
    Remove-Item -LiteralPath $buildRoot -Recurse -Force -ErrorAction SilentlyContinue
}
