@echo off
cd /d "%~dp0"
if not exist "chat-db.env" goto configure
for %%F in ("chat-db.env") do if %%~zF EQU 0 goto configure
goto initialize
:configure
 powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Set-ChatDatabase.ps1" -PoolerHost aws-0-ap-southeast-1.pooler.supabase.com
 if errorlevel 1 goto done
:initialize
node "%~dp0scripts\initialize-chat-postgres.mjs"
:done
pause
