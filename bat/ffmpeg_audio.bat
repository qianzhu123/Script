@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul

REM ============================================================
REM  FFmpeg 音频处理器
REM  Supports: Extract Audio / Volume Adjust / Speed Change / Audio Format Convert
REM  Output to same dir, filename gets _replaced suffix, does not overwrite original
REM ============================================================

echo ===============================================
echo         FFmpeg 音频处理器
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
echo 请选择操作:
echo   1. 提取音频(从视频中)
echo   2. 音量调整
echo   3. 音频变速
echo   4. 音频格式转换
echo.
set "MODE="
set /p "MODE=请输入编号(1-4): "

for %%F in ("!SRC!") do (
    set "FDIR=%%~dpF"
    set "FNAME=%%~nF"
    set "FEXT=%%~xF"
)

if "!MODE!"=="1" goto :extract
if "!MODE!"=="2" goto :volume
if "!MODE!"=="3" goto :speed
if "!MODE!"=="4" goto :convert
echo [错误] 无效选择。
goto :end

:extract
set "AFMT="
set /p "AFMT=输出音频格式(如 mp3/aac/wav): "
set "AFMT=!AFMT:.=!"
if "!AFMT!"=="" set "AFMT=mp3"
set "OUT=!FDIR!!FNAME!_replaced.!AFMT!"
set CMD_EXT=ffmpeg -i !SRC! -vn !OUT!
goto :run

:volume
set VOL=
set /p VOL=音量倍数(如 0.5为一半, 2.0为两倍): 
if "%VOL%"=="" (
    echo [错误] 音量不能为空。
    goto :end
)
for %%F in ("%SRC%") do set OUT=%FDIR%%%FNAME_replaced%FEXT%
ffmpeg -i "%SRC%" -filter:a volume^=%VOL% "%OUT%"
if errorlevel 1 (
    echo.
    echo [失败] 处理错误。
) else (
    echo.
    echo [完成] 输出: %OUT%
)
goto :end

:speed  
set SPD=
set /p SPD=速度倍数(0.5-2.0, 如1.5): 
if "%SPD%"=="" (
    echo [错误] 速度不能为空。
    goto :end  
)
for %%F in ("%SRC%") do set OUT=%FDIR%%%FNAME_replaced%FEXT%

powershell -Command "$s=[double]'%SPD%'; if($s -gt 2){$r=$s; $f=''; while($r -gt 2){$f+='atempo='+([math]::Min(2,$r)).ToString('0.####')+','; $r/=([math]::Min(2,$r))} $f+='atempo='+$r.ToString('0.####'); Write-Host $f}else{Write-Host ('atempo='+$s.ToString('0.####'))}" > "%TEMP%\atempo.txt"

for /f %%L in (%TEMP%\atempo.txt) do set ATEMPO=%L

del "%TEMP%\atempo.txt" >nul 2>nul

ffmpeg -i "%SRC%" -filter:a "%ATEMPO%" "%OUT%"
if errorlevel 1 (
    echo.
    echo [失败] 处理错误。
) else (
    echo.
    echo [完成] 输出: %OUT%
)
goto :end

:convert  
set AFMT=
set /p AFMT=目标音频格式(如 mp3/wav/flac/aac): 
for %%A in ("%AFMT:.=%") do set AFMT=%AFMT:.=
if "%AFMT%"=="" (
    echo [错误] 格式不能为空。
    goto :end  
)
for %%F in ("%SRC%") do set OUT=%FDIR%%%FNAME_replaced.%AFMT%
ffmpeg -i "%SRC%" "%OUT%"
if errorlevel 1 (
    echo.
    echo [失败] 处理错误。
) else (
    echo.
    echo [完成] 输出: %OUT%
)
goto :end

:run  
echo.
echo 源文件:   !SRC!
echo 输出到:   !OUT!
echo.

set CONFIRM=
set /p CONFIRM=开始处理? (Y/N): 
if /i not "%CONFIRM%"=="Y" goto :cancel

echo.
echo [运行中] 正在处理...
!CMD_EXT!
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