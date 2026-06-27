@echo off
setlocal EnableExtensions

rem 自动启动脚本生成器
rem 项目本地PowerShell脚本:
rem D:\code\myweb\daily\ps1\generate_start_script.ps1

set "PS1_SCRIPT=%~dp0..\ps1\generate_start_script.ps1"

if not exist "%PS1_SCRIPT%" (
    echo [错误] 未找到PowerShell脚本:
    echo         %PS1_SCRIPT%
    echo.
    if /i not "%DAILY_WEB_NO_PAUSE%"=="1" pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1_SCRIPT%" %*
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if /i not "%DAILY_WEB_NO_PAUSE%"=="1" pause
exit /b %EXIT_CODE%
