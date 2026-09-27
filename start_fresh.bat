@echo off
cd /d D:\code\myweb\script-studio
set SCRIPT_STUDIO_OUTPUT_ENCODING=gbk
start "DailyWeb" cmd /k "node server.js"
