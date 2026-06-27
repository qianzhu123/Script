@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul

:: Directory
set "TARGET_DIR=D:\code\github"

:: Create target directory if it does not exist
if not exist "%TARGET_DIR%" (
 echo [INFO] Directorydoes not exist,create: %TARGET_DIR%
 mkdir "%TARGET_DIR%"
)

:: Check if Git is available
where git >nul 2>nul
if errorlevel 1 (
 echo [ERROR] Git was not found, installeradd it to PATH.
 pause
 exit /b 1
)

:: Ask user for repository URL
set /p REPO_URL=Enter GitrepositoryURL: 

if "%REPO_URL%"=="" (
 echo [ERROR] URLcannot be empty.
 pause
 exit /b 1
)

:: Switch to target directory
cd /d "%TARGET_DIR%"

echo [INFO] Clone: %TARGET_DIR%
git clone "%REPO_URL%"

if errorlevel 1 (
 echo [ERROR] CloneFailed,checkURL network connection.
) else (
 echo [DONE] CloneDone!
)

pause
endlocal