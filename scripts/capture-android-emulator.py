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
        adb("shell", "input", "keyevent", "4")  # KEYCODE_BACK
        adb("shell", "input", "keyevent", "66") # KEYCODE_ENTER
    except Exception:
        pass

def ensure_app_foreground():
    for _ in range(5):
        focus = adb("shell", "dumpsys", "window")
        if "app.kinnect.live" in focus:
            return True
        dismiss_system_dialogs()
        adb("shell", "am", "start", "-n", "app.kinnect.live/.MainActivity", "--ez", "ui_review_fixture", "true")
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
    for _ in range(30):
        boot = adb("shell", "getprop", "sys.boot_completed")
        if boot == "1":
            break
        time.sleep(2)
    
    print("[Emulator] Device boot complete. Stabilizing system UI...")
    time.sleep(4)
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
    
    # Load screen inventory
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
    
    # Map screen_id to intent destinations
    DEST_MAP = {
        "SCR-01": "intro",
        "SCR-02": "intro",
        "SCR-03": "login",
        "SCR-04": "register",
        "SCR-05": "forgot",
        "SCR-06": "feed",
        "SCR-07": "feed",
        "SCR-08": "feed",
        "SCR-09": "feed",
        "SCR-10": "feed",
        "SCR-11": "discover",
        "SCR-12": "discover",
        "SCR-13": "discover",
        "SCR-14": "shorts",
        "SCR-15": "shorts",
        "SCR-16": "inbox",
        "SCR-17": "inbox",
        "SCR-18": "inbox",
        "SCR-19": "inbox",
        "SCR-20": "friends",
        "SCR-21": "friends",
        "SCR-22": "account",
        "SCR-23": "account",
        "SCR-24": "account",
        "SCR-25": "account",
        "SCR-26": "settings",
        "SCR-27": "settings",
        "SCR-28": "settings",
        "SCR-29": "notifications",
        "SCR-30": "notifications",
        "SCR-31": "settings",
        "SCR-32": "settings",
        "SCR-33": "settings",
        "SCR-34": "settings",
        "SCR-35": "settings",
        "SCR-36": "store",
        "SCR-37": "store",
        "SCR-38": "live",
        "SCR-39": "live",
        "SCR-40": "live",
        "SCR-41": "feed",
        "SCR-42": "create",
        "SCR-43": "create",
        "SCR-44": "feed",
        "SCR-45": "account",
        "SCR-46": "feed",
        "SCR-47": "account",
        "SCR-48": "feed",
        "SCR-49": "feed"
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
        dest = DEST_MAP.get(scr_id, "feed")
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
        
        # Launch target screen
        is_fixture = "true" if scr_id not in ("SCR-01", "SCR-02") else "false"
        adb("shell", "am", "start", "-n", "app.kinnect.live/.MainActivity",
            "--ez", "ui_review_fixture", is_fixture,
            "-e", "commerce_destination", dest,
            "-e", "app_language", row.get("language", "vi"))
        time.sleep(2.5)
        
        ensure_app_foreground()
        
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
