@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
set "PS1_SCRIPT=%SCRIPT_DIR%..\ps1\Install-Remotion.ps1"

if not exist "%PS1_SCRIPT%" (
 echo PowerShell installer:
 echo %PS1_SCRIPT%
 pause
 exit /b 1
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS1_SCRIPT%" %*
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
 echo.
 echo RemotionInstallFailed,exit code: %EXIT_CODE%
 pause
)

exit /b %EXIT_CODE%
