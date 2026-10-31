@echo off
cd /d "D:\Codex\Kinnect"
"D:\Codex\2026-10-24\c-kinnect-s-theo-h-ng\work\tools\cloudflared.exe" tunnel --config "D:\Codex\Kinnect\scripts\windows-tunnel.yml" run kinnect
pause
