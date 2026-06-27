@echo off
setlocal EnableExtensions

echo 指纹浏览器AI规则安装器
echo.

set "PROJECT_PATH=%~1"
if "%PROJECT_PATH%"=="" (
    set /p "PROJECT_PATH=请输入目标项目路径: "
)

if "%PROJECT_PATH%"=="" (
    echo [错误] 必须提供项目路径。
    exit /b 1
)

set "SCRIPT_DIR=%~dp0"
set "PS1_SCRIPT=%SCRIPT_DIR%..\ps1\install-cloakbrowser-ai-rules.ps1"

if not exist "%PS1_SCRIPT%" (
    echo [错误] 未找到PowerShell安装器:
    echo %PS1_SCRIPT%
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1_SCRIPT%" -ProjectPath "%PROJECT_PATH%"
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
    echo.
    echo 安装失败，退出码 %EXIT_CODE%.
    exit /b %EXIT_CODE%
)

echo.
echo 安装成功。
exit /b 0
