@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul 2>nul
set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "PROJECT_DIR=%%~fI"
if not defined DAILY_TEMP_DIR set "DAILY_TEMP_DIR=%PROJECT_DIR%\temp"
if not exist "%DAILY_TEMP_DIR%" mkdir "%DAILY_TEMP_DIR%" >nul 2>nul
title portused bycheck processclean

:main
cls
echo ==================================================
echo portused bycheck processclean
echo ==================================================
echo.
echo InputQexit.
echo.
set "PORT="
set /p "PORT=Enter port: "
if /i "%PORT%"=="Q" goto :exit
if "%PORT%"=="" goto :invalid
for /f "delims=0123456789" %%A in ("%PORT%") do goto :invalid
if %PORT% LSS 1 goto :invalid
if %PORT% GTR 65535 goto :invalid

echo checklocalport %PORT%...
echo.
set "RESULT_FILE=%DAILY_TEMP_DIR%\port_check_%RANDOM%%RANDOM%.txt"
set "PIDLIST="
set "FOUND=0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=[int]$env:PORT; $rows=@(); try { $rows += Get-NetTCPConnection -LocalPort $p -ErrorAction SilentlyContinue | Select-Object @{Name='Protocol';Expression={'TCP'}},LocalAddress,LocalPort,State,OwningProcess } catch {}; try { $rows += Get-NetUDPEndpoint -LocalPort $p -ErrorAction SilentlyContinue | Select-Object @{Name='Protocol';Expression={'UDP'}},LocalAddress,LocalPort,@{Name='State';Expression={'Open'}},OwningProcess } catch {}; foreach ($r in $rows) { $name='Unknown'; try { $proc=Get-Process -Id $r.OwningProcess -ErrorAction Stop; $name=$proc.ProcessName } catch {}; Write-Output ($r.OwningProcess.ToString() + '|' + $r.Protocol + '|' + $r.LocalAddress + ':' + $r.LocalPort + '|' + $r.State + '|' + $name) }" > "%RESULT_FILE%"
for %%Z in ("%RESULT_FILE%") do if %%~zZ GTR 0 set "FOUND=1"
if "%FOUND%"=="0" (
 echo localTCP/UDPprocessused byport %PORT%.
 del "%RESULT_FILE%" >nul 2>nul
 if /i "%DAILY_WEB_TERMINAL%"=="1" goto :main
 pause
 goto :main
)
echo PID local status process tool
echo ---------- ---------- ---------------------------- ------------ ----------------
for /f "usebackq tokens=1-5 delims=|" %%A in ("%RESULT_FILE%") do (
 set "PID=%%A"
 set "PROTO=%%B"
 set "LOCAL=%%C"
 set "STATE=%%D"
 set "PNAME=%%E"
 call :printRow "!PID!" "!PROTO!" "!LOCAL!" "!STATE!" "!PNAME!"
 echo !PIDLIST! | findstr /c:" !PID! " >nul
 if errorlevel 1 set "PIDLIST=!PIDLIST! !PID! "
)
del "%RESULT_FILE%" >nul 2>nul
echo.
echo WARN: Stopprocess tool.
choice /c YN /m " stoppingprocess"
if errorlevel 2 goto :main
echo.
for %%P in (%PIDLIST%) do if not "%%P"=="0" taskkill /F /PID %%P
echo Done.
if /i "%DAILY_WEB_TERMINAL%"=="1" goto :main
pause
goto :main

:printRow
set "C1=%~1 "
set "C2=%~2 "
set "C3=%~3 "
set "C4=%~4 "
set "C5=%~5"
echo %C1:~0,10% %C2:~0,10% %C3:~0,28% %C4:~0,12% %C5%
exit /b 0
:invalid
echo InvalidInput,Enter 1-65535.
if /i "%DAILY_WEB_TERMINAL%"=="1" goto :main
pause
goto :main
:exit
echo.
exit /b 0
