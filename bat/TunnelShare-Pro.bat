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
title TunnelShare Pro - 简易模式
color 0A
cls
echo ===============================================================================
echo                         TunnelShare Pro - 简易模式
echo ===============================================================================
echo [信息] 输出目录: %TUNNEL_OUT%
echo [信息] 临时目录:   %TUNNEL_TEMP%
echo.
where cloudflared >nul 2>nul
if errorlevel 1 (
  echo [错误] cloudflared 未安装或不在PATH中。
  goto FAIL
)
set "LOCAL_URL="
if not "%~1"=="" (set "LOCAL_URL=%~1") else set /p "LOCAL_URL=请输入要暴露的本地URL: "
if "%LOCAL_URL%"=="" (
  echo [错误] URL不能为空。
  goto FAIL
)
set "TUNNEL_LOG=%TUNNEL_TEMP%\TunnelSharePro-tunnel.log"
set "URL_FILE=%TUNNEL_OUT%\last-url.txt"
if exist "%TUNNEL_LOG%" del /q "%TUNNEL_LOG%" >nul 2>nul
if not defined TUNNEL_PROTOCOL set "TUNNEL_PROTOCOL=auto"
set "PROTOCOL_ARG="
if /i not "%TUNNEL_PROTOCOL%"=="auto" set "PROTOCOL_ARG=--protocol %TUNNEL_PROTOCOL%"

echo [信息] 正在新窗口中启动cloudflared...
for /f %%P in ('powershell -NoProfile -Command "$arg='/k cloudflared tunnel %PROTOCOL_ARG% --url \"%LOCAL_URL%\" --logfile \"%TUNNEL_LOG%\" --loglevel info'; $p=Start-Process -FilePath 'cmd.exe' -ArgumentList $arg -WindowStyle Normal -PassThru; $p.Id"') do set "TUNNEL_PID=%%P"
if not defined TUNNEL_PID (
  echo [错误] 启动cloudflared进程失败。
  goto FAIL
)
echo [完成] cloudflared PID: %TUNNEL_PID%
echo [信息] 正在等待公网域名...
set "PUBLIC_BASE="
for /L %%I in (1,1,90) do (
  for /f "usebackq delims=" %%U in (`powershell -NoProfile -Command "$p=''; if (Test-Path '%TUNNEL_LOG%') { $m = Select-String -Path '%TUNNEL_LOG%' -Pattern 'https://[a-z0-9-]+\.trycloudflare\.com' -AllMatches; if ($m) { $p = $m.Matches[-1].Value } }; Write-Output $p"`) do set "PUBLIC_BASE=%%U"
  if defined PUBLIC_BASE goto ready
  timeout /t 1 /nobreak >nul
)
echo [错误] 未能及时检测到公网域名。
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
echo 隧道已就绪
echo 本地URL        : %LOCAL_URL%
echo 公网基础URL    : %PUBLIC_BASE%
echo 最终分享URL    : %FINAL_URL%
echo PID            : %TUNNEL_PID%
echo URL文件        : %URL_FILE%
echo 日志文件       : %TUNNEL_LOG%
echo.
:menu
echo 命令: 1) 打开 2) 日志 3) 停止 4) 仅退出启动器
set "ACT="
set /p "ACT=请选择 1/2/3/4: "
if "%ACT%"=="1" start "" "%FINAL_URL%" & goto menu
if "%ACT%"=="2" if exist "%TUNNEL_LOG%" powershell -NoProfile -Command "Get-Content '%TUNNEL_LOG%' -Tail 50" & goto menu
if "%ACT%"=="3" taskkill /PID %TUNNEL_PID% /F >nul 2>nul & echo [完成] 隧道已停止。 & goto OK
if "%ACT%"=="4" echo [信息] 退出启动器，隧道继续运行。 & exit /b 0
goto menu
:FAIL
echo.
echo [失败]
if /i not "%DAILY_WEB_TERMINAL%"=="1" if /i not "%DAILY_WEB_NO_PAUSE%"=="1" pause
exit /b 1
:OK
if /i not "%DAILY_WEB_TERMINAL%"=="1" if /i not "%DAILY_WEB_NO_PAUSE%"=="1" pause
exit /b 0
