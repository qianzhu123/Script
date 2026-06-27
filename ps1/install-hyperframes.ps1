param(
    [Parameter(Position = 0)]
    [string]$ProjectPath,

    [switch]$SkipPreview,

    [switch]$NoPause
)

$ErrorActionPreference = "Stop"

function Write-Title {
    param([string]$Message)
    Write-Host ""
    Write-Host $Message -ForegroundColor Cyan
    Write-Host ("=" * $Message.Length) -ForegroundColor Cyan
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Assert-Command {
    param(
        [string]$Name,
        [string]$InstallHint
    )

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name was not found. $InstallHint"
    }
}

function Invoke-Step {
    param(
        [string]$Command,
        [string[]]$Arguments
    )

    Write-Info ("Running: {0} {1}" -f $Command, ($Arguments -join " "))
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw ("Command failed with exit code {0}: {1}" -f $LASTEXITCODE, $Command)
    }
}

function Read-RequiredPath {
    if (-not [string]::IsNullOrWhiteSpace($ProjectPath)) {
        return $ProjectPath
    }

    return Read-Host "Enter the target HyperFrames project path"
}

function Write-Utf8NoBom {
    param(
        [string]$Path,
        [string]$Content
    )

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Write-QuickStart {
    param([string]$TargetPath)

    $quickStartPath = Join-Path $TargetPath "HYPERFRAMES_QUICK_START.md"
    $content = @"
# HyperFrames Quick Start

This project was initialized by the local HyperFrames installer.

## What HyperFrames Does

HyperFrames lets you write video compositions with standard web technologies:

- HTML for structure.
- CSS for layout and styling.
- JavaScript for animation and timing.
- Browser rendering plus FFmpeg output for MP4 export.

## Common Commands

Preview the project:

````bash
npx hyperframes preview
````

Render the project:

````bash
npx hyperframes render
````

Add a catalog component:

````bash
npx hyperframes add component-name
````

## Suggested Workflow

1. Edit the composition HTML, CSS, and JavaScript files.
2. Run the preview command and check the browser output.
3. Add assets such as video, audio, images, SVG, Lottie, or fonts.
4. Render the final video when the preview looks correct.

## Useful Links

- HyperFrames repository: https://github.com/heygen-com/hyperframes
- Component catalog: https://hyperframes.heygen.com/catalog
"@

    Write-Utf8NoBom -Path $quickStartPath -Content $content
    Write-Ok "Wrote quick start guide: $quickStartPath"
}

try {
    Write-Title "HyperFrames Installer"
    Write-Host "This installer creates or initializes a HyperFrames project."
    Write-Host "It checks Node.js, npm, and FFmpeg, then prints the next commands."

    $ProjectPath = (Read-RequiredPath).Trim().Trim('"')
    if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
        throw "Project path is required."
    }

    $ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
    $ProjectName = Split-Path -Leaf $ProjectPath
    $ParentPath = Split-Path -Parent $ProjectPath

    if ([string]::IsNullOrWhiteSpace($ProjectName)) {
        throw "Project path must include a project folder name."
    }

    Assert-Command -Name "node" -InstallHint "Install Node.js 22 or later, then try again."
    Assert-Command -Name "npm" -InstallHint "Install npm with Node.js, then try again."

    $nodeVersion = (& node --version)
    $npmVersion = (& npm --version)
    Write-Ok "Node.js detected: $nodeVersion"
    Write-Ok "npm detected: $npmVersion"

    if (Get-Command "ffmpeg" -ErrorAction SilentlyContinue) {
        $ffmpegVersion = (& ffmpeg -version | Select-Object -First 1)
        Write-Ok "FFmpeg detected: $ffmpegVersion"
    } else {
        Write-Warn "FFmpeg was not found. Preview may work, but rendering usually requires FFmpeg."
        Write-Warn "Install FFmpeg before running npx hyperframes render."
    }

    if (-not (Test-Path $ParentPath)) {
        Write-Info "Creating parent directory: $ParentPath"
        New-Item -ItemType Directory -Path $ParentPath -Force | Out-Null
    }

    $shouldRunInit = $true
    if (Test-Path $ProjectPath) {
        $existingItems = Get-ChildItem -LiteralPath $ProjectPath -Force -ErrorAction SilentlyContinue
        if ($existingItems.Count -gt 0) {
            Write-Warn "The target directory already exists and is not empty: $ProjectPath"
            $answer = Read-Host "Skip HyperFrames init and only write the quick start guide? Type Y to skip, or press Enter to run init anyway"
            if ($answer -match '^(y|yes)$') {
                $shouldRunInit = $false
            }
        }
    }

    if ($shouldRunInit) {
        Push-Location $ParentPath
        try {
            Invoke-Step -Command "npx" -Arguments @("--yes", "hyperframes", "init", $ProjectName)
        } finally {
            Pop-Location
        }
    } else {
        if (-not (Test-Path $ProjectPath)) {
            New-Item -ItemType Directory -Path $ProjectPath -Force | Out-Null
        }
    }

    if (-not (Test-Path $ProjectPath)) {
        throw "Project directory was not created: $ProjectPath"
    }

    Write-QuickStart -TargetPath $ProjectPath

    Write-Title "Installation Complete"
    Write-Ok "Project path: $ProjectPath"
    Write-Host ""
    Write-Host "Next commands:"
    Write-Host "  cd /d `"$ProjectPath`""
    Write-Host "  npx hyperframes preview"
    Write-Host "  npx hyperframes render"
    Write-Host ""
    Write-Host "What to edit:"
    Write-Host "  Open the generated composition files and edit the HTML, CSS, and JavaScript."
    Write-Host "  Add media assets such as images, audio, video, SVG, Lottie, or fonts."
    Write-Host "  Read HYPERFRAMES_QUICK_START.md for the local quick start notes."

    if (-not $SkipPreview) {
        $previewAnswer = Read-Host "Start HyperFrames preview now? Type Y to start, or press Enter to skip"
        if ($previewAnswer -match '^(y|yes)$') {
            Push-Location $ProjectPath
            try {
                Invoke-Step -Command "npx" -Arguments @("hyperframes", "preview")
            } finally {
                Pop-Location
            }
        }
    }

    exit 0
} catch {
    Write-Host ""
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    if (-not $NoPause) {
        Write-Host ""
        Read-Host "Press Enter to close"
    }
}
