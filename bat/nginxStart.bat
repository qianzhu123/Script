@echo off
title Nginx 控制中心 - 启动中...
chcp 65001 >nul

:: 设置项目访问地址
set TARGET_URL=http://localhost

echo [1/2] 正在检查 Nginx 状态...
tasklist /fi "imagename eq nginx.exe" | findstr /i "nginx.exe" > nul
if %errorlevel% equ 0 (
    echo [!] Nginx 已经在运行中，跳过启动步骤。
) else (
    echo [2/2] 正在启动 Nginx 服务...
    start nginx.exe
    if %errorlevel% neq 0 (
        echo [错误] Nginx 启动失败，请检查配置文件！
        pause
        exit /b
    )
)

echo.
echo [成功] 正在为您打开网站: %TARGET_URL%
start %TARGET_URL%

:: 停留3秒后自动关闭脚本窗口
timeout /t 3 >nul
exit