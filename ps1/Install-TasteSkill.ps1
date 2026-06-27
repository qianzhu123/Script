param(
    [string]$ProjectPath,
    [string]$SkillName = "design-taste-frontend"
)

$ErrorActionPreference = "Stop"
$RepoUrl = "https://github.com/Leonxlnx/taste-skill"

Write-Host "Taste Skill Installer"
Write-Host ""

if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
    $ProjectPath = Read-Host "Enter project path"
}

if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
    Write-Error "Project path is required."
    exit 1
}

$ResolvedProjectPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ProjectPath)

if (-not (Test-Path -LiteralPath $ResolvedProjectPath -PathType Container)) {
    Write-Error "Project path does not exist: $ResolvedProjectPath"
    exit 1
}

$npxCommand = Get-Command npx -ErrorAction SilentlyContinue
if (-not $npxCommand) {
    Write-Error "npx was not found. Install Node.js first, then try again."
    exit 1
}

Write-Host "Project path: $ResolvedProjectPath"
Write-Host "Skill name: $SkillName"
Write-Host "Repository: $RepoUrl"
Write-Host "Mode: non-interactive"
Write-Host ""

Push-Location -LiteralPath $ResolvedProjectPath
try {
    & npx skills add $RepoUrl --skill $SkillName --yes
    $ExitCode = $LASTEXITCODE
}
finally {
    Pop-Location
}

if ($ExitCode -ne 0) {
    Write-Error "Taste Skill installation failed with exit code $ExitCode."
    exit $ExitCode
}

Write-Host ""
Write-Host "Taste Skill installation completed successfully."
exit 0
