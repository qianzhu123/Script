@echo off
chcp 65001 >nul
setlocal EnableExtensions

REM Runs a script repeatedly with a fixed interval and total duration.

set "PS1_SCRIPT=%~dp0..\ps1\scheduled_runner.ps1"

if not exist "%PS1_SCRIPT%" (
    echo [ERROR] PowerShell script was not found:
    echo %PS1_SCRIPT%
    echo.
    if /i not "%DAILY_WEB_NO_PAUSE%"=="1" pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1_SCRIPT%" %*
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if /i not "%DAILY_WEB_NO_PAUSE%"=="1" pause
exit /b %EXIT_CODE%
