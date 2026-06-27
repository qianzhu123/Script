@echo off
chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion

title 本地Git提交/推送助手

echo ========================================
echo     本地Git项目提交/推送助手
echo ========================================
echo.
echo 使用说明:
echo  1. 输入项目目录，脚本将自动检查/初始化Git仓库。
echo  2. 选择提交到本地或推送到远程仓库。
echo  3. 默认位置: C:\Users\Light\Desktop\[FolderName]
echo     可以只输入文件夹名，如: MyProject
echo     将自动解析为: C:\Users\Light\Desktop\MyProject
echo.

where git >nul 2>nul
if errorlevel 1 (
    echo [错误] 未检测到Git，请安装Git for Windows:
    echo https://git-scm.com/download/win
    pause
    exit /b 1
)

set "BASE_DIR=C:\Users\Light\Desktop"

:INPUT_DIR
set "PROJECT_DIR="
set /p "PROJECT_DIR=请输入项目目录路径或桌面上的文件夹名: "
if "%PROJECT_DIR%"=="" (
    echo [信息] 目录不能为空。
    goto INPUT_DIR
)

rem If user input is not a full path, treat it as a folder name under Desktop
echo %PROJECT_DIR% | findstr /r "^[A-Za-z]:\\" >nul
if errorlevel 1 (
    set "PROJECT_DIR=%BASE_DIR%\%PROJECT_DIR%"
)

if not exist "%PROJECT_DIR%\" (
    echo [错误] 目录不存在: %PROJECT_DIR%
    echo.
    goto INPUT_DIR
)

cd /d "%PROJECT_DIR%" || (
    echo [错误] 无法进入目录: %PROJECT_DIR%
    pause
    exit /b 1
)

echo.
echo 当前项目目录: %CD%
echo.

if not exist ".git\" (
    echo [信息] 当前目录不是Git仓库。
    choice /c YN /m "初始化为Git仓库"
    if errorlevel 2 (
        echo 已取消。
        pause
        exit /b 0
    )
    git init
    if errorlevel 1 (
        echo [错误] git init 失败。
        pause
        exit /b 1
    )
)

echo.
echo ========= 可用操作 =========
echo 1. 添加所有文件并提交到本地Git
echo 2. 添加所有文件、提交并推送到远程仓库
echo 3. 仅查看Git状态
echo 4. 设置/修改远程仓库URL(origin)
echo 5. 拉取远程更新(git pull)
echo 6. 退出
echo ========================================
echo.
choice /c 123456 /m "请选择操作"
set "OPT=%errorlevel%"

if "%OPT%"=="6" goto END
if "%OPT%"=="3" goto STATUS
if "%OPT%"=="4" goto SET_REMOTE
if "%OPT%"=="5" goto PULL
if "%OPT%"=="1" goto COMMIT_ONLY
if "%OPT%"=="2" goto COMMIT_PUSH

:STATUS
echo.
git status
echo.
pause
goto END

:SET_REMOTE
echo.
set "REMOTE_URL="
set /p "REMOTE_URL=请输入远程仓库URL (e.g., https://github.com/user/repo.git or file:///D:/git/repo.git): "
if "%REMOTE_URL%"=="" (
    echo [错误] 远程仓库URL不能为空。
    pause
    goto END
)

git remote get-url origin >nul 2>nul
if errorlevel 1 (
    git remote add origin "%REMOTE_URL%"
) else (
    git remote set-url origin "%REMOTE_URL%"
)
if errorlevel 1 (
    echo [错误] 设置origin失败。
    pause
    exit /b 1
)
echo [完成] Origin 已设置为:
git remote get-url origin
echo.
pause
goto END

:PULL
echo.
set "BRANCH="
for /f "tokens=*" %%i in ('git branch --show-current 2^>nul') do set "BRANCH=%%i"
if "%BRANCH%"=="" set "BRANCH=main"
set /p "BRANCH=请输入要拉取的分支名 (press Enter to use current/default branch [%BRANCH%]): "
if "%BRANCH%"=="" set "BRANCH=main"
git pull origin "%BRANCH%"
echo.
pause
goto END

:COMMIT_ONLY
call :DO_COMMIT
goto END

:COMMIT_PUSH
call :DO_COMMIT
if errorlevel 1 goto END

git remote get-url origin >nul 2>nul
if errorlevel 1 (
    echo.
    echo [信息] 尚未设置远程仓库origin。
    choice /c YN /m "现在设置origin"
    if errorlevel 2 goto END
    goto SET_REMOTE_AND_PUSH
)
goto PUSH

:SET_REMOTE_AND_PUSH
set "REMOTE_URL="
set /p "REMOTE_URL=请输入远程仓库URL: "
if "%REMOTE_URL%"=="" (
    echo [错误] 远程仓库URL不能为空。 推送已取消。
    pause
    goto END
)
git remote add origin "%REMOTE_URL%" 2>nul || git remote set-url origin "%REMOTE_URL%"

:PUSH
echo.
set "BRANCH="
for /f "tokens=*" %%i in ('git branch --show-current 2^>nul') do set "BRANCH=%%i"
if "%BRANCH%"=="" (
    set "BRANCH=main"
    git branch -M main
)
set /p "BRANCH=请输入要推送的分支名 (press Enter to use current/default branch [%BRANCH%]): "
if "%BRANCH%"=="" set "BRANCH=main"

echo [信息] 正在推送到 origin/%BRANCH% ...
git push -u origin "%BRANCH%"
if errorlevel 1 (
    echo [错误] 推送失败，请检查远程URL、权限或网络。
    pause
    exit /b 1
)
echo [完成] 推送完成。
pause
goto END

:DO_COMMIT
echo.
echo [信息] 当前Git状态:
git status --short
echo.
choice /c YN /m "执行 git add . 添加所有更改"
if errorlevel 2 (
    echo 提交已取消。
    exit /b 1
)

git add .
if errorlevel 1 (
    echo [错误] git add 失败。
    pause
    exit /b 1
)

git diff --cached --quiet
if not errorlevel 1 (
    echo [信息] 暂存区没有可提交的更改。
    pause
    exit /b 1
)

set "COMMIT_MSG="
set /p "COMMIT_MSG=请输入提交信息(直接回车使用默认): "
if "%COMMIT_MSG%"=="" set "COMMIT_MSG=update project"

git commit -m "%COMMIT_MSG%"
if errorlevel 1 (
    echo [错误] git commit 失败，请检查Git用户名/邮箱是否已配置。
    echo Run: git config --global user.name "Your Name"
    echo Run: git config --global user.email "your@email.com"
    pause
    exit /b 1
)
echo [完成] 已提交到本地Git。
exit /b 0

:END
echo.
echo 操作完成。
endlocal
