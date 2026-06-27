@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "REPO_URL=https://github.com/Leonxlnx/taste-skill"
set "DEFAULT_SKILL=design-taste-frontend"

echo UI Skillinstaller
echo.

if "%~1"=="" (
 set /p "PROJECT_PATH=Enter projectPath: "
) else (
 set "PROJECT_PATH=%~1"
)

if "%PROJECT_PATH%"=="" (
 echo [ERROR] is requiredprojectPath.
 exit /b 1
)

if not exist "%PROJECT_PATH%\" (
 echo [ERROR] projectPathdoes not exist: %PROJECT_PATH%
 exit /b 1
)

if "%~2"=="" (
 set "SKILL_NAME=%DEFAULT_SKILL%"
) else (
 set "SKILL_NAME=%~2"
)

where npx >nul 2>nul
if errorlevel 1 (
 echo [ERROR] not foundnpx,Install Node.js and retry.
 exit /b 1
)

echo projectPath: %PROJECT_PATH%
echo Skillname: %SKILL_NAME%
echo repository: %REPO_URL%
echo mode: non-interactive
echo.

pushd "%PROJECT_PATH%"
if errorlevel 1 (
 echo [ERROR] projectPathFailed.
 exit /b 1
)

call npx skills add "%REPO_URL%" --skill "%SKILL_NAME%" --yes
set "INSTALL_EXIT=%ERRORLEVEL%"
popd

if not "%INSTALL_EXIT%"=="0" (
 echo.
 echo [ERROR] UI Skill installFailed,exit code %INSTALL_EXIT%.
 exit /b %INSTALL_EXIT%
)

echo.
echo UI Skill installSuccess.
exit /b 0
