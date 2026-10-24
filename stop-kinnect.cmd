@echo off
rem Dừng máy chủ Kinnect (cổng 3000) và Cloudflare Tunnel đang chạy ẩn.
for /f "tokens=5" %%p in ('netstat -ano ^| findstr ":3000 " ^| findstr LISTENING') do taskkill /PID %%p /F
taskkill /IM cloudflared.exe /F
