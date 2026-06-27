@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul

REM ============================================================
REM  FFmpeg 帧率与码率调整
REM  Input source file, optional FPS/video bitrate/audio bitrate params
REM  Output to same dir, filename gets _replaced suffix, does not overwrite original
REM ============================================================

echo ===============================================
echo     FFmpeg 帧率与码率调整
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
echo 以下字段可留空(直接回车跳过)
echo.
set "FPS="
set /p "FPS=帧率(如 30/60): "
set "VB="
set /p "VB=视频码率(如 2M/4000k): "
set "AB="
set /p "AB=音频码率(如 128k/192k): "

set "ARGS="
if not "!FPS!"=="" set "ARGS=!ARGS! -r !FPS!"
if not "!VB!"=="" set "ARGS=!ARGS! -b:v !VB!"
if not "!AB!"=="" set "ARGS=!ARGS! -b:a !AB!"

if "!ARGS!"=="" (
    echo [错误] 至少需要一个参数。
    goto :end
)

for %%F in ("!SRC!") do (
    set "FDIR=%%~dpF"
    set "FNAME=%%~nF"
    set "FEXT=%%~xF"
)
set "OUT=!FDIR!!FNAME!_replaced!FEXT!"

echo.
echo 源文件:   !SRC!
echo 参数:     !ARGS!
echo 输出到:   !OUT!
echo.

set "CONFIRM="
set /p "CONFIRM=开始处理? (Y/N): "
if /i not "!CONFIRM!"=="Y" goto :cancel

echo.
echo [运行中] 正在处理...
ffmpeg -i "!SRC!"!ARGS! "!OUT!"
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