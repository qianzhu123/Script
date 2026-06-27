@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul
title APKTool 自动编译/反编译 + 签名

echo ==============================================
echo      APKTool 自动编译/反编译 + 签名
echo ==============================================
echo.

if not "%~1"=="" (
  set "INPUT_PATH=%~1"
  echo [信息] 接收到拖放/参数输入。
) else (
  set /p INPUT_PATH=请粘贴APK文件或项目文件夹的完整路径: 
)

if "%INPUT_PATH%"=="" (
  echo [错误] 未提供路径。
  goto :end
)

rem Remove all quote characters
set "TARGET=%INPUT_PATH:"=%"

rem Trim leading spaces
for /f "tokens=* delims= " %%A in ("!TARGET!") do set "TARGET=%%A"
rem Trim trailing spaces
:trim_tail
if "!TARGET:~-1!"==" " set "TARGET=!TARGET:~0,-1!" & goto :trim_tail

echo [信息] 规范化输入: "!TARGET!"

if not exist "!TARGET!" (
  echo [错误] 路径不存在:
  echo "!TARGET!"
  goto :end
)

where apktool >nul 2>&1
if errorlevel 1 (
  echo [错误] 未在PATH中找到apktool命令。
  goto :end
)

for %%A in ("!TARGET!") do set "ATTR=%%~aA"
if /I "!ATTR:~0,1!"=="d" (
  echo [信息] 检测到输入类型: 文件夹
  goto :handle_folder
) else (
  echo [信息] 检测到输入类型: 文件
  goto :handle_file
)

:handle_file
for %%I in ("!TARGET!") do (
  set "IN_NAME=%%~nI"
  set "IN_DIR=%%~dpI"
  set "IN_EXT=%%~xI"
)

if /I not "!IN_EXT!"==".apk" (
  echo [警告] 文件扩展名为 "!IN_EXT!". 仍将尝试作为APK容器处理。
)

set "OUT_DIR=!IN_DIR!!IN_NAME!_src"

echo.
echo [信息] 正在反编译APK...
echo [信息] 输入 : "!TARGET!"
echo [INFO] Output: "!OUT_DIR!"

call apktool d -f "!TARGET!" -o "!OUT_DIR!"
if errorlevel 1 (
  echo [错误] 反编译失败。
  goto :end
)

echo [完成] 反编译完成。
echo [RESULT] "!OUT_DIR!"
call :analyze_decompiled "!OUT_DIR!"
goto :end

:handle_folder
where keytool >nul 2>&1
if errorlevel 1 (
  echo [错误] 未在PATH中找到keytool。
  goto :end
)

where apksigner >nul 2>&1
if errorlevel 1 (
  echo [错误] 未在PATH中找到apksigner。
  goto :end
)

for %%I in ("!TARGET!") do (
  set "FOLDER_NAME=%%~nxI"
  set "PARENT_DIR=%%~dpI"
)

set "OUT_APK=!PARENT_DIR!!FOLDER_NAME!.apk"

set "KEYSTORE=%USERPROFILE%\Desktop\Codex_Apk_Signing_Key.jks"
set "KEY_ALIAS=codexkey"
set "KEYSTORE_PASS=codex123456"
set "KEY_PASS=codex123456"

if not exist "!KEYSTORE!" (
  echo [信息] 未找到密钥库，正在创建一次性本地密钥库...
  keytool -genkeypair -v -keystore "!KEYSTORE!" -storepass "!KEYSTORE_PASS!" -alias "!KEY_ALIAS!" -keypass "!KEY_PASS!" -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Codex, OU=Local, O=Local, L=Local, S=Local, C=CN"
  if errorlevel 1 (
    echo [错误] 创建密钥库失败。
    goto :end
  )
)

if exist "!OUT_APK!" del /q "!OUT_APK!" >nul 2>&1

echo.
echo [信息] 正在从文件夹重新构建APK...
echo [信息] 输入 : "!TARGET!"
echo [INFO] Final : "!OUT_APK!"

call apktool b "!TARGET!" -o "!OUT_APK!"
if errorlevel 1 (
  echo [错误] 重新构建失败。
  goto :end
)

echo [信息] 正在签名APK...
if exist "!OUT_APK!.idsig" del /q "!OUT_APK!.idsig" >nul 2>&1
call apksigner sign --v4-signing-enabled false --ks "!KEYSTORE!" --ks-pass pass:!KEYSTORE_PASS! --ks-key-alias "!KEY_ALIAS!" --key-pass pass:!KEY_PASS! "!OUT_APK!"
if errorlevel 1 (
  echo [错误] 签名失败。
  goto :end
)

echo [信息] 正在验证签名...
call apksigner verify -v "!OUT_APK!"
if errorlevel 1 (
  echo [错误] 签名验证失败。
  goto :end
)
if exist "!OUT_APK!.idsig" del /q "!OUT_APK!.idsig" >nul 2>&1

echo [完成] 重新构建 + 签名完成。
echo [RESULT] "!OUT_APK!"

echo [信息] 可选安装命令:
echo adb install -r "!OUT_APK!"
goto :end

:analyze_decompiled
set "SCAN_DIR=%~1"
if "%SCAN_DIR%"=="" goto :eof
if not exist "%SCAN_DIR%\AndroidManifest.xml" (
  echo [警告] 未找到AndroidManifest.xml，跳过清单分析。
  goto :eof
)

for %%I in ("%SCAN_DIR%") do (
  set "SCAN_NAME=%%~nxI"
  set "SCAN_PARENT=%%~dpI"
)

set "REPORT_DIR=!SCAN_PARENT!scan_!SCAN_NAME!"
if exist "!REPORT_DIR!" rd /s /q "!REPORT_DIR!" >nul 2>&1
mkdir "!REPORT_DIR!" >nul 2>&1

echo.
echo [信息] 正在运行清单分析...
echo [信息] 报告文件夹: "!REPORT_DIR!"

rem 1) Permission lines (same style as your sample)
findstr /n /i /c:"uses-permission" /c:"permission-group" "%SCAN_DIR%\AndroidManifest.xml" > "!REPORT_DIR!\permissions_lines.txt"

rem 2) Single launcher entry activity (only one class name)
powershell -NoProfile -Command "$m='%SCAN_DIR%\AndroidManifest.xml'; [xml]$x=Get-Content -LiteralPath $m; $n=New-Object System.Xml.XmlNamespaceManager($x.NameTable); $n.AddNamespace('a','http://schemas.android.com/apk/res/android'); $entry=$null; foreach($a in $x.manifest.application.activity){ foreach($f in $a.'intent-filter'){ $hasMain=$false; $hasLauncher=$false; foreach($ac in $f.action){ if($ac.GetAttribute('name','http://schemas.android.com/apk/res/android') -eq 'android.intent.action.MAIN'){ $hasMain=$true } }; foreach($c in $f.category){ if($c.GetAttribute('name','http://schemas.android.com/apk/res/android') -eq 'android.intent.category.LAUNCHER'){ $hasLauncher=$true } }; if($hasMain -and $hasLauncher){ $entry=$a.GetAttribute('name','http://schemas.android.com/apk/res/android'); break } }; if($entry){ break } }; if($entry){ $entry } else { 'NOT_FOUND' }" > "!REPORT_DIR!\entry_activity.txt"

rem 3) Key permission judgement (common sensitive permissions)
findstr /n /i /c:"android.permission.READ_SMS" /c:"android.permission.SEND_SMS" /c:"android.permission.RECEIVE_SMS" /c:"android.permission.READ_CONTACTS" /c:"android.permission.WRITE_CONTACTS" /c:"android.permission.READ_CALL_LOG" /c:"android.permission.WRITE_CALL_LOG" /c:"android.permission.RECORD_AUDIO" /c:"android.permission.CAMERA" /c:"android.permission.ACCESS_FINE_LOCATION" /c:"android.permission.ACCESS_COARSE_LOCATION" /c:"android.permission.READ_EXTERNAL_STORAGE" /c:"android.permission.WRITE_EXTERNAL_STORAGE" /c:"android.permission.MANAGE_EXTERNAL_STORAGE" /c:"android.permission.REQUEST_INSTALL_PACKAGES" /c:"android.permission.SYSTEM_ALERT_WINDOW" /c:"android.permission.QUERY_ALL_PACKAGES" /c:"android.permission.BIND_ACCESSIBILITY_SERVICE" /c:"android.permission.POST_NOTIFICATIONS" "%SCAN_DIR%\AndroidManifest.xml" > "!REPORT_DIR!\key_permissions.txt"

echo [完成] 清单分析完成。
echo [REPORT] "!REPORT_DIR!\permissions_lines.txt"
echo [REPORT] "!REPORT_DIR!\entry_activity.txt"
echo [REPORT] "!REPORT_DIR!\key_permissions.txt"
goto :eof

:end
echo.
echo [信息] 任务完成，按任意键关闭窗口...
pause >nul
endlocal
exit /b 0

