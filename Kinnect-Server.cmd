@echo off
setlocal
title Kinnect Server Manager

:menu
cls
echo ==============================
echo      Kinnect Server Manager
echo ==============================
echo.
echo   1. Start server
echo   2. Stop server
echo   3. Restart server
echo   4. Server status
echo   5. Exit
echo.
choice /C 12345 /N /M "Select: "

if errorlevel 5 goto done
if errorlevel 4 goto status
if errorlevel 3 goto restart
if errorlevel 2 goto stop
if errorlevel 1 goto start
goto menu

:start
set "ACTION=start"
goto run

:stop
set "ACTION=stop"
goto run

:restart
set "ACTION=restart"
goto run

:status
set "ACTION=status"
goto run

:run
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Kinnect-Server-Control.ps1" -Action "%ACTION%"
echo.
pause
goto menu

:done
endlocal
exit /b 0

