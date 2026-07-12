$ErrorActionPreference = "Stop"

$ToolRoot = "D:\code\android\apk-multiopen-tool"
$MainScript = Join-Path $ToolRoot "apk_clone_tool.py"

if (-not (Test-Path -LiteralPath $MainScript)) {
    Write-Host "APK clone tool was not found: $MainScript"
    exit 1
}

if ($args.Count -eq 0) {
    Write-Host "APK Clone Tool"
    Write-Host "This tool creates a best-effort cloned APK by changing the package name and re-signing it."
    Write-Host "Use only APKs that you own or have permission to modify."
    Write-Host ""
    $ApkPath = Read-Host "APK path"
    if ([string]::IsNullOrWhiteSpace($ApkPath)) {
        Write-Host "No APK path was provided."
        exit 1
    }

    $PackageName = Read-Host "New package name, or press Enter to auto-generate"
    $ForwardArgs = @($ApkPath)
    if (-not [string]::IsNullOrWhiteSpace($PackageName)) {
        $ForwardArgs += $PackageName
    }
}
else {
    $ForwardArgs = @($args)
}

python $MainScript @ForwardArgs
exit $LASTEXITCODE
