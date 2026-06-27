@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul

set "WATCH_SECS=12"
if not "%~1"=="" set "WATCH_SECS=%~1"

where adb >nul 2>nul
if errorlevel 1 (
  echo [错误] 未在PATH中找到adb。
  goto :end
)

for /f %%S in ('adb get-state 2^>nul') do set "STATE=%%S"
if /I not "!STATE!"=="device" (
  echo [错误] 未检测到adb设备。
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
  echo [错误] 无法解析前台包名/类名。
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

echo 前台应用信息:
echo 包名   : !PKG!
echo 类名   : !CLS!
echo 原始   : !COMP!
if defined APPPID (
  echo PID     : !APPPID!
) else (
  echo PID     : ^(not found^)
)

echo JDWP    :
if not defined APPPID (
  echo   未知(PID缺失)
) else (
  echo   已跳过(某些设备adb jdwp可能阻塞)
  echo   需要时手动运行: adb jdwp
)

echo 转发   :
set "hasForward=0"
for /f "delims=" %%f in ('adb forward --list 2^>nul') do (
  echo   %%f
  set "hasForward=1"
)
if "!hasForward!"=="0" echo   (无)

if defined APPPID (
  echo 相关转发:
  set "hasRelated=0"
  for /f "delims=" %%f in ('adb forward --list 2^>nul') do (
    set "fwdLine=%%f"
    echo !fwdLine! | findstr /c:"jdwp:!APPPID!" >nul
    if not errorlevel 1 (
      echo   !fwdLine!
      set "hasRelated=1"
    )
  )
  if "!hasRelated!"=="0" echo   当前PID无相关转发。
)
echo.

if not defined APPPID (
  echo [信息] PID不可用，跳过SO分析。
  goto :end
)

set "APK="
for /f "tokens=2 delims=:" %%A in ('adb shell pm path !PKG! 2^>nul ^| findstr /B /C:"package:"') do (
  if not defined APK set "APK=%%A"
)

if not defined APK (
  echo [错误] 无法获取base.apk路径。
  goto :end
)

set "APPDIR=!APK:/base.apk=!"

echo ==== 应用lib目录下的候选SO ====
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
if not defined CAND_LIST echo (无或不可访问)
echo.

echo ==== 当前进程已加载SO(应用相关) ====
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
if not defined HIT_LIST echo (当前无)
echo.

echo ==== 当前屏幕最可能的SO ====
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
if not defined ANY_HIT echo 暂无直接匹配，操作当前屏幕并观察下方新增条目。
echo.

echo 正在监视新加载的应用SO，持续 !WATCH_SECS! 秒...
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
echo 完成。
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
