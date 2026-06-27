@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul

set "DESKTOP_DIR=%USERPROFILE%\Desktop"
set "TEMP_DIR=%DESKTOP_DIR%\convert-image-temp"
set "PS1=%~dp0..\ps1\Convert-Image.ps1"

set "SRC=%~1"
set "FMT=%~2"

if not defined SRC (
    echo 请输入源图片路径:
    set /p "SRC=> "
)

if not defined FMT (
    call :selectFormat
)

if not defined SRC goto :usage
if not defined FMT goto :usage

set "SRC=%SRC:"=%"
set "FMT=%FMT:"=%"

if not exist "%SRC%" goto :notfound
if not exist "%PS1%" goto :missingps1

for %%F in ("%SRC%") do set "SRC_EXT=%%~xF"
set "SRC_EXT=%SRC_EXT:~1%"

if /I "%SRC_EXT%"=="jpg" set "SRC_EXT=jpeg"
if /I "%FMT%"=="jpg" set "FMT=jpeg"
if /I "%FMT%"=="jpeg" set "FMT=jpeg"
if /I "%FMT%"=="png" set "FMT=png"
if /I "%FMT%"=="bmp" set "FMT=bmp"
if /I "%FMT%"=="gif" set "FMT=gif"
if /I "%FMT%"=="tiff" set "FMT=tiff"
if /I "%FMT%"=="ico" set "FMT=ico"

if /I not "%FMT%"=="jpeg" if /I not "%FMT%"=="png" if /I not "%FMT%"=="bmp" if /I not "%FMT%"=="gif" if /I not "%FMT%"=="tiff" if /I not "%FMT%"=="ico" goto :badformat
if /I "%SRC_EXT%"=="%FMT%" goto :sameformat

if not exist "%TEMP_DIR%" mkdir "%TEMP_DIR%" >nul 2>&1

echo.
echo 开始转换...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -ImagePath "%SRC%" -TargetFormat "%FMT%"
set "RC=%errorlevel%"

if exist "%TEMP_DIR%" rmdir /s /q "%TEMP_DIR%" >nul 2>&1

if "%RC%"=="0" (
    echo.
    echo [完成] 转换完成。
) else (
    echo.
    echo [错误] 转换失败。
)
goto :pauseexit

:selectFormat
echo.
echo 请选择目标格式:
echo   [1] jpg
echo   [2] jpeg
echo   [3] png
echo   [4] bmp
echo   [5] gif
echo   [6] tiff
echo   [7] ico
set /p "FMT=> "
if "%FMT%"=="1" set "FMT=jpg"
if "%FMT%"=="2" set "FMT=jpeg"
if "%FMT%"=="3" set "FMT=png"
if "%FMT%"=="4" set "FMT=bmp"
if "%FMT%"=="5" set "FMT=gif"
if "%FMT%"=="6" set "FMT=tiff"
if "%FMT%"=="7" set "FMT=ico"
exit /b 0

:usage
echo [错误] 用法: %~nx0 "image_path" target_format
echo [错误] 支持的格式: jpg jpeg png bmp gif tiff ico
set "RC=1"
goto :pauseexit

:notfound
echo [错误] 源文件未找到: %SRC%
set "RC=1"
goto :pauseexit

:missingps1
echo [错误] 缺少PowerShell脚本: %PS1%
set "RC=1"
goto :pauseexit

:badformat
echo [错误] 不支持的目标格式: %FMT%
echo [错误] 支持的格式: jpg jpeg png bmp gif tiff ico
set "RC=1"
goto :pauseexit

:sameformat
echo [错误] 源文件已经是该格式。
set "RC=1"
goto :pauseexit

:pauseexit
echo.
pause >nul
endlocal & exit /b %RC%

