@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul

REM ============================================================
REM FFmpeg audio processor
REM Supports: Extract Audio / Volume Adjust / Speed Change / Audio Format Convert
REM Output to same dir, filename gets _replaced suffix, does not overwrite original
REM ============================================================

echo ===============================================
echo FFmpeg audio processor
echo ===============================================
echo.

where ffmpeg >nul 2>nul
if errorlevel 1 (
 echo [ERROR] ffmpeg was not found, add it to PATH.
 goto :end
)

set "SRC="
set /p "SRC=Enter Source filePath: "
set "SRC=!SRC:"=!"
if not exist "!SRC!" (
 echo [ERROR] filenot found: !SRC!
 goto :end
)

echo.
echo Select an action:
echo 1. extractaudio(video)
echo 2. volume 
echo 3. audio processor
echo 4. audioformatconvert
echo.
set "MODE="
set /p "MODE=Enter number(1-4): "

for %%F in ("!SRC!") do (
 set "FDIR=%%~dpF"
 set "FNAME=%%~nF"
 set "FEXT=%%~xF"
)

if "!MODE!"=="1" goto :extract
if "!MODE!"=="2" goto :volume
if "!MODE!"=="3" goto :speed
if "!MODE!"=="4" goto :convert
echo [ERROR] Invalidselect.
goto :end

:extract
set "AFMT="
set /p "AFMT=Outputaudioformat(mp3/aac/wav): "
set "AFMT=!AFMT:.=!"
if "!AFMT!"=="" set "AFMT=mp3"
set "OUT=!FDIR!!FNAME!_replaced.!AFMT!"
set CMD_EXT=ffmpeg -i !SRC! -vn !OUT!
goto :run

:volume
set VOL=
set /p VOL=volumemultiplier(0.5, 2.0): 
if "%VOL%"=="" (
 echo [ERROR] volumecannot be empty.
 goto :end
)
for %%F in ("%SRC%") do set OUT=%FDIR%%%FNAME_replaced%FEXT%
ffmpeg -i "%SRC%" -filter:a volume^=%VOL% "%OUT%"
if errorlevel 1 (
 echo.
 echo [FAILED] processing error.
) else (
 echo.
 echo [DONE] Output: %OUT%
)
goto :end

:speed 
set SPD=
set /p SPD=speedmultiplier(0.5-2.0, 1.5): 
if "%SPD%"=="" (
 echo [ERROR] speedcannot be empty.
 goto :end 
)
for %%F in ("%SRC%") do set OUT=%FDIR%%%FNAME_replaced%FEXT%

powershell -Command "$s=[double]'%SPD%'; if($s -gt 2){$r=$s; $f=''; while($r -gt 2){$f+='atempo='+([math]::Min(2,$r)).ToString('0.####')+','; $r/=([math]::Min(2,$r))} $f+='atempo='+$r.ToString('0.####'); Write-Host $f}else{Write-Host ('atempo='+$s.ToString('0.####'))}" > "%TEMP%\atempo.txt"

for /f %%L in (%TEMP%\atempo.txt) do set ATEMPO=%L

del "%TEMP%\atempo.txt" >nul 2>nul

ffmpeg -i "%SRC%" -filter:a "%ATEMPO%" "%OUT%"
if errorlevel 1 (
 echo.
 echo [FAILED] processing error.
) else (
 echo.
 echo [DONE] Output: %OUT%
)
goto :end

:convert 
set AFMT=
set /p AFMT= audioformat(mp3/wav/flac/aac): 
for %%A in ("%AFMT:.=%") do set AFMT=%AFMT:.=
if "%AFMT%"=="" (
 echo [ERROR] formatcannot be empty.
 goto :end 
)
for %%F in ("%SRC%") do set OUT=%FDIR%%%FNAME_replaced.%AFMT%
ffmpeg -i "%SRC%" "%OUT%"
if errorlevel 1 (
 echo.
 echo [FAILED] processing error.
) else (
 echo.
 echo [DONE] Output: %OUT%
)
goto :end

:run 
echo.
echo Source file: !SRC!
echo Output: !OUT!
echo.

set CONFIRM=
set /p CONFIRM=starting? (Y/N): 
if /i not "%CONFIRM%"=="Y" goto :Cancelled.

echo.
echo [RUNNING]...
!CMD_EXT!
if errorlevel 1 (
 echo.
 echo [FAILED] processing error.
) else (
 echo.
 echo [DONE] Output: !OUT!
)
goto :end

:Cancelled. 
echo Cancelled.led.

:end 
echo.
endlocal 
pause