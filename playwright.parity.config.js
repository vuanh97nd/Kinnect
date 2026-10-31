import {defineConfig} from '@playwright/test';
export default defineConfig({testDir:'./e2e',workers:1,timeout:60000,retries:0,reporter:'list',use:{headless:true,launchOptions:{executablePath:'C:/Users/ANH/Documents/Codex/2026-10-24/c-kinnect-s-theo-h-ng/outputs/Kinnect/work/browsers/chromium_headless_shell-1194/chrome-win/headless_shell.exe'},viewport:{width:390,height:844}}});
