@echo off
cd /d D:\code\myweb\daily
set SCRIPT_STUDIO_OUTPUT_ENCODING=gbk
start "DailyWeb" cmd /k "node server.js"
