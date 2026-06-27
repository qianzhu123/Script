@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "REPO_URL=https://github.com/Leonxlnx/taste-skill"
set "DEFAULT_SKILL=design-taste-frontend"

echo UI框架Skill安装器
echo.

if "%~1"=="" (
    set /p "PROJECT_PATH=请输入项目路径: "
) else (
    set "PROJECT_PATH=%~1"
)

if "%PROJECT_PATH%"=="" (
    echo [错误] 必须提供项目路径。
    exit /b 1
)

if not exist "%PROJECT_PATH%\" (
    echo [错误] 项目路径不存在: %PROJECT_PATH%
    exit /b 1
)

if "%~2"=="" (
    set "SKILL_NAME=%DEFAULT_SKILL%"
) else (
    set "SKILL_NAME=%~2"
)

where npx >nul 2>nul
if errorlevel 1 (
    echo [错误] 未找到npx，请先安装Node.js后重试。
    exit /b 1
)

echo 项目路径: %PROJECT_PATH%
echo Skill名称: %SKILL_NAME%
echo 仓库: %REPO_URL%
echo 模式: 非交互
echo.

pushd "%PROJECT_PATH%"
if errorlevel 1 (
    echo [错误] 进入项目路径失败。
    exit /b 1
)

call npx skills add "%REPO_URL%" --skill "%SKILL_NAME%" --yes
set "INSTALL_EXIT=%ERRORLEVEL%"
popd

if not "%INSTALL_EXIT%"=="0" (
    echo.
    echo [错误] UI框架Skill安装失败，退出码 %INSTALL_EXIT%.
    exit /b %INSTALL_EXIT%
)

echo.
echo UI框架Skill安装成功。
exit /b 0
