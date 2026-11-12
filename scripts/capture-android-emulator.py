#!/usr/bin/env python3
"""Automated Android Emulator UI capture script for Kinnect QA Parity."""
import subprocess
import time
import os
import json
from pathlib import Path

OUT_DIR = Path("outputs/qa-20261112/android/screenshots")
OUT_DIR.mkdir(parents=True, exist_ok=True)
MANIFEST_PATH = Path("outputs/qa-20261112/android/manifest.json")

def adb(*args):
    cmd = ["adb"] + list(args)
    res = subprocess.run(cmd, capture_output=True, text=True)
    return res.stdout.strip()

def capture(filename, description, screen, theme="light", lang="vi", font_scale=1.0, width=1080, height=2400):
    filepath = OUT_DIR / filename
    print(f"[Capture] {filename}: {description} (theme={theme}, font={font_scale})")
    subprocess.run(["adb", "exec-out", "screencap", "-p"], stdout=open(filepath, "wb"))
    return {
        "file": f"screenshots/{filename}",
        "screen": screen,
        "description": description,
        "theme": theme,
        "language": lang,
        "fontScale": font_scale,
        "resolution": f"{width}x{height}",
        "capturedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    }

def main():
    print("[Emulator] Waiting for ADB device...")
    subprocess.run(["adb", "wait-for-device"], check=True)
    time.sleep(5)
    
    # Device metrics
    wm_size = adb("shell", "wm", "size")
    wm_density = adb("shell", "wm", "density")
    print(f"[Device] Size: {wm_size}, Density: {wm_density}")
    
    # Install APK
    apk = "dist/kinnect-live-debug.apk"
    if not os.path.exists(apk):
        print(f"[Error] APK not found at {apk}")
        return
    print(f"[Install] Installing {apk}...")
    subprocess.run(["adb", "install", "-r", apk], check=True)
    
    captures = []
    
    # 1. Standard Light Mode captures
    adb("shell", "cmd", "uimode", "night", "no")
    adb("shell", "settings", "put", "system", "font_scale", "1.0")
    
    # Splash / Intro
    adb("shell", "am", "start", "-S", "-n", "app.kinnect.live/.MainActivity")
    time.sleep(2)
    captures.append(capture("01_splash_intro.png", "Splash & Intro Screen", "splash", "light", "vi", 1.0))
    time.sleep(3)
    
    # Auth / Welcome screen
    captures.append(capture("02_auth_welcome.png", "Welcome / Login / Auth options", "auth", "light", "vi", 1.0))
    
    # Navigate to Main Feed (via deeplink/extras)
    adb("shell", "am", "start", "-n", "app.kinnect.live/.MainActivity", "-e", "commerce_destination", "feed")
    time.sleep(3)
    captures.append(capture("03_feed_home.png", "Bảng tin (Feed) chính", "feed", "light", "vi", 1.0))
    
    # Discover
    adb("shell", "am", "start", "-n", "app.kinnect.live/.MainActivity", "-e", "commerce_destination", "discover")
    time.sleep(2)
    captures.append(capture("04_discover.png", "Khám phá (Discover) & Tìm kiếm", "discover", "light", "vi", 1.0))
    
    # Shorts
    adb("shell", "am", "start", "-n", "app.kinnect.live/.MainActivity", "-e", "commerce_destination", "shorts")
    time.sleep(2)
    captures.append(capture("05_shorts.png", "Shorts Video Player", "shorts", "light", "vi", 1.0))
    
    # Live Room / Setup
    adb("shell", "am", "start", "-n", "app.kinnect.live/.MainActivity", "-e", "commerce_destination", "live")
    time.sleep(2)
    captures.append(capture("06_live_setup.png", "Trực tiếp (Live) Setup & Danh sách phòng", "live", "light", "vi", 1.0))
    
    # Top Bar: Notifications
    adb("shell", "am", "start", "-n", "app.kinnect.live/.MainActivity", "-e", "commerce_destination", "notifications")
    time.sleep(2)
    captures.append(capture("07_notifications.png", "Thông báo (Notifications)", "notifications", "light", "vi", 1.0))
    
    # Top Bar: Store
    adb("shell", "am", "start", "-n", "app.kinnect.live/.MainActivity", "-e", "commerce_destination", "store")
    time.sleep(2)
    captures.append(capture("08_store.png", "Cửa hàng & Gói vật phẩm (Store)", "store", "light", "vi", 1.0))
    
    # Top Bar: Friends
    adb("shell", "am", "start", "-n", "app.kinnect.live/.MainActivity", "-e", "commerce_destination", "friends")
    time.sleep(2)
    captures.append(capture("09_friends.png", "Bạn bè & Lời mời kết bạn", "friends", "light", "vi", 1.0))
    
    # Top Bar: Messages / Chat Inbox
    adb("shell", "am", "start", "-n", "app.kinnect.live/.MainActivity", "-e", "commerce_destination", "inbox")
    time.sleep(2)
    captures.append(capture("10_messages.png", "Tin nhắn (Inbox)", "messages", "light", "vi", 1.0))
    
    # Top Bar: Account Menu
    adb("shell", "am", "start", "-n", "app.kinnect.live/.MainActivity", "-e", "commerce_destination", "account")
    time.sleep(2)
    captures.append(capture("11_account_menu.png", "Menu Tài khoản & Cài đặt", "account", "light", "vi", 1.0))
    
    # 2. Dark Mode captures
    adb("shell", "cmd", "uimode", "night", "yes")
    time.sleep(2)
    adb("shell", "am", "start", "-n", "app.kinnect.live/.MainActivity", "-e", "commerce_destination", "feed")
    time.sleep(2)
    captures.append(capture("12_feed_dark.png", "Bảng tin (Dark Theme)", "feed", "dark", "vi", 1.0))
    
    adb("shell", "am", "start", "-n", "app.kinnect.live/.MainActivity", "-e", "commerce_destination", "account")
    time.sleep(2)
    captures.append(capture("13_account_dark.png", "Menu Tài khoản (Dark Theme)", "account", "dark", "vi", 1.0))
    
    # 3. Large Font Scale (1.3)
    adb("shell", "cmd", "uimode", "night", "no")
    adb("shell", "settings", "put", "system", "font_scale", "1.3")
    time.sleep(2)
    adb("shell", "am", "start", "-n", "app.kinnect.live/.MainActivity", "-e", "commerce_destination", "feed")
    time.sleep(2)
    captures.append(capture("14_feed_font13.png", "Bảng tin chữ lớn (fontScale=1.3)", "feed", "light", "vi", 1.3))
    
    adb("shell", "am", "start", "-n", "app.kinnect.live/.MainActivity", "-e", "commerce_destination", "account")
    time.sleep(2)
    captures.append(capture("15_account_font13.png", "Menu Tài khoản chữ lớn (fontScale=1.3)", "account", "light", "vi", 1.3))
    
    # 4. Narrow Screen (720x1520)
    adb("shell", "settings", "put", "system", "font_scale", "1.0")
    adb("shell", "wm", "size", "720x1520")
    adb("shell", "wm", "density", "320")
    time.sleep(2)
    adb("shell", "am", "start", "-n", "app.kinnect.live/.MainActivity", "-e", "commerce_destination", "feed")
    time.sleep(2)
    captures.append(capture("16_feed_narrow.png", "Bảng tin màn hẹp 720x1520", "feed", "light", "vi", 1.0, 720, 1520))
    
    adb("shell", "am", "start", "-n", "app.kinnect.live/.MainActivity", "-e", "commerce_destination", "account")
    time.sleep(2)
    captures.append(capture("17_account_narrow.png", "Menu Tài khoản màn hẹp 720x1520", "account", "light", "vi", 1.0, 720, 1520))
    
    # Reset window size
    adb("shell", "wm", "size", "reset")
    adb("shell", "wm", "density", "reset")
    
    # Write manifest.json
    manifest = {
        "platform": "android",
        "provenance": {
            "sourceCommit": subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip(),
            "targetSdk": 35,
            "minSdk": 26,
            "apkPackage": "app.kinnect.live",
            "deviceProfile": "Pixel 6 (Google APIs x86_64)",
            "apiLevel": 34,
            "capturedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        },
        "capturesCount": len(captures),
        "captures": captures
    }
    
    with open(MANIFEST_PATH, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
    print(f"[Done] Captured {len(captures)} screenshots. Manifest written to {MANIFEST_PATH}")

if __name__ == "__main__":
    main()
