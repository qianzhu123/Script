@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul
title URL检测 - 扩展版

set "MODE=%~1"
set "TARGET_URL=%~2"

if /I "%MODE%"=="--summary-test" goto run_checks

echo ============================================================
echo URL安全检测 - 扩展版
echo 静默扫描模式，最终结论将在本窗口显示。
echo ============================================================
echo.
set /p "TARGET_URL=请粘贴完整URL并按回车: "

:run_checks
if "%TARGET_URL%"=="" (
    set "URL_RESULT=Invalid"
    set "STRUCTURE_RESULT=Unknown"
    set "DNS_RESULT=Not Run"
    set "HTTP_RESULT=Not Run"
    set "TLS_RESULT=Not Run"
    set "WHOIS_RESULT=Not Run"
    set "PING_RESULT=Not Run"
    set "TRACE_RESULT=Not Run"
    set "OVERALL_RESULT=High"
    goto show_or_spawn
)

for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "'%TARGET_URL%'.Trim()"`) do set "TARGET_URL=%%A"

set "PARSED_HOST="
set "PARSED_SCHEME="
set "PARSED_PORT="

for /f "usebackq tokens=1-3 delims=|" %%A in (`powershell -NoProfile -Command "$ErrorActionPreference='Stop'; try { $u=[Uri]'%TARGET_URL%'; if (-not $u.Host) { throw 'Missing host' }; $port = if ($u.IsDefaultPort) { '' } else { [string]$u.Port }; '{0}|{1}|{2}' -f $u.Scheme, $u.Host, $port } catch { exit 1 }" 2^>nul`) do (
    set "PARSED_SCHEME=%%A"
    set "PARSED_HOST=%%B"
    set "PARSED_PORT=%%C"
)

if not defined PARSED_HOST (
    set "URL_RESULT=Invalid"
    set "STRUCTURE_RESULT=Unknown"
    set "DNS_RESULT=Not Run"
    set "HTTP_RESULT=Not Run"
    set "TLS_RESULT=Not Run"
    set "WHOIS_RESULT=Not Run"
    set "PING_RESULT=Not Run"
    set "TRACE_RESULT=Not Run"
    set "OVERALL_RESULT=High"
    goto show_or_spawn
)

set "URL_RESULT=Valid"

if not defined PARSED_PORT (
    if /I "%PARSED_SCHEME%"=="https" (
        set "PARSED_PORT=443"
    ) else if /I "%PARSED_SCHEME%"=="http" (
        set "PARSED_PORT=80"
    )
)

set "STRUCTURE_RESULT=Clean"
powershell -NoProfile -Command ^
    "$u=[Uri]'%TARGET_URL%';" ^
    "$bad = $false;" ^
    "if ($u.Host -match 'xn--') { $bad = $true };" ^
    "if ($u.UserInfo) { $bad = $true };" ^
    "if ($u.Host -match '^\d{1,3}(\.\d{1,3}){3}$') { $bad = $true };" ^
    "if ($u.AbsoluteUri.Length -gt 200) { $bad = $true };" ^
    "if ($u.Query.Length -gt 120) { $bad = $true };" ^
    "if ($u.Scheme -notin @('http','https')) { $bad = $true };" ^
    "if ($bad) { exit 1 }" >nul 2>nul
if errorlevel 1 set "STRUCTURE_RESULT=Suspicious"

set "DNS_RESULT=Failed"
powershell -NoProfile -Command ^
    "try { [System.Net.Dns]::GetHostAddresses('%PARSED_HOST%') | Out-Null; exit 0 } catch { exit 1 }" >nul 2>nul
if not errorlevel 1 set "DNS_RESULT=Resolved"

set "HTTP_RESULT=Failed"
powershell -NoProfile -Command ^
    "try {" ^
    "  $request = [System.Net.HttpWebRequest]::Create('%TARGET_URL%');" ^
    "  $request.Method = 'HEAD';" ^
    "  $request.AllowAutoRedirect = $true;" ^
    "  $request.Timeout = 15000;" ^
    "  $request.UserAgent = 'URL-Inspector/1.0';" ^
    "  $response = $request.GetResponse();" ^
    "  if ($response) { $response.Close(); exit 0 } else { exit 1 }" ^
    "} catch { exit 1 }" >nul 2>nul
if not errorlevel 1 set "HTTP_RESULT=Reachable"

if /I "%PARSED_SCHEME%"=="https" (
    set "TLS_RESULT=Failed"
    powershell -NoProfile -Command ^
        "$ErrorActionPreference='Stop';" ^
        "try {" ^
        "  $tcp = New-Object Net.Sockets.TcpClient('%PARSED_HOST%', %PARSED_PORT%);" ^
        "  try {" ^
        "    $ssl = New-Object Net.Security.SslStream($tcp.GetStream(), $false, ({ $true }));" ^
        "    $ssl.AuthenticateAsClient('%PARSED_HOST%');" ^
        "    if ($ssl.RemoteCertificate) { exit 0 } else { exit 1 }" ^
        "  } finally {" ^
        "    if ($ssl) { $ssl.Dispose() }" ^
        "    $tcp.Close()" ^
        "  }" ^
        "} catch { exit 1 }" >nul 2>nul
    if not errorlevel 1 set "TLS_RESULT=Available"
) else (
    set "TLS_RESULT=Skipped"
)

set "WHOIS_RESULT=Command Missing"
where.exe whois >nul 2>nul
if not errorlevel 1 (
    set "WHOIS_RESULT=Failed"
    whois %PARSED_HOST% >nul 2>nul
    if not errorlevel 1 set "WHOIS_RESULT=Available"
)

set "PING_RESULT=Failed"
where.exe ping >nul 2>nul
if not errorlevel 1 (
    ping -n 1 %PARSED_HOST% >nul 2>nul
    if not errorlevel 1 set "PING_RESULT=Reachable"
) else (
    set "PING_RESULT=Command Missing"
)

set "TRACE_RESULT=Failed"
where.exe tracert >nul 2>nul
if not errorlevel 1 (
    tracert -d -h 4 %PARSED_HOST% >nul 2>nul
    if not errorlevel 1 set "TRACE_RESULT=Reachable"
) else (
    set "TRACE_RESULT=Command Missing"
)

set /a RISK_SCORE=0
if /I "%URL_RESULT%"=="Invalid" set /a RISK_SCORE+=3
if /I "%STRUCTURE_RESULT%"=="Suspicious" set /a RISK_SCORE+=2
if /I "%DNS_RESULT%"=="Failed" set /a RISK_SCORE+=2
if /I "%HTTP_RESULT%"=="Failed" set /a RISK_SCORE+=1
if /I "%TLS_RESULT%"=="Failed" set /a RISK_SCORE+=1
if /I "%WHOIS_RESULT%"=="Command Missing" set /a RISK_SCORE+=1
if /I "%WHOIS_RESULT%"=="Failed" set /a RISK_SCORE+=1

if %RISK_SCORE% GEQ 5 (
    set "OVERALL_RESULT=High"
) else if %RISK_SCORE% GEQ 3 (
    set "OVERALL_RESULT=Medium"
) else (
    set "OVERALL_RESULT=Low"
)

:show_or_spawn
if /I "%MODE%"=="--summary-test" goto print_summary

goto display_summary

:print_summary
echo URL结果: %URL_RESULT%
echo 结构结果: %STRUCTURE_RESULT%
echo DNS结果: %DNS_RESULT%
echo HTTP结果: %HTTP_RESULT%
echo TLS结果: %TLS_RESULT%
echo WHOIS结果: %WHOIS_RESULT%
echo Ping结果: %PING_RESULT%
echo 路由结果: %TRACE_RESULT%
echo 综合结果: %OVERALL_RESULT%
exit /b 0

:display_summary
title URL安全检测 - 结果
echo ============================
echo URL安全检测 - 结果
echo ============================
echo.
echo URL结果: %URL_RESULT%
echo 结构结果: %STRUCTURE_RESULT%
echo DNS结果: %DNS_RESULT%
echo HTTP结果: %HTTP_RESULT%
echo TLS结果: %TLS_RESULT%
echo WHOIS结果: %WHOIS_RESULT%
echo Ping结果: %PING_RESULT%
echo 路由结果: %TRACE_RESULT%
echo 综合结果: %OVERALL_RESULT%
echo.
echo 按任意键退出 . . .
pause >nul
exit /b 0
