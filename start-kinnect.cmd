@echo off
cd /d "%~dp0"
set SECURE_COOKIES=1
"C:\Program Files\nodejs\node.exe" server.js
pause
