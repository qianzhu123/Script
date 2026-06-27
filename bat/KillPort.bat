@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul 2>nul
title Windows 端口进程终结器
color 0A

echo ==============================================
echo           Windows 端口进程终结器
echo ==============================================
echo.

set "port=%~1"
if "%port%"=="" set /p "port=请输入端口号: "
if "%port%"=="" (
    echo [错误] 端口号不能为空。
    goto :fail
)

echo %port%| findstr /r "^[0-9][0-9]*$" >nul || (
    echo [错误] 无效端口号: %port%
    goto :fail
)

echo.
echo 正在查询端口 %port% ...
echo ----------------------------------------------

set "pid="
for /f "tokens=5" %%a in ('netstat -ano ^| findstr /r /c:":%port% "') do (
    set "pid=%%a"
    goto :found
)

echo 端口 %port% 未被占用。
goto :ok

:found
set "process="
for /f "tokens=1" %%b in ('tasklist ^| findstr /r /c:"^!pid! "') do (
    set "process=%%b"
)
if not defined process set "process=Unknown"

echo 端口 %port% 占用信息:
echo PID: !pid!
echo Process: !process!
echo ----------------------------------------------

set "confirm=%~2"
if "%confirm%"=="" set /p "confirm=是否强制结束该进程? (Y/N): "
if /i "!confirm!"=="Y" (
    echo.
    echo 正在结束 PID !pid! / 进程 !process! ...
    taskkill /f /pid !pid!
    if errorlevel 1 (
        echo [错误] 结束PID失败 !pid!. 可能需要管理员权限。
        goto :fail
    ) else (
        echo [完成] PID !pid! 已结束。端口 %port% 应已释放。
    )
) else (
    echo 已取消，未结束任何进程。
)

goto :ok

:fail
if not "%DAILY_WEB_NO_PAUSE%"=="1" pause
exit /b 1

:ok
if not "%DAILY_WEB_NO_PAUSE%"=="1" pause
exit /b 0
