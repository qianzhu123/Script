@echo off
setlocal

set "SERVER_DIR=D:\tools\Security\Reverse\Android\tools\jadx-mcp-server"
set "SERVER_SCRIPT=jadx_mcp_server.py"

echo StartJADX MCPservice(HTTPmode)...
echo serviceDirectory: %SERVER_DIR%
echo Endpoint: http://127.0.0.1:8651/mcp
echo.

if not exist "%SERVER_DIR%\%SERVER_SCRIPT%" (
 echo [ERROR] not foundservicescript: "%SERVER_DIR%\%SERVER_SCRIPT%".
 echo verifyInstallPath.
 pause
 exit /b 1
)

where uv >nul 2>&1
if errorlevel 1 (
 echo [ERROR] "uv" in PATH:.
 echo Installuv add it to PATHretry.
 pause
 exit /b 1
)

cd /d "%SERVER_DIR%"
uv --directory "%SERVER_DIR%" run "%SERVER_SCRIPT%" --http

if errorlevel 1 (
 echo.
 echo [ERROR] JADX MCPserviceStartFailed.
 pause
 exit /b 1
)

endlocal
