@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul

REM ============================================================
REM  FFmpeg Resolution Resizer
REM  Input source file + target resolution, output to same dir
REM  Output filename gets _replaced suffix, does not overwrite original
REM ============================================================

echo ===============================================
echo         FFmpeg 分辨率调整
echo ===============================================
echo.

where ffmpeg >nul 2>nul
if errorlevel 1 (
    echo [错误] 未找到ffmpeg，请将其加入PATH。
    goto :end
)

set "SRC="
set /p "SRC=请输入源文件路径: "
set "SRC=!SRC:"=!"
if not exist "!SRC!" (
    echo [错误] 文件未找到: !SRC!
    goto :end
)

echo.
echo 分辨率示例: 1920x1080  1280x720  854x480
echo 保持宽高比可用 -2 作为高度，如 1280x-2
echo.
set "RES="
set /p "RES=请输入目标分辨率(WxH): "
if "!RES!"=="" (
    echo [错误] 分辨率不能为空。
    goto :end
)
set "SCALE=!RES:x=:!"

for %%F in ("!SRC!") do (
    set "FDIR=%%~dpF"
    set "FNAME=%%~nF"
    set "FEXT=%%~xF"
)
set "OUT=!FDIR!!FNAME!_replaced!FEXT!"

echo.
echo 源文件:       !SRC!
echo 分辨率:       !RES!
echo 输出到:       !OUT!
echo.

set "CONFIRM="
set /p "CONFIRM=开始处理? (Y/N): "
if /i not "!CONFIRM!"=="Y" goto :cancel

echo.
echo [运行中] 正在调整分辨率...
ffmpeg -i "!SRC!" -vf "scale=!SCALE!" "!OUT!"
if errorlevel 1 (
    echo.
    echo [失败] 处理错误。
) else (
    echo.
    echo [完成] 输出: !OUT!
)
goto :end

:cancel
echo 已取消。

:end
echo.
endlocal
pause