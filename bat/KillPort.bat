@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul 2>nul
title Windows portprocess tool
color 0A

echo ==============================================
echo Windows portprocess tool
echo ==============================================
echo.

set "port=%~1"
if "%port%"=="" set /p "port=Enter port: "
if "%port%"=="" (
 echo [ERROR] port cannot be empty.
 goto :fail
)

echo %port%| findstr /r "^[0-9][0-9]*$" >nul || (
 echo [ERROR] Invalidport: %port%
 goto :fail
)

echo.
echo port %port%...
echo ----------------------------------------------

set "pid="
for /f "tokens=5" %%a in ('netstat -ano ^| findstr /r /c:":%port% "') do (
 set "pid=%%a"
 goto :found
)

echo port %port% used by.
goto :ok

:found
set "process="
for /f "tokens=1" %%b in ('tasklist ^| findstr /r /c:"^!pid! "') do (
 set "process=%%b"
)
if not defined process set "process=Unknown"

echo port %port% used byINFO:
echo PID: !pid!
echo Process: !process!
echo ----------------------------------------------

set "confirm=%~2"
if "%confirm%"=="" set /p "confirm= end process? (Y/N): "
if /i "!confirm!"=="Y" (
 echo.
 echo end PID !pid! / process !process!...
 taskkill /f /pid !pid!
 if errorlevel 1 (
 echo [ERROR] endPIDFailed !pid!. administrator privileges.
 goto :fail
) else (
 echo [DONE] PID !pid! end.port %port% release.
)
) else (
 echo Cancelled.led, end process.
)

goto :ok

:fail
if not "%DAILY_WEB_NO_PAUSE%"=="1" pause
exit /b 1

:ok
if not "%DAILY_WEB_NO_PAUSE%"=="1" pause
exit /b 0
