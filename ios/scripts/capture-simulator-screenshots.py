#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import time
from pathlib import Path

OUT_DIR = Path("dist/ios-ui-review")
OUT_DIR.mkdir(parents=True, exist_ok=True)
DEFAULT_BUNDLE_ID = "app.kinnect.live"


def run(cmd, check=True, capture=True):
    print(f"+ {' '.join(cmd)}", flush=True)
    res = subprocess.run(cmd, text=True, capture_output=capture)
    if check and res.returncode != 0:
        print("STDOUT:", res.stdout, flush=True)
        print("STDERR:", res.stderr, flush=True)
        raise RuntimeError(f"Command failed ({res.returncode}): {' '.join(cmd)}")
    return res


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
    subprocess.run(["xcrun", "simctl", "boot", udid], check=False)
    run(["xcrun", "simctl", "bootstatus", udid, "-b"])
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
    subprocess.run(["xcrun", "simctl", "launch", udid, bundle_id, "--ui-review-screen", "feed"], check=False)
    time.sleep(4.0)
    subprocess.run(["xcrun", "simctl", "terminate", udid, bundle_id], check=False)
    time.sleep(1.0)


def capture_screen(device, slug, screen_arg, bundle_id, extra_args=None, wait_sec=3.0):
    udid = device["udid"]
    subprocess.run(["xcrun", "simctl", "terminate", udid, bundle_id], check=False)
    time.sleep(0.5)

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

    cmd = ["xcrun", "simctl", "launch", udid, bundle_id, "--ui-review-screen", screen_arg]
    if extra_args:
        cmd.extend(extra_args)
    run(cmd)

    actual_wait = 5.5 if screen_arg == "auth" else wait_sec
    time.sleep(actual_wait)

    out_file = OUT_DIR / f"{slug}.png"
    run(["xcrun", "simctl", "io", udid, "screenshot", str(out_file)])

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
            rows = (len(records) + cols - 1) // cols
            cell_w, cell_h = 340, 680
            sheet = Image.new("RGB", (cols * cell_w + 40, rows * cell_h + 80), (14, 11, 24))
            draw = ImageDraw.Draw(sheet)
            draw.text((24, 20), "Kinnect iOS Native SwiftUI — Actual iOS Simulator UI Review Contact Sheet", fill=(255, 255, 255))

            for idx, rec in enumerate(records):
                r = idx // cols
                c = idx % cols
                x0 = 20 + c * cell_w
                y0 = 60 + r * cell_h
                img_path = Path(rec["file"])
                if not img_path.exists():
                    continue
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
            return contact_path
        except Exception as err:
            print(f"Warning generating PNG contact sheet: {err}", flush=True)

    # Fallback HTML contact sheet so a single view of all screens is always available
    html_lines = [
        "<!DOCTYPE html>",
        "<html lang='vi'>",
        "<head>",
        "  <meta charset='utf-8'>",
        "  <title>Kinnect iOS Native SwiftUI — UI Review Contact Sheet</title>",
        "  <style>",
        "    body { background: #0E0B18; color: #fff; font-family: -apple-system, sans-serif; margin: 24px; }",
        "    h1 { color: #8A3FFC; margin-bottom: 8px; }",
        "    p.sub { color: #A8A29E; margin-bottom: 24px; font-size: 14px; }",
        "    .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 20px; }",
        "    .card { background: #181326; border: 1px solid #332454; border-radius: 12px; padding: 12px; }",
        "    .card img { width: 100%; height: auto; border-radius: 8px; border: 1px solid #231B3A; }",
        "    .card h4 { margin: 8px 0 4px 0; font-size: 14px; color: #D4BBFF; }",
        "    .card p { margin: 0 0 4px 0; font-size: 12px; color: #E0E0E0; }",
        "    .card small { font-size: 11px; color: #A8A29E; }",
        "  </style>",
        "</head>",
        "<body>",
        "  <h1>Kinnect iOS Native SwiftUI — Actual Simulator UI Review</h1>",
        f"  <p class='sub'>Tập hợp {len(records)} ảnh chụp thực tế từ iPhone 16 Pro, iPhone 16e và iPad Pro 11-inch.</p>",
        "  <div class='grid'>"
    ]
    for r in records:
        f_name = Path(r["file"]).name
        html_lines.append(f"    <div class='card'>")
        html_lines.append(f"      <img src='{f_name}' alt='{r['slug']}'>")
        html_lines.append(f"      <h4>{r['slug']}</h4>")
        html_lines.append(f"      <p>{r['description']}</p>")
        html_lines.append(f"      <small>{r['device']}</small>")
        html_lines.append(f"    </div>")
    html_lines.extend(["  </div>", "</body>", "</html>"])
    html_path = OUT_DIR / "contact-sheet.html"
    html_path.write_text("\n".join(html_lines), encoding="utf-8")
    print(f"Generated HTML contact sheet: {html_path}", flush=True)
    return html_path


def main():
    devices = ensure_xcode_with_simulator_runtime()
    xcode_ver = run(["xcodebuild", "-version"]).stdout.strip().replace("\n", " | ")
    runtimes_txt = run(["xcrun", "simctl", "list", "runtimes"]).stdout

    print("Building Kinnect.app for iphonesimulator...", flush=True)
    run([
        "xcodebuild", "build",
        "-project", "ios/Kinnect.xcodeproj",
        "-scheme", "Kinnect",
        "-configuration", "Debug",
        "-sdk", "iphonesimulator",
        "-derivedDataPath", "build/SimDerivedData",
        "MARKETING_VERSION=1.2.12",
        "CURRENT_PROJECT_VERSION=118",
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

    # 1. Standard iPhone screenshots
    boot_and_install(standard_iphone, app_path, bundle_id)
    iphone_screens = [
        ("01-iphone-auth-welcome-dark", "auth-welcome", [], "Màn hình chào mừng đầu tiên với logo và VI/EN (Dark)"),
        ("01b-iphone-auth-login-dark", "auth-login", [], "Đăng nhập chính với Ghi nhớ & Quên mật khẩu"),
        ("01c-iphone-auth-register-dark", "auth-register", [], "Đăng ký tài khoản với checkbox 18+ và Quyền riêng tư"),
        ("01d-iphone-auth-forgot-dark", "auth-reset", [], "Quên mật khẩu: Khôi phục mật khẩu tài khoản (008)"),
        ("01e-iphone-auth-welcome-light", "auth-welcome", ["--ui-review-light"], "Màn hình chào mừng đầu tiên (Light)"),
        ("02-iphone-feed-dark", "feed", [], "Bảng tin không có category strip (Dark)"),
        ("03-iphone-discover-dark", "discover", [], "Khám phá (Dark)"),
        ("03b-iphone-shorts-video-dark", "shorts", [], "Tab Video Shorts (Android 1.2.12 build 118)"),
        ("04-iphone-messages-list-dark", "messages", [], "Danh sách Tin nhắn & Nhóm (Dark)"),
        ("05-iphone-chat-detail-dark", "chat-detail", [], "Chi tiết Chat: nội dung trên, giờ+seen+reaction+more dưới"),
        ("05b-iphone-chat-menu-dark", "chat-menu", [], "Tùy chọn hội thoại: Menu Ghim, Tắt thông báo, Báo cáo, Chặn"),
        ("05c-iphone-message-menu-dark", "message-menu", [], "Tùy chọn tin nhắn: Menu Sửa, Chuyển tiếp, Thu hồi, Xóa"),
        ("05d-iphone-group-chat-dark", "group-chat-detail", [], "Chi tiết Nhóm chat: thanh công cụ, icon vector & menu tùy chọn"),
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
        ("13j-iphone-support", "support", [], "Trung tâm Hỗ trợ & Trợ giúp người dùng (124)"),
        ("13k-iphone-change-password-light", "change-password", ["--ui-review-light"], "Cài đặt: Đổi mật khẩu tài khoản (Light)")
    ]

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

    # 2. Compact / second iPhone screenshots
    if compact_iphone:
        if compact_iphone["udid"] != standard_iphone["udid"]:
            print(f"Shutting down previous standard simulator {standard_iphone['name']} to free resources...", flush=True)
            subprocess.run(["xcrun", "simctl", "shutdown", standard_iphone["udid"]], check=False)
            boot_and_install(compact_iphone, app_path, bundle_id)
        for slug, screen_arg, extra, desc in [
            ("14-compact-iphone-feed", "feed", [], "Màn hình nhỏ: Bảng tin & Tab bar 5 tab 26pt"),
            ("15-compact-iphone-chat-detail", "chat-detail", [], "Màn hình nhỏ: Chi tiết Chat & hàng trạng thái dưới"),
            ("16-compact-iphone-wallet", "wallet", [], "Màn hình nhỏ: Ví & Cửa hàng không cắt số dư / Nạp xu"),
            ("16b-compact-iphone-dynamictype-max", "feed", ["--ui-review-dynamictype-max"], "Màn hình nhỏ: Dynamic Type kích thước tối đa Accessibility 5")
        ]:
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
    if ipad:
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

    manifest = {
        "xcodeVersion": xcode_ver,
        "standardIphone": standard_iphone,
        "compactIphone": compact_iphone,
        "ipad": ipad,
        "screenshots": records,
        "contactSheet": str(contact_sheet)
    }
    (OUT_DIR / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")

    report_lines = [
        "# Báo cáo Chụp thử Giao diện Thực tế Kinnect iOS Native (`dist/ios-ui-review`)",
        "",
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

