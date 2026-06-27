@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul

set "WATCH_SECS=12"
if not "%~1"=="" set "WATCH_SECS=%~1"

where adb >nul 2>nul
if errorlevel 1 (
 echo [ERROR] in PATH: adb.
 goto :end
)

for /f %%S in ('adb get-state 2^>nul') do set "STATE=%%S"
if /I not "!STATE!"=="device" (
 echo [ERROR] check adbdevice.
 goto :end
)

set "COMP="
for /f "usebackq delims=" %%L in (`adb shell dumpsys activity 2^>nul ^| findstr /R /C:"ResumedActivity" /C:"mResumedActivity" /C:"topResumedActivity" /C:"mFocusedActivity"`) do (
 if not defined COMP call :TryExtractComp "%%L"
)
if not defined COMP (
 for /f "usebackq delims=" %%L in (`adb shell dumpsys window 2^>nul ^| findstr /R /C:"mFocusedApp" /C:"mCurrentFocus"`) do (
 if not defined COMP call :TryExtractComp "%%L"
)
)

if not defined COMP (
 echo [ERROR] cannot parseforegroundpackage/class.
 goto :end
)

for /f "tokens=1,2 delims=/" %%a in ("!COMP!") do (
 set "PKG=%%a"
 set "CLS=%%b"
)
if "!CLS:~0,1!"=="." set "CLS=!PKG!!CLS!"

set "APPPID="
for /f %%P in ('adb shell pidof -s !PKG! 2^>nul') do (
 if not defined APPPID set "APPPID=%%P"
)

if not defined APPPID (
 for /f "usebackq delims=" %%L in (`adb shell ps -A 2^>nul ^| findstr /I /C:" !PKG!"`) do (
 if not defined APPPID call :FindFirstNumber "%%L"
)
)

echo foreground appINFO:
echo package : !PKG!
echo class : !CLS!
echo raw : !COMP!
if defined APPPID (
 echo PID : !APPPID!
) else (
 echo PID : ^(not found^)
)

echo JDWP :
if not defined APPPID (
 echo unknown(PIDmissing)
) else (
 echo skip(deviceadb jdwp block)
 echo manualRun: adb jdwp
)

echo forward :
set "hasForward=0"
for /f "delims=" %%f in ('adb forward --list 2^>nul') do (
 echo %%f
 set "hasForward=1"
)
if "!hasForward!"=="0" echo ()

if defined APPPID (
 echo relatedforward:
 set "hasRelated=0"
 for /f "delims=" %%f in ('adb forward --list 2^>nul') do (
 set "fwdLine=%%f"
 echo !fwdLine! | findstr /c:"jdwp:!APPPID!" >nul
 if not errorlevel 1 (
 echo !fwdLine!
 set "hasRelated=1"
)
)
 if "!hasRelated!"=="0" echo currentPID relatedforward.
)
echo.

if not defined APPPID (
 echo [INFO] PIDunavailable,skipSOanalysis.
 goto :end
)

set "APK="
for /f "tokens=2 delims=:" %%A in ('adb shell pm path !PKG! 2^>nul ^| findstr /B /C:"package:"') do (
 if not defined APK set "APK=%%A"
)

if not defined APK (
 echo [ERROR] cannot getbase.apkPath.
 goto :end
)

set "APPDIR=!APK:/base.apk=!"

echo ==== applicationlibdirectorycandidate SO files ====
set "CAND_LIST="
for /f "usebackq delims=" %%S in (`adb shell ls !APPDIR!/lib/arm/*.so 2^>nul`) do (
 call :TailName "%%S"
 if defined TAIL (
 echo !TAIL!
 set "CAND_LIST=!CAND_LIST!;!TAIL!;"
)
)
for /f "usebackq delims=" %%S in (`adb shell ls !APPDIR!/lib/armeabi-v7a/*.so 2^>nul`) do (
 call :TailName "%%S"
 if defined TAIL (
 echo !TAIL!
 set "CAND_LIST=!CAND_LIST!;!TAIL!;"
)
)
if not defined CAND_LIST echo ()
echo.

echo ==== currentprocessloaded SO files(applicationrelated) ====
set "HIT_LIST="
for /f "usebackq delims=" %%M in (`adb shell su -c "cat /proc/!APPPID!/maps" 2^>nul ^| findstr /R "\.so"`) do (
 set "LINE=%%M"
 echo !LINE! | findstr /I /C:"!PKG!" /C:"base.apk!lib/" >nul
 if not errorlevel 1 (
 call :TailName "!LINE!"
 if defined TAIL (
 echo !TAIL!
 set "HIT_LIST=!HIT_LIST!;!TAIL!;"
)
)
)
if not defined HIT_LIST echo (current)
echo.

echo ==== currentscreen SO ====
set "ANY_HIT="
for %%N in (libqhreadercutils.so libqhapplocation.so libAisound.so) do (
 echo !HIT_LIST! | findstr /I /C:";%%N;" >nul
 if not errorlevel 1 (
 echo %%N
 set "ANY_HIT=1"
)
)
if not defined ANY_HIT (
 for /f "tokens=2 delims=;" %%X in ("!HIT_LIST!") do (
 if not defined ANY_HIT (
 echo %%X
 set "ANY_HIT=1"
)
)
)
if not defined ANY_HIT echo matches, currentscreen new entries.
echo.

echo watch applicationSO,for !WATCH_SECS! seconds...
set /a i=0
:watch_loop
if !i! geq !WATCH_SECS! goto :done
set /a i+=1

set "PID_NOW="
for /f %%P in ('adb shell pidof -s !PKG! 2^>nul') do (
 if not defined PID_NOW set "PID_NOW=%%P"
)
if defined PID_NOW (
 for /f "usebackq delims=" %%M in (`adb shell su -c "cat /proc/!PID_NOW!/maps" 2^>nul ^| findstr /R "\.so"`) do (
 set "LINE=%%M"
 echo !LINE! | findstr /I /C:"!PKG!" /C:"base.apk!lib/" >nul
 if not errorlevel 1 (
 call :TailName "!LINE!"
 if defined TAIL (
 echo !HIT_LIST! | findstr /I /C:";!TAIL!;" >nul
 if errorlevel 1 (
 set "HIT_LIST=!HIT_LIST!;!TAIL!;"
 echo [NEW] !TAIL!
)
)
)
)
)

timeout /t 1 >nul
goto :watch_loop

:done
echo.
echo Done.
goto :end

:TryExtractComp
set "LINE=%~1"
for %%T in (!LINE!) do (
 echo %%T| findstr /R "^[A-Za-z0-9_.$][A-Za-z0-9_.$]*/[A-Za-z0-9_.$][A-Za-z0-9_.$]*$" >nul
 if not errorlevel 1 (
 set "COMP=%%T"
 goto :eof
)
)
goto :eof

:FindFirstNumber
set "LINE=%~1"
for %%T in (!LINE!) do (
 echo %%T| findstr /R "^[0-9][0-9]*$" >nul
 if not errorlevel 1 (
 set "APPPID=%%T"
 goto :eof
)
)
goto :eof

:TailName
set "TAIL="
set "TXT=%~1"
for %%B in (!TXT!) do set "TAIL=%%~nxB"
if defined TAIL (
 echo !TAIL!| findstr /R /I "\.so$" >nul
 if errorlevel 1 set "TAIL="
)
goto :eof

:end
echo.
pause
endlocal
