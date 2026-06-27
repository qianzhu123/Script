@echo off
setlocal EnableExtensions

echo browserAI installer
echo.

set "PROJECT_PATH=%~1"
if "%PROJECT_PATH%"=="" (
 set /p "PROJECT_PATH=Enter projectPath: "
)

if "%PROJECT_PATH%"=="" (
 echo [ERROR] is requiredprojectPath.
 exit /b 1
)

set "SCRIPT_DIR=%~dp0"
set "PS1_SCRIPT=%SCRIPT_DIR%..\ps1\install-cloakbrowser-ai-rules.ps1"

if not exist "%PS1_SCRIPT%" (
 echo [ERROR] PowerShell installer:
 echo %PS1_SCRIPT%
 exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1_SCRIPT%" -ProjectPath "%PROJECT_PATH%"
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
 echo.
 echo InstallFailed,exit code %EXIT_CODE%.
 exit /b %EXIT_CODE%
)

echo.
echo InstallSuccess.
exit /b 0
