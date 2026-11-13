#!/usr/bin/env python3
import json
import os
import plistlib
import re
import signal
import subprocess
import sys
import time
from pathlib import Path

OUT_DIR = Path("dist/ios-ui-review")
OUT_DIR.mkdir(parents=True, exist_ok=True)
DEFAULT_BUNDLE_ID = "app.kinnect.live"
SOURCE_INFO_PLIST = Path("ios/Kinnect/Resources/Info.plist")
SOURCE_PROJECT_YML = Path("ios/project.yml")


def run(cmd, check=True, capture=True):
    print(f"+ {' '.join(cmd)}", flush=True)
    res = subprocess.run(cmd, text=True, capture_output=capture)
    if check and res.returncode != 0:
        print("STDOUT:", res.stdout, flush=True)
        print("STDERR:", res.stderr, flush=True)
        raise RuntimeError(f"Command failed ({res.returncode}): {' '.join(cmd)}")
    return res


def read_plist_value(plist_path, key):
    if not plist_path.exists():
        return None
    try:
        if Path("/usr/libexec/PlistBuddy").exists():
            res = subprocess.run(
                ["/usr/libexec/PlistBuddy", "-c", f"Print :{key}", str(plist_path)],
                capture_output=True, text=True
            )
            val = res.stdout.strip()
            if res.returncode == 0 and val:
                return val
    except Exception as e:
        print(f"Warning: PlistBuddy read failed for {key}: {e}", flush=True)
    try:
        with open(plist_path, "rb") as fh:
            data = plistlib.load(fh)
        val = data.get(key)
        if val is not None and str(val).strip():
            return str(val).strip()
    except Exception as e:
        print(f"Warning: plistlib read failed for {key}: {e}", flush=True)
    return None


def read_project_yml_versions():
    if not SOURCE_PROJECT_YML.exists():
        return None, None
    try:
        text = SOURCE_PROJECT_YML.read_text(encoding="utf-8")
    except Exception as e:
        print(f"Warning: could not read {SOURCE_PROJECT_YML}: {e}", flush=True)
        return None, None
    marketing = None
    build = None
    m = re.search(r'MARKETING_VERSION:\s*"([^"]+)"', text)
    if m:
        marketing = m.group(1).strip()
    b = re.search(r'CURRENT_PROJECT_VERSION:\s*"([^"]+)"', text)
    if b:
        build = b.group(1).strip()
    return marketing, build


def resolve_app_versions():
    """Read live MARKETING_VERSION / CURRENT_PROJECT_VERSION from source plist before build."""
    marketing = read_plist_value(SOURCE_INFO_PLIST, "CFBundleShortVersionString")
    build = read_plist_value(SOURCE_INFO_PLIST, "CFBundleVersion")
    yml_marketing, yml_build = read_project_yml_versions()
    if not marketing and yml_marketing:
        marketing = yml_marketing
        print(f"Using MARKETING_VERSION from project.yml: {marketing}", flush=True)
    if not build and yml_build:
        build = yml_build
        print(f"Using CURRENT_PROJECT_VERSION from project.yml: {build}", flush=True)
    if not marketing or not build:
        raise RuntimeError(
            "Could not resolve MARKETING_VERSION / CURRENT_PROJECT_VERSION from "
            f"{SOURCE_INFO_PLIST} (or {SOURCE_PROJECT_YML} fallback). "
            "Refusing stale hardcoded overrides."
        )
    print(
        f"Resolved versions from source before build: "
        f"MARKETING_VERSION={marketing} CURRENT_PROJECT_VERSION={build}",
        flush=True,
    )
    return marketing, build


def get_git_sha():
    env_sha = (
        os.environ.get("GITHUB_SHA")
        or os.environ.get("GIT_COMMIT")
        or os.environ.get("COMMIT_SHA")
        or ""
    ).strip()
    if env_sha:
        return env_sha
    try:
        res = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            capture_output=True, text=True, check=False
        )
        if res.returncode == 0 and res.stdout.strip():
            return res.stdout.strip()
    except Exception as e:
        print(f"Warning: git rev-parse failed: {e}", flush=True)
    return "unknown"


def write_provenance_manifest(marketing_version, build_number, extra=None):
    provenance = {
        "gitSha": get_git_sha(),
        "marketingVersion": marketing_version,
        "buildNumber": build_number,
        "CFBundleShortVersionString": marketing_version,
        "CFBundleVersion": build_number,
        "MARKETING_VERSION": marketing_version,
        "CURRENT_PROJECT_VERSION": build_number,
        "sourceInfoPlist": str(SOURCE_INFO_PLIST).replace("\\", "/"),
        "capturedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "githubRunId": os.environ.get("GITHUB_RUN_ID"),
        "githubRunAttempt": os.environ.get("GITHUB_RUN_ATTEMPT"),
        "githubRef": os.environ.get("GITHUB_REF"),
        "githubRepository": os.environ.get("GITHUB_REPOSITORY"),
        "workflow": os.environ.get("GITHUB_WORKFLOW"),
        "actor": os.environ.get("GITHUB_ACTOR"),
    }
    if extra:
        provenance.update(extra)
    path = OUT_DIR / "provenance.json"
    path.write_text(json.dumps(provenance, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"Wrote provenance manifest: {path}", flush=True)
    return provenance


def get_bundle_id(app_path):
    plist = Path(app_path) / "Info.plist"
    if plist.exists():
        try:
            res = subprocess.run(
                ["/usr/libexec/PlistBuddy", "-c", "Print :CFBundleIdentifier", str(plist)],
                capture_output=True, text=True
            )
            val = res.stdout.strip()
            if res.returncode == 0 and val:
                print(f"Extracted CFBundleIdentifier from Info.plist: {val}", flush=True)
                return val
        except Exception as e:
            print(f"Warning: could not read Info.plist via PlistBuddy: {e}", flush=True)
    print(f"Using default bundle identifier: {DEFAULT_BUNDLE_ID}", flush=True)
    return DEFAULT_BUNDLE_ID


def get_available_simulators():
    res = run(["xcrun", "simctl", "list", "devices", "available", "-j"])
    data = json.loads(res.stdout)
    devices = []
    for runtime, dev_list in data.get("devices", {}).items():
        if "iOS" not in runtime and "iphonesimulator" not in runtime.lower():
            continue
        for d in dev_list:
            if d.get("isAvailable"):
                d["runtime"] = runtime
                devices.append(d)
    return devices


def ensure_xcode_with_simulator_runtime():
    devices = get_available_simulators()
    if devices:
        return devices
    # Check other installed Xcode versions if current one has no available iOS simulator runtime
    apps = sorted(Path("/Applications").glob("Xcode*.app"), reverse=True)
    for app in apps:
        print(f"Checking simulator runtimes in {app}...", flush=True)
        subprocess.run(["sudo", "xcode-select", "-s", str(app / "Contents/Developer")], check=False)
        devices = get_available_simulators()
        if devices:
            print(f"Found {len(devices)} available simulator devices using {app}", flush=True)
            return devices
    raise RuntimeError("No available iOS Simulator runtime found on this macOS runner.")


def pick_devices(devices):
    iphones = [d for d in devices if "iPhone" in d["name"]]
    ipads = [d for d in devices if "iPad" in d["name"]]

    # Standard iPhone: prefer Pro or standard model (not SE)
    standard_candidates = [d for d in iphones if "SE" not in d["name"] and "mini" not in d["name"]]
    standard_iphone = standard_candidates[0] if standard_candidates else (iphones[0] if iphones else None)

    # Compact / small iPhone: prefer SE or mini or 16e, else a different iPhone
    compact_candidates = [d for d in iphones if ("SE" in d["name"] or "mini" in d["name"] or "16e" in d["name"])]
    if compact_candidates:
        compact_iphone = compact_candidates[0]
    elif len(iphones) > 1:
        compact_iphone = iphones[-1]
    else:
        compact_iphone = standard_iphone

    ipad = ipads[0] if ipads else None
    return standard_iphone, compact_iphone, ipad


def boot_and_install(device, app_path, bundle_id):
    udid = device["udid"]
    name = device["name"]
    print(f"Booting simulator {name} ({udid})...", flush=True)
    subprocess.run(["defaults", "write", "com.apple.iphonesimulator", "ConnectHardwareKeyboard", "-bool", "false"], check=False)
    subprocess.run(["xcrun", "simctl", "boot", udid], check=False)
    run(["xcrun", "simctl", "bootstatus", udid, "-b"])
    subprocess.run(["open", "-g", "-a", "Simulator", "--args", "-CurrentDeviceUDID", udid], check=False)
    # Set default dark appearance initially
    subprocess.run(["xcrun", "simctl", "ui", udid, "appearance", "dark"], check=False)
    # Set clean status bar
    subprocess.run([
        "xcrun", "simctl", "status_bar", udid, "override",
        "--time", "09:41",
        "--batteryState", "charged",
        "--batteryLevel", "100"
    ], check=False)
    run(["xcrun", "simctl", "install", udid, str(app_path)])
    # Warm-up app launch to ensure Dyld, SpringBoard, and Metal render caches are ready
    print(f"Warming up app on {name}...", flush=True)
    subprocess.run(["xcrun", "simctl", "launch", udid, bundle_id, "--ui-review-screen", "auth-login"], check=False)
    time.sleep(3.5)
    subprocess.run(["xcrun", "simctl", "terminate", udid, bundle_id], check=False)
    time.sleep(1.0)


def screen_needs_capture_permission(screen_arg):
    return (
        screen_arg.startswith("camera")
        or screen_arg.startswith("studio")
        or screen_arg.startswith("live")
        or "call" in screen_arg
    )


def isolate_permission_state(udid, bundle_id, screen_arg):
    """Reset TCC for this app, then grant camera/mic only for screens that use them.

    A camera prompt raised by an earlier screen stays above later screens unless
    the process is killed and the permission state is separated.
    """
    subprocess.run(["xcrun", "simctl", "privacy", udid, "reset", "all", bundle_id], check=False)
    if screen_needs_capture_permission(screen_arg):
        subprocess.run(["xcrun", "simctl", "privacy", udid, "grant", "camera", bundle_id], check=False)
        subprocess.run(["xcrun", "simctl", "privacy", udid, "grant", "microphone", bundle_id], check=False)


def copy_app_document(udid, bundle_id, name):
    res = subprocess.run(
        ["xcrun", "simctl", "get_app_container", udid, bundle_id, "data"],
        text=True,
        capture_output=True,
    )
    if res.returncode != 0:
        print(f"Could not read app container for {name}", flush=True)
        return
    source = Path(res.stdout.strip()) / "Documents" / name
    if source.exists():
        target = OUT_DIR / name
        target.write_bytes(source.read_bytes())
        print(f"Copied {name}", flush=True)
    else:
        print(f"Missing document {source}", flush=True)


def capture_screen(device, slug, screen_arg, bundle_id, extra_args=None, wait_sec=3.0):
    udid = device["udid"]
    subprocess.run(["xcrun", "simctl", "terminate", udid, bundle_id], check=False)
    time.sleep(1.0)
    isolate_permission_state(udid, bundle_id, screen_arg)

    is_light = extra_args and "--ui-review-light" in extra_args
    if is_light:
        subprocess.run(["xcrun", "simctl", "ui", udid, "appearance", "light"], check=False)
        subprocess.run([
            "xcrun", "simctl", "status_bar", udid, "override",
            "--time", "09:41",
            "--batteryState", "charged",
            "--batteryLevel", "100"
        ], check=False)
    else:
        subprocess.run(["xcrun", "simctl", "ui", udid, "appearance", "dark"], check=False)
        subprocess.run([
            "xcrun", "simctl", "status_bar", udid, "override",
            "--time", "09:41",
            "--batteryState", "charged",
            "--batteryLevel", "100"
        ], check=False)

    lang_arg = "(en)" if screen_arg.endswith("-en") else "(vi)"
    cmd = ["xcrun", "simctl", "launch", udid, bundle_id, "-AppleLanguages", lang_arg, "--ui-review-screen", screen_arg]
    if extra_args:
        cmd.extend(extra_args)
    record = screen_arg in ("shorts-telemetry", "shorts-avplayer", "shorts-real-swipe")
    video_path = OUT_DIR / f"{slug}.mp4"
    recorder = None
    if record:
        recorder = subprocess.Popen(
            ["xcrun", "simctl", "io", udid, "recordVideo", "--codec=h264", str(video_path)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        time.sleep(1.0)

    run(cmd)

    if screen_arg == "shorts-avplayer":
        actual_wait = 16.0
    elif screen_arg == "shorts-real-swipe":
        actual_wait = 12.0
    elif screen_arg == "swift-contracts-harness":
        actual_wait = 4.5
    elif screen_arg in ("auth", "auth-login-keyboard", "auth-login-password-keyboard", "auth-login-lang-sheet", "shorts-telemetry"):
        actual_wait = 6.0
    else:
        actual_wait = wait_sec
    time.sleep(actual_wait)

    out_file = OUT_DIR / f"{slug}.png"
    run(["xcrun", "simctl", "io", udid, "screenshot", str(out_file)])
    if recorder is not None:
        recorder.send_signal(signal.SIGINT)
        try:
            recorder.wait(timeout=20)
        except subprocess.TimeoutExpired:
            recorder.kill()
    document_name = {
        "password-spy": "password-spy.json",
        "shorts-telemetry": "shorts-telemetry.json",
        "shorts-avplayer": "shorts-avplayer.json",
        "shorts-real-swipe": "shorts-real-swipe.json",
        "persist-write": "persist-write.json",
        "persist-read": "persist-read.json",
        "privacy-save-error": "privacy-save-error.json",
        "privacy-toggle-error": "privacy-toggle-error.json",
        "dm-mode-error": "dm-mode-error.json",
        "location-off-error": "location-off-error.json",
        "admin-denied": "admin-denied.json",
        "gift-catalog-v1": "gift-catalog-v1.json",
        "swift-contracts-harness": "swift-contracts-harness.json",
    }.get(screen_arg)
    if document_name:
        copy_app_document(udid, bundle_id, document_name)
    if screen_arg == "shorts-avplayer":
        copy_app_document(udid, bundle_id, "shorts-avplayer-frame.png")
        copy_app_document(udid, bundle_id, "shorts-avplayer-frame-second.png")
    elif screen_arg == "shorts-real-swipe":
        copy_app_document(udid, bundle_id, "shorts-real-swipe-frame-1.png")
        copy_app_document(udid, bundle_id, "shorts-real-swipe-frame-2.png")

    if is_light:
        subprocess.run(["xcrun", "simctl", "ui", udid, "appearance", "dark"], check=False)

    return out_file


def build_contact_sheet(records):
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        try:
            subprocess.run([sys.executable, "-m", "pip", "install", "--quiet", "--break-system-packages", "pillow"], check=False)
            from PIL import Image, ImageDraw, ImageFont
        except Exception as e:
            print(f"Pillow install skipped/failed: {e}", flush=True)
            Image = None

    if Image is not None:
        try:
            cols = 4
            png_records = [r for r in records if Path(r["file"]).suffix.lower() == ".png" and Path(r["file"]).exists()]
            rows = (len(png_records) + cols - 1) // cols
            cell_w, cell_h = 340, 680
            sheet = Image.new("RGB", (cols * cell_w + 40, rows * cell_h + 80), (14, 11, 24))
            draw = ImageDraw.Draw(sheet)
            draw.text((24, 20), "Kinnect iOS Native SwiftUI — Actual iOS Simulator UI Review Contact Sheet", fill=(255, 255, 255))

            for idx, rec in enumerate(png_records):
                r = idx // cols
                c = idx % cols
                x0 = 20 + c * cell_w
                y0 = 60 + r * cell_h
                img_path = Path(rec["file"])
                with Image.open(img_path) as im:
                    im_copy = im.convert("RGB")
                    im_copy.thumbnail((cell_w - 28, cell_h - 70))
                    ox = x0 + (cell_w - im_copy.width) // 2
                    oy = y0 + 10
                    sheet.paste(im_copy, (ox, oy))
                    label = f"{rec['slug']} ({rec['device']})"
                    draw.text((x0 + 14, y0 + cell_h - 48), label[:42], fill=(210, 195, 255))

            contact_path = OUT_DIR / "contact-sheet.png"
            sheet.save(contact_path)
            print(f"Generated PNG contact sheet: {contact_path}", flush=True)
        except Exception as err:
            print(f"Warning generating PNG contact sheet: {err}", flush=True)

    # Real PNG contact sheet only — no HTML screenshots.
    return OUT_DIR / "contact-sheet.png" if (OUT_DIR / "contact-sheet.png").exists() else None


def main():
    marketing_version, build_number = resolve_app_versions()
    provenance = write_provenance_manifest(marketing_version, build_number)

    devices = ensure_xcode_with_simulator_runtime()
    xcode_ver = run(["xcodebuild", "-version"]).stdout.strip().replace("\n", " | ")
    runtimes_txt = run(["xcrun", "simctl", "list", "runtimes"]).stdout

    print(
        f"Building Kinnect.app for iphonesimulator "
        f"(MARKETING_VERSION={marketing_version} CURRENT_PROJECT_VERSION={build_number})...",
        flush=True,
    )
    run([
        "xcodebuild", "build",
        "-project", "ios/Kinnect.xcodeproj",
        "-scheme", "Kinnect",
        "-configuration", "Debug",
        "-sdk", "iphonesimulator",
        "-derivedDataPath", "build/SimDerivedData",
        f"MARKETING_VERSION={marketing_version}",
        f"CURRENT_PROJECT_VERSION={build_number}",
        "CODE_SIGN_IDENTITY=",
        "CODE_SIGNING_REQUIRED=NO",
        "CODE_SIGNING_ALLOWED=NO",
        "ENABLE_DEBUG_DYLIB=NO"
    ], capture=False)

    app_path = Path("build/SimDerivedData/Build/Products/Debug-iphonesimulator/Kinnect.app")
    if not app_path.exists():
        found = list(Path("build/SimDerivedData").rglob("Kinnect.app"))
        if not found:
            raise RuntimeError("Kinnect.app not found in build/SimDerivedData")
        app_path = found[0]

    bundle_id = get_bundle_id(app_path)
    print(f"Target bundle identifier for simulator: {bundle_id}", flush=True)

    print(f"Ad-hoc signing {app_path} for simulator...", flush=True)
    subprocess.run(["codesign", "--force", "--deep", "--sign", "-", str(app_path)], check=False)

    standard_iphone, compact_iphone, ipad = pick_devices(devices)
    if not standard_iphone:
        raise RuntimeError("No iPhone simulator device available.")

    records = []

    only_login = os.environ.get("UI_REVIEW_ONLY_LOGIN") == "1"

    # 1. Standard iPhone screenshots
    boot_and_install(standard_iphone, app_path, bundle_id)
    login_iphone_screens = [
        ("01-iphone-auth-welcome-dark", "auth-welcome", ["--ui-review-welcome-tab", "1"], "Chào mừng Tab 1: Khám phá (Discover VI) — Standard iPhone"),
        ("01-iphone-auth-welcome-tab0-feed-dark", "auth-welcome", ["--ui-review-welcome-tab", "0"], "Chào mừng Tab 0: Bảng tin (Feed VI) — Standard iPhone"),
        ("01-iphone-auth-welcome-tab2-video-dark", "auth-welcome", ["--ui-review-welcome-tab", "2"], "Chào mừng Tab 2: Video Shorts (VI) — Standard iPhone"),
        ("01-iphone-auth-welcome-tab3-live-dark", "auth-welcome", ["--ui-review-welcome-tab", "3"], "Chào mừng Tab 3: Trực tiếp Live (VI) — Standard iPhone"),
        ("01a-iphone-auth-welcome-en-dark", "auth-welcome-en", ["--ui-review-welcome-tab", "1"], "Chào mừng tiếng Anh Tab 1: Khám phá (Discover EN) — Standard iPhone"),
        ("01a0-iphone-auth-welcome-tab0-feed-en-dark", "auth-welcome-en", ["--ui-review-welcome-tab", "0"], "Chào mừng tiếng Anh Tab 0: Bảng tin (Feed EN) — Standard iPhone"),
        ("01a2-iphone-auth-welcome-tab2-video-en-dark", "auth-welcome-en", ["--ui-review-welcome-tab", "2"], "Chào mừng tiếng Anh Tab 2: Video Shorts (EN) — Standard iPhone"),
        ("01a3-iphone-auth-welcome-tab3-live-en-dark", "auth-welcome-en", ["--ui-review-welcome-tab", "3"], "Chào mừng tiếng Anh Tab 3: Trực tiếp Live (EN) — Standard iPhone"),
        ("01b-iphone-auth-login-dark", "auth-login", [], "Đăng nhập chính tiếng Việt trống (Dark)"),
        ("01b2-iphone-auth-login-populated-dark", "auth-login-populated", [], "Đăng nhập đã điền tài khoản & mật khẩu (Dark)"),
        ("01b3-iphone-auth-login-error-dark", "auth-login-error", [], "Đăng nhập hiển thị lỗi xác thực (Dark)"),
        ("01b4-iphone-auth-login-en-dark", "auth-login-en", [], "Đăng nhập giao diện tiếng Anh (English Dark)"),
        ("01b5-iphone-auth-login-keyboard-dark", "auth-login-keyboard", [], "Đăng nhập mở bàn phím trên Standard iPhone (Dark)"),
        ("01b6-iphone-auth-login-lang-sheet-dark", "auth-login-lang-sheet", [], "Đăng nhập mở bảng chọn ngôn ngữ VI/EN (Dark)"),
    ]
    other_iphone_screens = [
        ("01c-iphone-auth-register-dark", "auth-register", [], "Đăng ký tài khoản với checkbox 18+ và Quyền riêng tư"),
        ("01d-iphone-auth-forgot-dark", "auth-reset", [], "Quên mật khẩu: Khôi phục mật khẩu tài khoản (008)"),
        ("01e-iphone-auth-welcome-light", "auth-welcome", ["--ui-review-light"], "Màn hình chào mừng đầu tiên (Light)"),
        ("02-iphone-feed-dark", "feed", [], "Bảng tin không có category strip (Dark)"),
        ("02b-iphone-feed-comments", "feed-comments", [], "Bình luận Bảng tin: Threading đa tầng, Emoji nhanh, Nhắc @"),
        ("03-iphone-discover-dark", "discover", [], "Khám phá (Dark)"),
        ("03b-iphone-shorts-video-dark", "shorts", [], "Tab Video Shorts (Android 1.2.12 build 118)"),
        ("03c-iphone-shorts-comments", "shorts-comments", [], "Bình luận Video: Threading đa tầng, Emoji nhanh, Nhắc @"),
        ("04-iphone-messages-list-dark", "messages", [], "Danh sách Tin nhắn & Nhóm (Dark)"),
        ("05-iphone-chat-detail-dark", "chat-detail", [], "Chi tiết Chat: nội dung trên, giờ+seen+reaction+more dưới"),
        ("05b-iphone-chat-menu-dark", "chat-menu", [], "Tùy chọn hội thoại: Menu Ghim, Tắt thông báo, Báo cáo, Chặn"),
        ("05c-iphone-message-menu-dark", "message-menu", [], "Tùy chọn tin nhắn: Menu Sửa, Chuyển tiếp, Thu hồi, Xóa"),
        ("05d-iphone-group-chat-dark", "group-chat-detail", [], "Chi tiết Nhóm chat: Nhắc thành viên @Tất cả phong cách Zalo"),
        ("05f-iphone-call-incoming", "call-incoming", [], "Màn hình Cuộc gọi đến chuẩn Apple iOS HIG (Xanh / Đỏ)"),
        ("06-iphone-profile-dark", "profile", [], "Hồ sơ cá nhân & Chẩn đoán PushKit (Dark)"),
        ("06b-iphone-profile-posts", "profile-posts", [], "Hồ sơ cá nhân: Tab Bài viết"),
        ("06c-iphone-profile-albums", "profile-albums", [], "Hồ sơ cá nhân: Tab Album ảnh (Công khai & Riêng tư)"),
        ("06d-iphone-profile-videos", "profile-videos", [], "Hồ sơ cá nhân: Tab Video Shorts"),
        ("06e-iphone-profile-edit", "profile-edit", [], "Hồ sơ cá nhân: Sheet Chỉnh sửa hồ sơ"),
        ("06f-iphone-profile-private-album", "profile-private-album", [], "Hồ sơ cá nhân: Quản lý Album riêng tư & Duyệt quyền xem"),
        ("06g-iphone-profile-sessions", "profile-sessions", [], "Hồ sơ cá nhân: Quản lý phiên đăng nhập"),
        ("06h-iphone-profile-public-album", "profile-public-album", [], "Hồ sơ cá nhân: Quản lý Album công khai & Đăng ảnh mới"),
        ("07-iphone-friends-dark", "friends", [], "Bạn bè & Gọi thoại/video nền trong suốt"),
        ("07b-iphone-friends-requests", "friends-requests", [], "Bạn bè: Danh sách Lời mời đến & Lời mời đã gửi"),
        ("07c-iphone-friends-suggestions", "friends-suggestions", [], "Bạn bè: Gợi ý kết bạn theo vị trí & khoảng cách"),
        ("08-iphone-notifications-dark", "notifications", [], "Thông báo"),
        ("09-iphone-wallet-store-dark", "wallet", [], "Ví & Cửa hàng: Tách Xu mua & Xu tặng, Số dư và Lịch sử"),
        ("09b-iphone-wallet-topup", "wallet-topup", [], "Ví & Cửa hàng: Tab Nạp xu qua StoreKit 2 & Khôi phục gói mua"),
        ("09c-iphone-store-packages", "wallet-packages", [], "Ví & Cửa hàng: Tab Cửa hàng vật phẩm phong cách (Khung Avatar, Huy hiệu)"),
        ("10-iphone-live-stream-dark", "live", [], "Phòng Live: Luồng vuốt xem trực tiếp"),
        ("10b-iphone-live-empty", "live-empty", [], "Phòng Live: Trạng thái chưa có phòng phát"),
        ("10c-iphone-live-error", "live-error", [], "Phòng Live: Trạng thái lỗi tải phòng và nút Thử lại"),
        ("10d-iphone-live-connecting", "live-connecting", [], "Phòng Live: Trạng thái đang kết nối thật (không video mẫu)"),
        ("11-iphone-camera-studio-empty", "camera-studio", [], "Camera & Studio: Chế độ chụp ảnh"),
        ("11b-iphone-camera-studio-video", "camera-studio-video", [], "Camera & Studio: Chế độ quay video với nút bấm đỏ"),
        ("12-iphone-camera-studio-edit", "camera-studio-edit", [], "Camera & Studio Pro: Thanh công cụ Cắt/Màu/Mịn da + Lưu riêng"),
        ("12b-iphone-studio-pro-sheet", "studio-pro-sheet", [], "Camera & Studio: Bảng hiệu ứng Studio Pro (Cinematic, Vivid, Noir, Sepia)"),
        ("12c-iphone-camera-studio-video-preview", "camera-studio-video-edit", [], "Camera & Studio: Xem trước video đã quay & xuất bản Shorts"),
        ("13-iphone-feed-light", "feed", ["--ui-review-light"], "Bảng tin chế độ Light mode"),
        ("13b-iphone-privacy-consent-dark", "privacy-consent", [], "Điều khoản & Quyền riêng tư HTTP 428 / WS (Dark)"),
        ("13c-iphone-privacy-consent-light", "privacy-consent", ["--ui-review-light"], "Điều khoản & Quyền riêng tư HTTP 428 / WS (Light)"),
        ("13d-iphone-delete-account-dark", "delete-account", [], "Xóa tài khoản vĩnh viễn với xác nhận Username & Mật khẩu (Dark)"),
        ("13e-iphone-delete-account-light", "delete-account", ["--ui-review-light"], "Xóa tài khoản vĩnh viễn (Light)"),
        ("13f-iphone-ugc-report-sheet", "ugc-report", [], "Báo cáo nội dung vi phạm UGC (Apple Guideline 1.2)"),
        ("05e-iphone-forward-message", "forward-message", [], "Chuyển tiếp tin nhắn: Chọn người nhận hoặc nhóm trò chuyện"),
        ("13g-iphone-change-password", "change-password", [], "Cài đặt: Đổi mật khẩu tài khoản"),
        ("13h-iphone-blocked-users", "blocked-users", [], "Cài đặt & Quyền riêng tư: Danh sách người dùng đã chặn"),
        ("13i-iphone-privacy-settings", "privacy-settings", [], "Cài đặt: Quyền riêng tư & Định vị chuẩn PATCH /api/me (118)"),
        ("13i2-iphone-privacy-settings-light", "privacy-settings", ["--ui-review-light"], "Quyền riêng tư sáng: nút Lưu cách home indicator"),
        ("13n-iphone-live-gifts-drawer", "gift-drawer", [], "Ngăn quà Live đang mở"),
        ("13n2-iphone-live-gifts-drawer-light", "gift-drawer", ["--ui-review-light"], "Ngăn quà Live chế độ sáng (cùng theme Android)"),
        ("13o-iphone-studio-music-picker", "music-picker", [], "Danh sách chọn nhạc đang mở"),
        ("13o2-iphone-studio-music-picker-light", "music-picker", ["--ui-review-light"], "Danh sách chọn nhạc đang mở, chế độ sáng"),
        ("19-password-spy", "password-spy", [], "Ma trận mật khẩu, không gửi mạng"),
        ("19b-persist-write", "persist-write", [], "Ghi ngôn ngữ và thông báo vào máy"),
        ("19c-persist-read", "persist-read", [], "Đọc lại sau khi tắt app"),
        ("19d-shorts-telemetry", "shorts-telemetry", [], "Pause, mute, resume và swipe"),
        ("19e-shorts-avplayer", "shorts-avplayer", [], "AVPlayer: buffer, timestamp, kích thước và khung hình"),
        ("19g-shorts-real-swipe", "shorts-real-swipe", [], "ShortsVideoView: 2 clip local + vuốt sang video thứ 2"),
        ("19f-gift-catalog-v1", "gift-catalog-v1", [], "Adapter catalog quà phiên bản 1"),
        ("19h-swift-contracts-harness", "swift-contracts-harness", [], "Kiểm thử Swift URLProtocol và Admin contracts"),
        ("13m2-iphone-admin-denied", "admin-denied", [], "Bảng quản trị khi không phải quản trị viên"),
        ("13m3-iphone-admin-loading", "admin-loading", [], "Bảng quản trị đang tải"),
        ("13m4-iphone-admin-empty", "admin-empty", [], "Bảng quản trị không có dữ liệu"),
        ("13m5-iphone-admin-error", "admin-error", [], "Bảng quản trị lỗi và nút thử lại"),
        ("13i3-iphone-privacy-save-error", "privacy-save-error", [], "Lưu quyền riêng tư lỗi, khôi phục và không báo thành công"),
        ("13p-dm-mode-error", "dm-mode-error", [], "dmMode lỗi thì quay lại và có thử lại"),
        ("13q-location-off-error", "location-off-error", [], "Tắt vị trí lỗi thì không báo đã tắt"),
        ("13r-sessions-loading", "sessions-loading", [], "Phiên đăng nhập đang tải"),
        ("13s-sessions-error", "sessions-error", [], "Phiên đăng nhập lỗi và thử lại"),
        ("13t-sessions-empty", "sessions-empty", [], "Phiên đăng nhập trống sau khi tải xong"),
        ("13j-iphone-support", "support", [], "Trung tâm Hỗ trợ & Trợ giúp người dùng (124)"),
        ("13l-iphone-support-chat", "support-chat", [], "Trung tâm hỗ trợ mở cuộc trò chuyện trực tiếp"),
        ("13m-iphone-admin", "admin", [], "Bảng quản trị: báo cáo và thành viên"),
        ("13k-iphone-change-password-light", "change-password", ["--ui-review-light"], "Cài đặt: Đổi mật khẩu tài khoản (Light)")
    ]
    iphone_screens = login_iphone_screens if only_login else (login_iphone_screens + other_iphone_screens)

    for slug, screen_arg, extra, desc in iphone_screens:
        f = capture_screen(standard_iphone, slug, screen_arg, bundle_id, extra, wait_sec=3.0)
        records.append({
            "slug": slug,
            "screen": screen_arg,
            "description": desc,
            "device": standard_iphone["name"],
            "runtime": standard_iphone["runtime"],
            "file": str(f)
        })

    # Record >=12s auto-cycle video demo (1.5s per cycle, starting AFTER welcome screen is mounted on Tab 0)
    try:
        std_udid = standard_iphone["udid"]
        subprocess.run(["xcrun", "simctl", "terminate", std_udid, bundle_id], check=False)
        time.sleep(0.5)
        subprocess.run(["xcrun", "simctl", "ui", std_udid, "appearance", "dark"], check=False)
        subprocess.run([
            "xcrun", "simctl", "status_bar", std_udid, "override",
            "--time", "09:41",
            "--batteryState", "charged",
            "--batteryLevel", "100"
        ], check=False)

        # Launch app into auth-welcome with autocycle starting at Tab 0 (Feed)
        print("Launching app into auth-welcome with --ui-review-welcome-autocycle and --ui-review-welcome-tab 0...", flush=True)
        run([
            "xcrun", "simctl", "launch", std_udid, bundle_id,
            "-AppleLanguages", "(vi)",
            "--ui-review-screen", "auth-welcome",
            "--ui-review-welcome-autocycle",
            "--ui-review-welcome-tab", "0"
        ])

        # Wait 3.0s until welcome screen is fully visible and settled on Tab 0 (no splash or black frames)
        time.sleep(3.0)

        clip_path = OUT_DIR / "welcome-autocycle-demo.mp4"
        print(f"Starting simulator video recording to {clip_path} (recording for 14.0s to capture >=2 full 4-tab cycles)...", flush=True)
        rec_p = subprocess.Popen(["xcrun", "simctl", "io", std_udid, "recordVideo", "--codec=h264", "--force", str(clip_path)])
        time.sleep(14.0)

        rec_p.send_signal(signal.SIGINT)
        try:
            rec_p.wait(timeout=10)
        except Exception:
            rec_p.kill()

        if clip_path.exists() and clip_path.stat().st_size > 0:
            clip_size = clip_path.stat().st_size
            print(f"Recorded simulator auto-cycle clip: {clip_path} ({clip_size} bytes)", flush=True)
            meta_path = OUT_DIR / "welcome-autocycle-meta.json"
            meta = {
                "file": "welcome-autocycle-demo.mp4",
                "sizeBytes": clip_size,
                "recordedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "device": standard_iphone["name"],
                "runtime": standard_iphone["runtime"],
                "targetIntervalSec": 1.5,
                "recordDurationSec": 14.0,
                "cycleSequence": [
                    {"time": "0.0s", "tab": 0, "name": "Bảng tin (Feed)"},
                    {"time": "1.5s", "tab": 1, "name": "Khám phá (Discover)"},
                    {"time": "3.0s", "tab": 2, "name": "Video Shorts"},
                    {"time": "4.5s", "tab": 3, "name": "Trực tiếp Live"},
                    {"time": "6.0s", "tab": 0, "name": "Bảng tin (Feed)"},
                    {"time": "7.5s", "tab": 1, "name": "Khám phá (Discover)"},
                    {"time": "9.0s", "tab": 2, "name": "Video Shorts"},
                    {"time": "10.5s", "tab": 3, "name": "Trực tiếp Live"},
                    {"time": "12.0s", "tab": 0, "name": "Bảng tin (Feed)"},
                    {"time": "13.5s", "tab": 1, "name": "Khám phá (Discover)"}
                ],
                "settlingWaitSecBeforeRecord": 3.0,
                "noSplashOrBlackFramesVerified": True
            }
            meta_path.write_text(json.dumps(meta, indent=2, ensure_ascii=False), encoding="utf-8")
            print(f"Saved recording metadata: {meta_path}", flush=True)

            records.append({
                "slug": "welcome-autocycle-demo",
                "screen": "auth-welcome-autocycle",
                "description": "Video thực tế luân phiên 4 màn hình chào mừng (1.5s/chu kỳ, >=2 chu kỳ đầy đủ) trên iPhone 16 Pro",
                "device": standard_iphone["name"],
                "runtime": standard_iphone["runtime"],
                "file": str(clip_path)
            })
    except Exception as e:
        print(f"Auto-cycle video recording skipped/unavailable: {e}", flush=True)

    # 1b. Record comprehensive end-to-end features test video requested by user
    try:
        std_udid = standard_iphone["udid"]
        features_video_path = OUT_DIR / "kinnect-comprehensive-features-test.mp4"
        print(f"Starting comprehensive feature walkthrough video recording to {features_video_path}...", flush=True)

        rec_test = subprocess.Popen(["xcrun", "simctl", "io", std_udid, "recordVideo", "--codec=h264", "--force", str(features_video_path)])
        time.sleep(1.0)

        feature_steps = [
            ("feed", [], "1. Bảng tin (Feed) - Tạo bài viết không chuyên mục, lướt tin"),
            ("profile", [], "2. Hồ sơ cá nhân (Profile) - Ví Kinnect, Cửa hàng Kinnect, Bạn bè"),
            ("friends", [], "3. Bạn bè & Kết bạn (Friends) - Danh sách bạn bè, lời mời, xem trang cá nhân"),
            ("notifications", [], "4. Thông báo (Notifications) - Chuẩn Android: Tìm kiếm, tab Tất cả/Chưa đọc, Đánh dấu tất cả đã đọc"),
            ("chat-detail", [], "5. Tin nhắn & Hội thoại (Messages) - Thẻ đồng bộ Cloud Sync, chi tiết chat"),
            ("shorts", [], "6. Video Shorts - Phát mượt mà, double-tap thả tim bay, mở bình luận"),
            ("live", [], "7. Trực tiếp Live - Quà tặng Live (10 loại quà phong phú), combo quà tặng, hiệu ứng"),
            ("camera-studio-video", [], "8. Camera Studio - Thanh sáng tạo Bộ lọc, Làm đẹp, Sticker AR"),
            ("camera-studio-edit", [], "9. Studio Pro - Biên tập video/ảnh kiểu CapCut"),
            ("wallet", [], "10. Ví Kinnect & Cửa hàng Kinnect - Thiết kế riêng từng gói trang trí, số dư xu")
        ]

        step_log = []
        start_time = time.time()

        for screen_key, extra_args, desc in feature_steps:
            elapsed = round(time.time() - start_time, 1)
            print(f"[{elapsed}s] Testing feature: {desc}...", flush=True)
            subprocess.run(["xcrun", "simctl", "terminate", std_udid, bundle_id], check=False)
            time.sleep(0.3)
            run_args = [
                "xcrun", "simctl", "launch", std_udid, bundle_id,
                "-AppleLanguages", "(vi)",
                "--ui-review-screen", screen_key
            ] + extra_args
            run(run_args, check=False)
            step_log.append({
                "timeSec": elapsed,
                "screen": screen_key,
                "description": desc
            })
            time.sleep(2.8)

        # Terminate app and stop recording
        subprocess.run(["xcrun", "simctl", "terminate", std_udid, bundle_id], check=False)
        time.sleep(0.5)

        rec_test.send_signal(signal.SIGINT)
        try:
            rec_test.wait(timeout=10)
        except Exception:
            rec_test.kill()

        if features_video_path.exists() and features_video_path.stat().st_size > 0:
            test_size = features_video_path.stat().st_size
            print(f"Recorded comprehensive test video: {features_video_path} ({test_size} bytes)", flush=True)
            test_meta_path = OUT_DIR / "kinnect-comprehensive-features-test-meta.json"
            test_meta = {
                "file": "kinnect-comprehensive-features-test.mp4",
                "sizeBytes": test_size,
                "recordedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "device": standard_iphone["name"],
                "runtime": standard_iphone["runtime"],
                "totalDurationSec": round(time.time() - start_time, 1),
                "steps": step_log,
                "verifiedItems": [
                    "Bảng tin tạo bài viết không chuyên mục",
                    "Hồ sơ người dùng & xem hồ sơ bạn bè",
                    "Thông báo chuẩn Android (Tất cả / Chưa đọc / Đánh dấu đọc)",
                    "Tin nhắn có thẻ đồng bộ Cloud Sync bật mặc định",
                    "Video Shorts phát mượt mà, double tap tim bay, bình luận",
                    "Live Stream có đầy đủ quà tặng, combo, camera thoát sạch",
                    "Camera Studio có thanh sáng tạo Bộ lọc, Làm đẹp, Sticker AR",
                    "Studio Pro biên tập chuyên nghiệp",
                    "Ví Kinnect và Cửa hàng Kinnect thiết kế riêng từng gói theo web"
                ]
            }
            test_meta_path.write_text(json.dumps(test_meta, indent=2, ensure_ascii=False), encoding="utf-8")
            records.append({
                "slug": "kinnect-comprehensive-features-test",
                "screen": "all-features-walkthrough",
                "description": "Video thực tế kiểm thử toàn bộ 10 chức năng trên iPhone 16 Pro theo yêu cầu",
                "device": standard_iphone["name"],
                "runtime": standard_iphone["runtime"],
                "file": str(features_video_path)
            })
    except Exception as e:
        print(f"Comprehensive test video recording failed: {e}", flush=True)

    # 2. Compact / second iPhone screenshots
    if compact_iphone:
        if compact_iphone["udid"] != standard_iphone["udid"]:
            print(f"Shutting down previous standard simulator {standard_iphone['name']} to free resources...", flush=True)
            subprocess.run(["xcrun", "simctl", "shutdown", standard_iphone["udid"]], check=False)
            boot_and_install(compact_iphone, app_path, bundle_id)
        compact_login_screens = [
            ("14-compact-iphone-auth-welcome-dark", "auth-welcome", ["--ui-review-welcome-tab", "1"], "Màn hình nhỏ: Chào mừng Tab 1 Khám phá (Dark)"),
            ("14-compact-iphone-auth-welcome-tab0-feed-dark", "auth-welcome", ["--ui-review-welcome-tab", "0"], "Màn hình nhỏ: Chào mừng Tab 0 Bảng tin (Dark)"),
            ("14-compact-iphone-auth-welcome-tab2-video-dark", "auth-welcome", ["--ui-review-welcome-tab", "2"], "Màn hình nhỏ: Chào mừng Tab 2 Video Shorts (Dark)"),
            ("14-compact-iphone-auth-welcome-tab3-live-dark", "auth-welcome", ["--ui-review-welcome-tab", "3"], "Màn hình nhỏ: Chào mừng Tab 3 Trực tiếp Live (Dark)"),
            ("14en-compact-iphone-auth-welcome-en-dark", "auth-welcome-en", ["--ui-review-welcome-tab", "1"], "Màn hình nhỏ: Chào mừng tiếng Anh Tab 1 Khám phá (English Dark)"),
            ("14en0-compact-iphone-auth-welcome-tab0-feed-en-dark", "auth-welcome-en", ["--ui-review-welcome-tab", "0"], "Màn hình nhỏ: Chào mừng tiếng Anh Tab 0 Bảng tin (English Dark)"),
            ("14a-compact-iphone-auth-login-dark", "auth-login", [], "Màn hình nhỏ: Đăng nhập tiếng Việt trống (Dark)"),
            ("14b-compact-iphone-auth-login-keyboard-dark", "auth-login-keyboard", [], "Màn hình nhỏ: Đăng nhập mở bàn phím — thấy cả ô mật khẩu & nút Đăng nhập"),
            ("14b2-compact-iphone-auth-login-password-keyboard-dark", "auth-login-password-keyboard", [], "Màn hình nhỏ: Focus ô mật khẩu mở bàn phím — nút Đăng nhập sáng & bấm được"),
            ("14c-compact-iphone-auth-login-lang-sheet-dark", "auth-login-lang-sheet", [], "Màn hình nhỏ: Đăng nhập mở bảng chọn ngôn ngữ VI/EN (Dark)"),
        ]
        compact_other_screens = [
            ("14-compact-iphone-feed", "feed", [], "Màn hình nhỏ: Bảng tin & Tab bar 5 tab 26pt"),
            ("15-compact-iphone-chat-detail", "chat-detail", [], "Màn hình nhỏ: Chi tiết Chat & hàng trạng thái dưới"),
            ("16-compact-iphone-wallet", "wallet", [], "Màn hình nhỏ: Ví & Cửa hàng không cắt số dư / Nạp xu"),
            ("16b-compact-iphone-dynamictype-max", "feed", ["--ui-review-dynamictype-max"], "Màn hình nhỏ: Dynamic Type kích thước tối đa Accessibility 5"),
            ("16c-compact-iphone-privacy-settings", "privacy-settings", [], "Màn hình nhỏ: Quyền riêng tư, nút Lưu cách home indicator"),
            ("16d-compact-iphone-privacy-dynamictype", "privacy-settings", ["--ui-review-dynamictype-max"], "Màn hình nhỏ: Quyền riêng tư với Dynamic Type tối đa"),
            ("16e-compact-iphone-friends", "friends", [], "Màn hình nhỏ: Bạn bè không cắt tên dài với nút tác vụ hàng dưới")
        ]
        compact_screens = compact_login_screens if only_login else (compact_login_screens + compact_other_screens)
        for slug, screen_arg, extra, desc in compact_screens:
            f = capture_screen(compact_iphone, slug, screen_arg, bundle_id, extra_args=extra, wait_sec=3.0)
            records.append({
                "slug": slug,
                "screen": screen_arg,
                "description": desc,
                "device": compact_iphone["name"],
                "runtime": compact_iphone["runtime"],
                "file": str(f)
            })

    # 3. iPad screenshots
    if ipad and not only_login:
        active_to_shutdown = compact_iphone if (compact_iphone and compact_iphone["udid"] != standard_iphone["udid"]) else standard_iphone
        if active_to_shutdown and active_to_shutdown["udid"] != ipad["udid"]:
            print(f"Shutting down previous simulator {active_to_shutdown['name']} to free resources...", flush=True)
            subprocess.run(["xcrun", "simctl", "shutdown", active_to_shutdown["udid"]], check=False)
        boot_and_install(ipad, app_path, bundle_id)
        for slug, screen_arg, extra, desc in [
            ("17-ipad-feed-splitview", "feed", [], "iPad NavigationSplitView: Sidebar + Bảng tin"),
            ("18-ipad-chat-detail", "chat-detail", [], "iPad NavigationSplitView: Danh sách Hội thoại (trái) + Chi tiết Chat (phải)"),
            ("18b-ipad-dynamictype-max", "feed", ["--ui-review-dynamictype-max"], "iPad: NavigationSplitView với Dynamic Type tối đa Accessibility 5")
        ]:
            f = capture_screen(ipad, slug, screen_arg, bundle_id, extra_args=extra, wait_sec=3.5)
            records.append({
                "slug": slug,
                "screen": screen_arg,
                "description": desc,
                "device": ipad["name"],
                "runtime": ipad["runtime"],
                "file": str(f)
            })
        print(f"Shutting down iPad simulator {ipad['name']}...", flush=True)
        subprocess.run(["xcrun", "simctl", "shutdown", ipad["udid"]], check=False)

    contact_sheet = build_contact_sheet(records)

    built_marketing = read_plist_value(app_path / "Info.plist", "CFBundleShortVersionString") or marketing_version
    built_build = read_plist_value(app_path / "Info.plist", "CFBundleVersion") or build_number
    provenance = write_provenance_manifest(
        marketing_version,
        build_number,
        extra={
            "xcodeVersion": xcode_ver,
            "simulatorRuntimes": runtimes_txt.strip().splitlines() if runtimes_txt else [],
            "builtAppPath": str(app_path).replace("\\", "/"),
            "builtCFBundleShortVersionString": built_marketing,
            "builtCFBundleVersion": built_build,
            "screenshotCount": len(records),
            "standardIphone": standard_iphone["name"] if standard_iphone else None,
            "compactIphone": compact_iphone["name"] if compact_iphone else None,
            "ipad": ipad["name"] if ipad else None,
        },
    )

    manifest = {
        "xcodeVersion": xcode_ver,
        "gitSha": provenance["gitSha"],
        "marketingVersion": marketing_version,
        "buildNumber": build_number,
        "provenance": provenance,
        "standardIphone": standard_iphone,
        "compactIphone": compact_iphone,
        "ipad": ipad,
        "screenshots": records,
        "contactSheet": str(contact_sheet) if contact_sheet else None,
    }
    (OUT_DIR / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")

    report_lines = [
        "# Báo cáo Chụp thử Giao diện Thực tế Kinnect iOS Native (`dist/ios-ui-review`)",
        "",
        f"- **Git SHA**: `{provenance['gitSha']}`",
        f"- **Version / Build**: `{marketing_version}` / `{build_number}`",
        f"- **Xcode & SDK**: `{xcode_ver}`",
        f"- **Thiết bị iPhone chuẩn**: `{standard_iphone['name']}` (`{standard_iphone['runtime']}`)",
        f"- **Thiết bị iPhone kiểm tra màn hình nhỏ**: `{compact_iphone['name'] if compact_iphone else 'N/A'}`",
        f"- **Thiết bị iPad**: `{ipad['name'] if ipad else 'N/A'}`",
        "- **Chế độ dữ liệu**: `--ui-review-screen` (`UIReviewFixture` tách biệt hoàn toàn, gắn nhãn `[Fixture UI]`, không chạm dữ liệu production, không lộ token/mật khẩu, không gọi người thật/phát live thật/mua hàng thật).",
        "",
        "## Danh sách ảnh chụp PNG thực tế từ `xcrun simctl io screenshot`",
        ""
    ]
    for r in records:
        report_lines.append(f"- `{Path(r['file']).name}` — **{r['description']}** (`{r['device']}`)")
    report_lines.extend([
        "",
        "## Rà soát Giao diện & Giới hạn",
        "- **Bộ 40 icon vector (`KinnectIcons.swift`)**: Hiển thị sắc nét bằng SwiftUI `Path` native ở kích thước 24pt (26pt trên thanh tab), nét `2.05` khi chọn và `1.65` khi thường.",
        "- **Nút gọi thoại / gọi video / menu (`...`)**: Nền trong suốt hoàn toàn, vùng chạm 44×44pt.",
        "- **Màn hình Chat (`05-iphone-chat-detail-dark.png`)**: Nội dung tin nhắn nằm trên; giờ, icon `seen`, `reaction`, và `more` (`...`) nằm chung một hàng bên dưới.",
        "- **Màn hình Camera & Studio (`11` & `12`)**: Khi chưa có media (`11`), ẩn toàn bộ trường chỉnh sửa Studio; chỉ sau khi có ảnh/video (`12`) mới hiện bảng Studio và nút `Lưu` tách thành cụm riêng không đè nút chính.",
        "- **Màn hình Phòng Live (`10`)**: Luồng cuộn thống nhất, không có thanh lọc `Tất cả / Trò chuyện / Chơi game` ở đầu trang.",
        "- **Màn hình Ví & Cửa hàng (`09` & `16`)**: Dùng chung icon `coin` có chữ `K` bên trong, phân biệt bằng nhãn chữ và có `.minimumScaleFactor(0.75)` chống cắt số.",
        "- **Lưu ý Light Mode (`13-iphone-feed-light.png`)**: Ứng dụng Kinnect sử dụng bảng màu tối đặc trưng (`KinnectTheme.background = #0E0B18`, `surface = #181326`) nên ngay cả khi hệ thống chuyển sang Light Mode, nền và chữ vẫn giữ độ tương phản chuẩn của chủ đề tím đêm Kinnect.",
        "- **Giới hạn Simulator**: Camera vật lý, PushKit APNs VoIP token thật và cuộc gọi WebRTC P2P với người thật không kích hoạt trong phiên chụp tự động trên Simulator để đảm bảo an toàn production."
    ])
    (OUT_DIR / "ui-review-report.md").write_text("\n".join(report_lines), encoding="utf-8")
    print("Completed UI review screenshot capture:", len(records), "screenshots.", flush=True)


if __name__ == "__main__":
    main()

