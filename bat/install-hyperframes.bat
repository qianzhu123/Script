@echo off
setlocal EnableExtensions

REM HyperFrames installer and project initializer for Windows.
REM This launcher calls the PowerShell installer from the sibling ps1 folder.

set "SCRIPT_DIR=%~dp0"
set "PS1_SCRIPT=%SCRIPT_DIR%..\ps1\install-hyperframes.ps1"

if not exist "%PS1_SCRIPT%" (
    echo [错误] 未找到PowerShell安装器:
    echo %PS1_SCRIPT%
    echo.
    pause
    exit /b 1
)

echo HyperFrames 安装器
echo =====================
echo.

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS1_SCRIPT%" %*
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
    echo.
    echo HyperFrames安装失败，退出码: %EXIT_CODE%
    pause
)

exit /b %EXIT_CODE%
