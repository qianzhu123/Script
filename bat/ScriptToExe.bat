@echo off
setlocal EnableExtensions
chcp 65001 >nul 2>nul

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "PROJECT_DIR=%%~fI"
set "PS1_SCRIPT=%PROJECT_DIR%\ps1\ScriptToExe.ps1"

if not exist "%PS1_SCRIPT%" (
 echo [ERROR] PowerShell converter:
 echo %PS1_SCRIPT%
 set "EXIT_CODE=2"
 goto END
)

set "SOURCE_PATH=%~1"
if not defined SOURCE_PATH (
 set /p "SOURCE_PATH=Enter source script path(.bat/.cmd/.ps1/.py): "
)
set "SOURCE_PATH=%SOURCE_PATH:"=%"
if not defined SOURCE_PATH (
 echo [ERROR] is requiredsource script path.
 set "EXIT_CODE=3"
 goto END
)

set "ICON_PATH=%~2"
if "%~2"=="" if "%~3"=="" (
 set /p "ICON_PATH=Enter ICOicon path,press Enter for default icon: "
)
set "ICON_PATH=%ICON_PATH:"=%"

set "OUTPUT_NAME=%~3"
if "%~3"=="" (
 set /p "OUTPUT_NAME=Enter Outputexename,press Enter for source script name: "
)
set "OUTPUT_NAME=%OUTPUT_NAME:"=%"

set "POWERSHELL_EXE=powershell.exe"
where powershell.exe >nul 2>nul
if errorlevel 1 (
 where pwsh.exe >nul 2>nul
 if errorlevel 1 (
 echo [ERROR] powershell.exe pwsh.exe.
 set "EXIT_CODE=4"
 goto END
)
 set "POWERSHELL_EXE=pwsh.exe"
)

if defined ICON_PATH (
 if defined OUTPUT_NAME (
 "%POWERSHELL_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS1_SCRIPT%" -ScriptPath "%SOURCE_PATH%" -IconPath "%ICON_PATH%" -OutputName "%OUTPUT_NAME%"
) else (
 "%POWERSHELL_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS1_SCRIPT%" -ScriptPath "%SOURCE_PATH%" -IconPath "%ICON_PATH%"
)
) else (
 if defined OUTPUT_NAME (
 "%POWERSHELL_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS1_SCRIPT%" -ScriptPath "%SOURCE_PATH%" -OutputName "%OUTPUT_NAME%"
) else (
 "%POWERSHELL_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS1_SCRIPT%" -ScriptPath "%SOURCE_PATH%"
)
)
set "EXIT_CODE=%ERRORLEVEL%"

:END
echo.
if "%EXIT_CODE%"=="0" (
 echo [DONE] runfile shortcut create script.
) else (
 echo [FAILED] convertFailed,exit code: %EXIT_CODE%
)
if /i not "%DAILY_WEB_TERMINAL%"=="1" if /i not "%DAILY_WEB_NO_PAUSE%"=="1" pause
exit /b %EXIT_CODE%
