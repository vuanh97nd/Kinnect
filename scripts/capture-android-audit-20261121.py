#!/usr/bin/env python3
import os, pathlib, subprocess, sys, time

OUT = pathlib.Path("outputs/audit-android-20261121")
OUT.mkdir(parents=True, exist_ok=True)
PKG = "app.kinnect.live"

def adb(*args, check=False):
    res = subprocess.run(["adb", *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if check and res.returncode != 0:
        raise RuntimeError(f"adb {args} failed: {res.stderr}")
    return res.stdout.strip()

def set_dark_mode(dark: bool):
    adb("shell", "cmd", "uimode", "night", "yes" if dark else "no")
    time.sleep(0.8)

def capture(name: str):
    out_file = OUT / f"{name}.png"
    with open(out_file, "wb") as f:
        subprocess.run(["adb", "exec-out", "screencap", "-p"], stdout=f, check=True)
    size = out_file.stat().st_size
    print(f"[Captured] {name}.png ({size} bytes)")
    return size

def launch(dest: str, dark: bool = True, wait: float = 2.6, extra_args=None):
    set_dark_mode(dark)
    adb("shell", "am", "force-stop", PKG)
    time.sleep(0.4)
    cmd = [
        "shell", "am", "start", "-W",
        "-n", f"{PKG}/.MainActivity",
        "--ez", "ui_review_fixture", "true",
        "--es", "app_language", "vi",
        "--es", "commerce_destination", dest,
    ]
    if extra_args:
        cmd.extend(extra_args)
    adb(*cmd)
    time.sleep(wait)

def main():
    subprocess.run(["adb", "wait-for-device"], check=True)
    for _ in range(45):
        if adb("shell", "getprop", "sys.boot_completed") == "1":
            break
        time.sleep(2)
    time.sleep(4)
    adb("shell", "input", "keyevent", "82")
    adb("shell", "settings", "put", "global", "window_animation_scale", "0")
    adb("shell", "settings", "put", "global", "transition_animation_scale", "0")
    adb("shell", "settings", "put", "global", "animator_duration_scale", "0")

    apk = "dist/kinnect-live.apk"
    subprocess.run(["adb", "install", "-r", apk], check=True)
    time.sleep(1.5)

    for perm in [
        "android.permission.CAMERA",
        "android.permission.RECORD_AUDIO",
        "android.permission.POST_NOTIFICATIONS",
        "android.permission.ACCESS_FINE_LOCATION",
        "android.permission.ACCESS_COARSE_LOCATION",
        "android.permission.READ_MEDIA_IMAGES",
        "android.permission.READ_MEDIA_VIDEO",
    ]:
        adb("shell", "pm", "grant", PKG, perm)

    screens = [
        ("and_01_welcome", "intro", True, 2.5),
        ("and_02_login", "login", True, 2.4),
        ("and_03_register", "register", True, 2.4),
        ("and_04_forgot", "forgot", True, 2.2),
        ("and_05_feed_dark", "feed", True, 3.0),
        ("and_06_feed_light", "feed", False, 3.0),
        ("and_07_feed_story", "feed_story", True, 2.6),
        ("and_08_feed_comments", "feed_comments", True, 2.8),
        ("and_09_discover_dark", "discover", True, 2.8),
        ("and_10_discover_light", "discover", False, 2.8),
        ("and_11_shorts", "shorts", True, 2.8),
        ("and_12_shorts_comments", "shorts_comments", True, 2.8),
        ("and_13_inbox", "inbox", True, 2.8),
        ("and_14_chat_direct", "chat_direct", True, 2.8),
        ("and_15_chat_group", "chat_group", True, 2.8),
        ("and_16_friends", "friends", True, 2.6),
        ("and_17_friend_requests", "friend_requests", True, 2.6),
        ("and_18_notifications", "notifications", True, 2.6),
        ("and_19_profile_dark", "profile", True, 2.8),
        ("and_20_profile_albums", "profile_albums", True, 2.6),
        ("and_21_account_menu", "account", True, 2.6),
        ("and_22_settings", "settings", True, 2.6),
        ("and_23_wallet", "wallet_main", True, 2.8),
        ("and_24_store_dark", "store", True, 2.8),
        ("and_25_store_light", "store", False, 2.8),
        ("and_26_live", "live", True, 2.8),
        ("and_27_incoming_call", "call_incoming", True, 2.8),
    ]

    for name, dest, dark, wait in screens:
        try:
            launch(dest, dark=dark, wait=wait)
            capture(name)
        except Exception as e:
            print(f"[Error] {name}: {e}")

    # 28. Prove ZERO pinned "Kinnect đang hoạt động" notification in notification shade
    try:
        launch("feed", dark=True, wait=2.5)
        adb("shell", "cmd", "statusbar", "expand-notifications")
        time.sleep(1.5)
        capture("and_28_notification_shade_no_pin")
        adb("shell", "cmd", "statusbar", "collapse")
    except Exception as e:
        print(f"[Error] notification_shade: {e}")

    print(f"[Done] Captured {len(list(OUT.glob('*.png')))} screenshots in {OUT}")

if __name__ == "__main__":
    main()
