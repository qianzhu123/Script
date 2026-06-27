@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul
set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "PROJECT_DIR=%%~fI"
if not defined DAILY_PROJECT_DIR set "DAILY_PROJECT_DIR=%PROJECT_DIR%"
if not defined DAILY_OUTPUT_DIR set "DAILY_OUTPUT_DIR=%PROJECT_DIR%\output"
if not defined DAILY_TEMP_DIR set "DAILY_TEMP_DIR=%PROJECT_DIR%\temp"
set "TUNNEL_OUT=%DAILY_OUTPUT_DIR%\tunnelshare"
set "TUNNEL_TEMP=%DAILY_TEMP_DIR%\tunnelshare"
if not exist "%TUNNEL_OUT%" mkdir "%TUNNEL_OUT%" >nul 2>nul
if not exist "%TUNNEL_TEMP%" mkdir "%TUNNEL_TEMP%" >nul 2>nul
title TunnelShare Pro - mode
color 0A
cls
echo ===============================================================================
echo TunnelShare Pro - mode
echo ===============================================================================
echo [INFO] OutputDirectory: %TUNNEL_OUT%
echo [INFO] tempDirectory: %TUNNEL_TEMP%
echo.
where cloudflared >nul 2>nul
if errorlevel 1 (
 echo [ERROR] cloudflared installerPATH.
 goto FAIL
)
set "LOCAL_URL="
if not "%~1"=="" (set "LOCAL_URL=%~1") else set /p "LOCAL_URL=Enter localURL: "
if "%LOCAL_URL%"=="" (
 echo [ERROR] URLcannot be empty.
 goto FAIL
)
set "TUNNEL_LOG=%TUNNEL_TEMP%\TunnelSharePro-tunnel.log"
set "URL_FILE=%TUNNEL_OUT%\last-url.txt"
if exist "%TUNNEL_LOG%" del /q "%TUNNEL_LOG%" >nul 2>nul
if not defined TUNNEL_PROTOCOL set "TUNNEL_PROTOCOL=auto"
set "PROTOCOL_ARG="
if /i not "%TUNNEL_PROTOCOL%"=="auto" set "PROTOCOL_ARG=--protocol %TUNNEL_PROTOCOL%"

echo [INFO] Startcloudflared...
for /f %%P in ('powershell -NoProfile -Command "$arg='/k cloudflared tunnel %PROTOCOL_ARG% --url \"%LOCAL_URL%\" --logfile \"%TUNNEL_LOG%\" --loglevel info'; $p=Start-Process -FilePath 'cmd.exe' -ArgumentList $arg -WindowStyle Normal -PassThru; $p.Id"') do set "TUNNEL_PID=%%P"
if not defined TUNNEL_PID (
 echo [ERROR] StartcloudflaredprocessFailed.
 goto FAIL
)
echo [DONE] cloudflared PID: %TUNNEL_PID%
echo [INFO] publicdomain...
set "PUBLIC_BASE="
for /L %%I in (1,1,90) do (
 for /f "usebackq delims=" %%U in (`powershell -NoProfile -Command "$p=''; if (Test-Path '%TUNNEL_LOG%') { $m = Select-String -Path '%TUNNEL_LOG%' -Pattern 'https://[a-z0-9-]+\.trycloudflare\.com' -AllMatches; if ($m) { $p = $m.Matches[-1].Value } }; Write-Output $p"`) do set "PUBLIC_BASE=%%U"
 if defined PUBLIC_BASE goto ready
 timeout /t 1 /nobreak >nul
)
echo [ERROR] check publicdomain.
goto FAIL

:ready
if "%PUBLIC_BASE:~-1%"=="/" set "PUBLIC_BASE=%PUBLIC_BASE:~0,-1%"
set "PATH_PART=/"
set "TMP_NO_SCHEME=%LOCAL_URL:http://=%"
set "TMP_NO_SCHEME=%TMP_NO_SCHEME:https://=%"
for /f "tokens=1* delims=/" %%A in ("%TMP_NO_SCHEME%") do if not "%%B"=="" set "PATH_PART=/%%B"
set "FINAL_URL=%PUBLIC_BASE%"
if not "%PATH_PART%"=="/" set "FINAL_URL=%PUBLIC_BASE%%PATH_PART%"
>"%URL_FILE%" echo %FINAL_URL%
echo %FINAL_URL% | clip >nul 2>nul
echo.
echo tunnelready
echo localURL : %LOCAL_URL%
echo public URL : %PUBLIC_BASE%
echo URL : %FINAL_URL%
echo PID : %TUNNEL_PID%
echo URLfile : %URL_FILE%
echo logfile : %TUNNEL_LOG%
echo.
:menu
echo command: 1) open 2) log 3) Stop 4) onlyexitstarting
set "ACT="
set /p "ACT=Select 1/2/3/4: "
if "%ACT%"=="1" start "" "%FINAL_URL%" & goto menu
if "%ACT%"=="2" if exist "%TUNNEL_LOG%" powershell -NoProfile -Command "Get-Content '%TUNNEL_LOG%' -Tail 50" & goto menu
if "%ACT%"=="3" taskkill /PID %TUNNEL_PID% /F >nul 2>nul & echo [DONE] tunnel Stop. & goto OK
if "%ACT%"=="4" echo [INFO] exitstarting,tunnelcontinueRun. & exit /b 0
goto menu
:FAIL
echo.
echo [FAILED]
if /i not "%DAILY_WEB_TERMINAL%"=="1" if /i not "%DAILY_WEB_NO_PAUSE%"=="1" pause
exit /b 1
:OK
if /i not "%DAILY_WEB_TERMINAL%"=="1" if /i not "%DAILY_WEB_NO_PAUSE%"=="1" pause
exit /b 0
