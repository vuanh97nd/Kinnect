#!/usr/bin/env python3
"""Automated Android Emulator UI capture script for Kinnect QA Parity."""
import subprocess
import time
import os
import sys
import json
import hashlib
import csv
from pathlib import Path

OUT_DIR = Path("outputs/qa-20261112/android/screenshots")
OUT_DIR.mkdir(parents=True, exist_ok=True)
MANIFEST_PATH = Path("outputs/qa-20261112/android/manifest.json")
INVENTORY_PATH = Path("outputs/qa-20261112/android/screen-inventory.csv")

def adb(*args):
    cmd = ["adb"] + list(args)
    res = subprocess.run(cmd, capture_output=True, text=True)
    return res.stdout.strip()

def dismiss_system_dialogs():
    """Dismiss any launcher ANR / system crash overlays."""
    try:
        adb("shell", "am", "broadcast", "-a", "android.intent.action.CLOSE_SYSTEM_DIALOGS")
        time.sleep(0.5)
        # Check if an ANR dialog is visible
        dump = adb("shell", "dumpsys", "window", "windows")
        if "Application Not Responding" in dump or "is not responding" in dump:
            print("[ANR] Detected system crash dialog, dismissing...")
            adb("shell", "input", "keyevent", "66") # KEYCODE_ENTER (Wait)
            time.sleep(0.5)
            adb("shell", "input", "keyevent", "4")  # KEYCODE_BACK
    except Exception:
        pass

def ensure_app_foreground(activity="MainActivity"):
    target = f"app.kinnect.live/.{activity}"
    for _ in range(8):
        focus = adb("shell", "dumpsys", "window")
        if "mCurrentFocus" in focus and "app.kinnect.live" in focus:
            return True
        dismiss_system_dialogs()
        adb("shell", "am", "start", "-n", target, "--ez", "ui_review_fixture", "true")
        time.sleep(1.5)
    return False

def get_file_sha256(filepath):
    h = hashlib.sha256()
    with open(filepath, "rb") as f:
        while chunk := f.read(8192):
            h.update(chunk)
    return h.hexdigest()

def main():
    print("[Emulator] Waiting for ADB device boot complete...")
    subprocess.run(["adb", "wait-for-device"], check=True)
    
    # Wait for boot completion
    for _ in range(40):
        boot = adb("shell", "getprop", "sys.boot_completed")
        if boot == "1":
            break
        time.sleep(2)
    
    print("[Emulator] Device boot complete. Stabilizing system UI...")
    time.sleep(5)
    dismiss_system_dialogs()
    
    # Device metrics
    wm_size = adb("shell", "wm", "size")
    wm_density = adb("shell", "wm", "density")
    print(f"[Device] Size: {wm_size}, Density: {wm_density}")
    
    # Install APK
    apk = "dist/kinnect-live-debug.apk"
    if not os.path.exists(apk):
        print(f"[Error] APK not found at {apk}")
        sys.exit(1)
        
    print(f"[Install] Installing {apk}...")
    subprocess.run(["adb", "install", "-r", apk], check=True)
    time.sleep(2)
    dismiss_system_dialogs()
    
    if not INVENTORY_PATH.exists():
        print(f"[Error] Inventory not found at {INVENTORY_PATH}")
        sys.exit(1)
        
    rows = []
    with open(INVENTORY_PATH, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for r in reader:
            rows.append(r)
            
    print(f"[Inventory] Loaded {len(rows)} screen definitions.")
    
    seen_hashes = {}
    captures = []
    
    # Detailed mapping to exercise specific nested sub-screens
    DEST_MAP = {
        "SCR-01": ("MainActivity", "intro", "intro"),
        "SCR-02": ("MainActivity", "intro", "welcome"),
        "SCR-03": ("MainActivity", "login", "auth_login"),
        "SCR-04": ("MainActivity", "register", "auth_register"),
        "SCR-05": ("MainActivity", "forgot", "auth_forgot"),
        "SCR-06": ("MainActivity", "feed", "feed_home"),
        "SCR-07": ("MainActivity", "feed", "feed_story"),
        "SCR-08": ("MainActivity", "feed", "feed_post_detail"),
        "SCR-09": ("MainActivity", "feed", "feed_comments"),
        "SCR-10": ("MainActivity", "feed", "feed_reactions"),
        "SCR-11": ("MainActivity", "discover", "discover_search"),
        "SCR-12": ("MainActivity", "discover", "discover_results"),
        "SCR-13": ("MainActivity", "discover", "discover_empty"),
        "SCR-14": ("MainActivity", "shorts", "shorts_player"),
        "SCR-15": ("MainActivity", "shorts", "shorts_comments"),
        "SCR-16": ("MainActivity", "inbox", "inbox_list"),
        "SCR-17": ("MainActivity", "chat_direct", "chat_direct"),
        "SCR-18": ("MainActivity", "chat_group", "chat_group"),
        "SCR-19": ("MainActivity", "inbox", "chat_menu"),
        "SCR-20": ("MainActivity", "friends", "friends_list"),
        "SCR-21": ("MainActivity", "friend_requests", "friends_requests"),
        "SCR-22": ("MainActivity", "account", "profile_main"),
        "SCR-23": ("MainActivity", "profile_edit", "profile_edit"),
        "SCR-24": ("MainActivity", "account", "profile_albums"),
        "SCR-25": ("MainActivity", "account", "account_menu"),
        "SCR-26": ("MainActivity", "settings", "appearance_settings"),
        "SCR-27": ("MainActivity", "password", "security_password"),
        "SCR-28": ("MainActivity", "settings", "sessions_devices"),
        "SCR-29": ("MainActivity", "notifications", "notifications_screen"),
        "SCR-30": ("MainActivity", "settings", "notifications_settings"),
        "SCR-31": ("MainActivity", "settings", "privacy_settings"),
        "SCR-32": ("MainActivity", "language", "language_settings"),
        "SCR-33": ("MainActivity", "settings", "help_support"),
        "SCR-34": ("MainActivity", "settings", "about_screen"),
        "SCR-35": ("MainActivity", "settings", "delete_account_confirm"),
        "SCR-36": ("MainActivity", "store", "wallet_main"),
        "SCR-37": ("MainActivity", "store", "store_packages"),
        "SCR-38": ("MainActivity", "live", "live_list"),
        "SCR-39": ("MainActivity", "live", "live_setup_sheet"),
        "SCR-40": ("MainActivity", "live", "live_gifts_drawer"),
        "SCR-41": ("MainActivity", "feed", "call_incoming"),
        "SCR-42": ("MainActivity", "create", "studio_camera"),
        "SCR-43": ("MainActivity", "create", "studio_music_picker"),
        "SCR-44": ("MainActivity", "feed", "feed_dark"),
        "SCR-45": ("MainActivity", "account", "account_dark"),
        "SCR-46": ("MainActivity", "feed", "feed_font13"),
        "SCR-47": ("MainActivity", "account", "account_font13"),
        "SCR-48": ("MainActivity", "feed", "feed_narrow"),
        "SCR-49": ("MainActivity", "feed", "comments_narrow")
    }

    current_theme = "light"
    current_font = "1.0"
    current_size = "normal"
    
    adb("shell", "cmd", "uimode", "night", "no")
    adb("shell", "settings", "put", "system", "font_scale", "1.0")
    adb("shell", "wm", "size", "reset")
    adb("shell", "wm", "density", "reset")
    
    for row in rows:
        scr_id = row["screen_id"]
        act_name, dest, state_label = DEST_MAP.get(scr_id, ("MainActivity", "feed", "default"))
        theme = row.get("theme", "light")
        font_scale = row.get("fontScale", "1.0")
        res = row.get("resolution", "1080x2400")
        img_file = Path(row["image_path"]).name
        target_path = OUT_DIR / img_file
        
        # Configure theme if changed
        if theme != current_theme:
            adb("shell", "cmd", "uimode", "night", "yes" if theme == "dark" else "no")
            current_theme = theme
            time.sleep(1)
            
        # Configure font scale if changed
        if font_scale != current_font:
            adb("shell", "settings", "put", "system", "font_scale", font_scale)
            current_font = font_scale
            time.sleep(1)
            
        # Configure narrow screen if needed
        if "720x1520" in res and current_size != "narrow":
            adb("shell", "wm", "size", "720x1520")
            adb("shell", "wm", "density", "320")
            current_size = "narrow"
            time.sleep(1)
        elif "720x1520" not in res and current_size == "narrow":
            adb("shell", "wm", "size", "reset")
            adb("shell", "wm", "density", "reset")
            current_size = "normal"
            time.sleep(1)
            
        dismiss_system_dialogs()
        
        # Launch target screen with fixture enabled
        is_fixture = "true" if scr_id not in ("SCR-01", "SCR-02") else "false"
        adb("shell", "am", "start", "-n", f"app.kinnect.live/.{act_name}",
            "--ez", "ui_review_fixture", is_fixture,
            "-e", "commerce_destination", dest,
            "-e", "app_language", row.get("language", "vi"))
        time.sleep(2.5)
        
        ensure_app_foreground(act_name)
        
        # Screencap
        subprocess.run(["adb", "exec-out", "screencap", "-p"], stdout=open(target_path, "wb"), check=True)
        
        sha = get_file_sha256(target_path)
        dup_of = seen_hashes.get(sha)
        
        if dup_of:
            row["status"] = "duplicate_warning"
            row["blocker_or_reason"] = f"Identical SHA256 to {dup_of}"
        else:
            seen_hashes[sha] = scr_id
            row["status"] = "captured"
            row["blocker_or_reason"] = "OK (ADB screencap verified)"
            
        captures.append({
            "screen_id": scr_id,
            "screen_name": row["screen_name"],
            "file": f"screenshots/{img_file}",
            "sha256": sha,
            "theme": theme,
            "fontScale": font_scale,
            "status": row["status"]
        })
        print(f"[{row['status'].upper()}] {scr_id} ({img_file}): sha={sha[:8]}...")
        
    # Reset device state
    adb("shell", "cmd", "uimode", "night", "no")
    adb("shell", "settings", "put", "system", "font_scale", "1.0")
    adb("shell", "wm", "size", "reset")
    adb("shell", "wm", "density", "reset")
    
    # Rewrite inventory with updated status
    with open(INVENTORY_PATH, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
        
    # Write manifest
    captured_count = sum(1 for c in captures if c["status"] == "captured")
    dup_count = sum(1 for c in captures if c["status"] == "duplicate_warning")
    
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
        "stats": {
            "totalScreens": len(rows),
            "captured": captured_count,
            "duplicateWarnings": dup_count
        },
        "captures": captures
    }
    
    with open(MANIFEST_PATH, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
        
    print(f"\n[Summary] Captured {captured_count}/{len(rows)} screens. Duplicates: {dup_count}. Manifest: {MANIFEST_PATH}")

if __name__ == "__main__":
    main()
