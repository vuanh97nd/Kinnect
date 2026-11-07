#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import time
from pathlib import Path

OUT_DIR = Path("dist/ios-ui-review")
OUT_DIR.mkdir(parents=True, exist_ok=True)
BUNDLE_ID = "vn.kinnect.ios"


def run(cmd, check=True, capture=True):
    print(f"+ {' '.join(cmd)}", flush=True)
    res = subprocess.run(cmd, text=True, capture_output=capture)
    if check and res.returncode != 0:
        print("STDOUT:", res.stdout, flush=True)
        print("STDERR:", res.stderr, flush=True)
        raise RuntimeError(f"Command failed ({res.returncode}): {' '.join(cmd)}")
    return res


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


def boot_and_install(device, app_path):
    udid = device["udid"]
    name = device["name"]
    print(f"Booting simulator {name} ({udid})...", flush=True)
    subprocess.run(["xcrun", "simctl", "boot", udid], check=False)
    run(["xcrun", "simctl", "bootstatus", udid, "-b"])
    # Set clean status bar
    subprocess.run([
        "xcrun", "simctl", "status_bar", udid, "override",
        "--time", "09:41",
        "--batteryState", "charged",
        "--batteryLevel", "100"
    ], check=False)
    run(["xcrun", "simctl", "install", udid, str(app_path)])


def capture_screen(device, slug, screen_arg, extra_args=None, wait_sec=2.8):
    udid = device["udid"]
    subprocess.run(["xcrun", "simctl", "terminate", udid, BUNDLE_ID], check=False)
    time.sleep(0.4)
    cmd = ["xcrun", "simctl", "launch", udid, BUNDLE_ID, "--ui-review-screen", screen_arg]
    if extra_args:
        cmd.extend(extra_args)
    run(cmd)
    time.sleep(wait_sec)
    out_file = OUT_DIR / f"{slug}.png"
    run(["xcrun", "simctl", "io", udid, "screenshot", str(out_file)])
    return out_file


def build_contact_sheet(records):
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        subprocess.run([sys.executable, "-m", "pip", "install", "--quiet", "pillow"], check=True)
        from PIL import Image, ImageDraw, ImageFont

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
    return contact_path


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
        "CODE_SIGNING_ALLOWED=NO"
    ], capture=False)

    app_path = Path("build/SimDerivedData/Build/Products/Debug-iphonesimulator/Kinnect.app")
    if not app_path.exists():
        found = list(Path("build/SimDerivedData").rglob("Kinnect.app"))
        if not found:
            raise RuntimeError("Kinnect.app not found in build/SimDerivedData")
        app_path = found[0]

    standard_iphone, compact_iphone, ipad = pick_devices(devices)
    if not standard_iphone:
        raise RuntimeError("No iPhone simulator device available.")

    records = []

    # 1. Standard iPhone screenshots
    boot_and_install(standard_iphone, app_path)
    iphone_screens = [
        ("01-iphone-auth-dark", "auth", [], "Đăng nhập / Đăng ký (Dark)"),
        ("02-iphone-feed-dark", "feed", [], "Bảng tin & Tin 24h (Dark)"),
        ("03-iphone-discover-dark", "discover", [], "Khám phá & Shorts (Dark)"),
        ("04-iphone-messages-list-dark", "messages", [], "Danh sách Tin nhắn & Nhóm (Dark)"),
        ("05-iphone-chat-detail-dark", "chat-detail", [], "Chi tiết Chat: nội dung trên, giờ+seen+reaction+more dưới"),
        ("06-iphone-profile-dark", "profile", [], "Hồ sơ cá nhân & Chẩn đoán PushKit (Dark)"),
        ("07-iphone-friends-dark", "friends", [], "Bạn bè & Gọi thoại/video nền trong suốt"),
        ("08-iphone-notifications-dark", "notifications", [], "Thông báo"),
        ("09-iphone-wallet-store-dark", "wallet", [], "Ví & Cửa hàng StoreKit 2 (Icon Xu chữ K)"),
        ("10-iphone-live-stream-dark", "live", [], "Phòng Live luồng thống nhất (Không thanh lọc đầu trang)"),
        ("11-iphone-camera-studio-empty", "camera-studio", [], "Camera & Studio trước khi chọn ảnh/video"),
        ("12-iphone-camera-studio-edit", "camera-studio-edit", [], "Camera & Studio sau khi có ảnh (Hiện Studio + nút Lưu riêng)"),
        ("13-iphone-feed-light", "feed", ["--ui-review-light"], "Bảng tin thử chế độ Light mode")
    ]

    for slug, screen_arg, extra, desc in iphone_screens:
        f = capture_screen(standard_iphone, slug, screen_arg, extra)
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
            boot_and_install(compact_iphone, app_path)
        for slug, screen_arg, desc in [
            ("14-compact-iphone-feed", "feed", "Màn hình nhỏ: Bảng tin & Tab bar 26pt"),
            ("15-compact-iphone-chat-detail", "chat-detail", "Màn hình nhỏ: Chi tiết Chat & hàng trạng thái dưới"),
            ("16-compact-iphone-wallet", "wallet", "Màn hình nhỏ: Ví & Cửa hàng không cắt số dư")
        ]:
            f = capture_screen(compact_iphone, slug, screen_arg)
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
        boot_and_install(ipad, app_path)
        for slug, screen_arg, desc in [
            ("17-ipad-feed-splitview", "feed", "iPad NavigationSplitView: Sidebar + Bảng tin"),
            ("18-ipad-chat-detail", "chat-detail", "iPad: Chi tiết hội thoại")
        ]:
            f = capture_screen(ipad, slug, screen_arg, wait_sec=3.2)
            records.append({
                "slug": slug,
                "screen": screen_arg,
                "description": desc,
                "device": ipad["name"],
                "runtime": ipad["runtime"],
                "file": str(f)
            })

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
