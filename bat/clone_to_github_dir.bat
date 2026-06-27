@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul

:: 目标目录
set "TARGET_DIR=D:\code\github"

:: Create target directory if it does not exist
if not exist "%TARGET_DIR%" (
    echo [信息] 目录不存在，正在创建: %TARGET_DIR%
    mkdir "%TARGET_DIR%"
)

:: Check if Git is available
where git >nul 2>nul
if errorlevel 1 (
    echo [错误] 未找到Git，请安装并将其加入PATH。
    pause
    exit /b 1
)

:: Ask user for repository URL
set /p REPO_URL=请输入Git仓库URL: 

if "%REPO_URL%"=="" (
    echo [错误] URL不能为空。
    pause
    exit /b 1
)

:: Switch to target directory
cd /d "%TARGET_DIR%"

echo [信息] 正在克隆到: %TARGET_DIR%
git clone "%REPO_URL%"

if errorlevel 1 (
    echo [错误] 克隆失败，请检查URL或网络连接。
) else (
    echo [完成] 克隆完成!
)

pause
endlocal