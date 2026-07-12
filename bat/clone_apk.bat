@echo off
chcp 65001 >nul
setlocal

set "SCRIPT_DIR=%~dp0"
set "PS1_SCRIPT=%SCRIPT_DIR%..\ps1\clone_apk.ps1"

if "%~1"=="" (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS1_SCRIPT%"
    set "EXIT_CODE=%ERRORLEVEL%"
    echo.
    pause
    exit /b %EXIT_CODE%
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS1_SCRIPT%" %*
exit /b %ERRORLEVEL%
