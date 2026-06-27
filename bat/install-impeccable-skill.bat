@echo off
setlocal EnableExtensions

REM Install only the Codex-compatible Impeccable skill into a project root.
REM Usage:
REM install-impeccable-skill.bat "D:\path\to\project"
REM If no argument is provided, the script will prompt for the project root.
REM
REM This BAT wrapper delegates the real installation work to the PowerShell
REM script in D:\code\myweb\daily\ps1. It does not require unzip and does not
REM install system packages.

set "PROJECT_DIR=%~1"

if "%PROJECT_DIR%"=="" (
 set /p "PROJECT_DIR=Enter project path: "
)

if "%PROJECT_DIR%"=="" (
 echo [ERROR] is requiredproject path.
 exit /b 1
)

if not exist "%PROJECT_DIR%\" (
 echo [ERROR] project pathdoes not exist: %PROJECT_DIR%
 exit /b 1
)

set "PS_SCRIPT=D:\code\myweb\daily\ps1\install-impeccable-skill.ps1"

if not exist "%PS_SCRIPT%" (
 echo [ERROR] PowerShell installer:
 echo %PS_SCRIPT%
 exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -ProjectRoot "%PROJECT_DIR%"
set "INSTALL_EXIT_CODE=%ERRORLEVEL%"

if not "%INSTALL_EXIT_CODE%"=="0" (
 echo.
 echo [ERROR] Skill installFailed,exit code %INSTALL_EXIT_CODE%.
 exit /b %INSTALL_EXIT_CODE%
)

exit /b 0
