@echo off
setlocal

set "WINGET=winget"
set "WINGET_FOUND=0"
where winget >nul 2>nul
if errorlevel 1 (
    for /f "delims=" %%I in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Command winget.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source"') do set "WINGET=%%I"
    if exist "%WINGET%" set "WINGET_FOUND=1"
    if "%WINGET_FOUND%"=="0" (
        if exist "%LOCALAPPDATA%\Microsoft\WindowsApps\winget.exe" (
            set "WINGET=%LOCALAPPDATA%\Microsoft\WindowsApps\winget.exe"
            set "WINGET_FOUND=1"
        )
    )
) else (
    set "WINGET_FOUND=1"
)

if "%WINGET_FOUND%"=="0" (
    echo 未找到winget。
    echo 请从Microsoft Store安装或修复App Installer后重试。
    echo.
    pause
    exit /b 1
)

echo 正在更新winget源...
echo 命令: "%WINGET%" source update
echo.
"%WINGET%" source update
echo.

echo winget中已安装的PowerShell包:
echo 命令: "%WINGET%" list --id Microsoft.PowerShell --source winget
echo.
"%WINGET%" list --id Microsoft.PowerShell --source winget
echo.

echo winget源中最新的PowerShell包版本:
echo 命令: "%WINGET%" show --id Microsoft.PowerShell --source winget --versions
echo.
"%WINGET%" show --id Microsoft.PowerShell --source winget --versions
echo.

echo 正在通过winget更新PowerShell...
echo 命令: "%WINGET%" upgrade --id Microsoft.PowerShell --source winget --include-unknown
echo.
"%WINGET%" upgrade --id Microsoft.PowerShell --source winget --include-unknown
echo.
echo 更新命令完成，请重启终端并检查版本。
pause
