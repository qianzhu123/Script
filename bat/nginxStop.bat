@echo off
title Nginx 控制中心 - 正在停止...
chcp 65001 >nul

echo [1/2] 正在发送停止信号...
nginx.exe -s quit

:: 等待2秒确保进程退出
timeout /t 2 >nul

:: 检查是否还有残留进程并强制清理
tasklist /fi "imagename eq nginx.exe" | findstr /i "nginx.exe" > nul
if %errorlevel% equ 0 (
    echo [2/2] 正在强制清理残留进程...
    taskkill /f /t /im nginx.exe >nul 2>&1
)

echo.
echo [完成] Nginx 服务已安全关闭。
timeout /t 3 >nul
exit