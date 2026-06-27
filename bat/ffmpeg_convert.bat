@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul

REM ============================================================
REM  FFmpeg Format Converter
REM  Input source file path + target format, output to same dir
REM  Output filename gets _replaced suffix, does not overwrite original
REM ============================================================

echo ===============================================
echo         FFmpeg 格式转换器
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

set "TARGET="
set /p "TARGET=请输入目标格式(如 mp4/mkv/avi/mov/mp3): "
set "TARGET=!TARGET:.=!"
if "!TARGET!"=="" (
    echo [错误] 目标格式不能为空。
    goto :end
)

for %%F in ("!SRC!") do (
    set "FDIR=%%~dpF"
    set "FNAME=%%~nF"
)
set "OUT=!FDIR!!FNAME!_replaced.!TARGET!"

echo.
echo 源文件:   !SRC!
echo 输出到:   !OUT!
echo.

set "CONFIRM="
set /p "CONFIRM=开始转换? (Y/N): "
if /i not "!CONFIRM!"=="Y" goto :cancel

echo.
echo [运行中] 正在转换...
ffmpeg -i "!SRC!" "!OUT!"
if errorlevel 1 (
    echo.
    echo [失败] 转换错误，请检查格式兼容性。
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