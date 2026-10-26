@echo off
rem Dừng máy chủ Kinnect (cổng 3000 và 3306 cho các bản cũ) và Cloudflare Tunnel đang chạy ẩn.
for /f "tokens=5" %%p in ('netstat -ano ^| findstr ":3000 " ^| findstr LISTENING') do taskkill /PID %%p /F
for /f "tokens=5" %%p in ('netstat -ano ^| findstr ":3306 " ^| findstr LISTENING') do taskkill /PID %%p /F
taskkill /IM cloudflared.exe /F
