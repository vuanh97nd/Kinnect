#!/usr/bin/env python3
"""
Kinnect Android UI Parity Capture Script (49-screen matrix).

Reads `outputs/ui-parity-20261126/parity-matrix.json`, installs or verifies
the specified Play Debug APK on local AVD `Medium_Phone_API_37.0`, captures
`SCR-01.png`..`SCR-48b.png` (plus optional `uiautomator/<ID>.xml`) into the
output directory, verifies PNG integrity + zero fatal crashes + zero duplicate
hashes, writes `manifest-android.json`, and always restores emulator
display/theme/font/app state in `finally`.
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import pathlib
import re
import struct
import subprocess
import sys
import time
from typing import Any

ROOT = pathlib.Path(r"D:\Codex\Kinnect")
ADB = r"C:\Users\ANH\AppData\Local\Android\Sdk\platform-tools\adb.exe"
MATRIX_PATH = ROOT / "outputs" / "ui-parity-20261126" / "parity-matrix.json"
DEFAULT_OUT_DIR = ROOT / "outputs" / "ui-ux-pro-20261127" / "android-after"
PACKAGE = "app.kinnect.live"
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"

PERMISSIONS = [
    "android.permission.CAMERA",
    "android.permission.RECORD_AUDIO",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.ACCESS_COARSE_LOCATION",
    "android.permission.ACCESS_FINE_LOCATION",
]

LONG_WAIT_IDS = {
    "SCR-14",
    "SCR-15",
    "SCR-24",
    "SCR-25",
    "SCR-26",
    "SCR-27",
    "SCR-28",
    "SCR-29",
    "SCR-30",
    "SCR-31",
    "SCR-37",
    "SCR-39",
    "SCR-43",
    "SCR-44",
}


def run_adb(*args: str, timeout: int = 30) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [ADB, *args],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=timeout,
    )


def adb_out(*args: str, timeout: int = 30) -> str:
    return run_adb(*args, timeout=timeout).stdout.strip()


def sha256_file(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()


def parse_png_dimensions(data: bytes) -> tuple[int, int]:
    if len(data) < 24 or data[:8] != PNG_MAGIC:
        return (0, 0)
    w, h = struct.unpack(">II", data[16:24])
    return (w, h)


def check_blank_image(path: pathlib.Path) -> tuple[bool, str]:
    """Return (is_ok, detail). Rejects solid-color or corrupt PNGs."""
    data = path.read_bytes()
    if len(data) < 10240 or data[:8] != PNG_MAGIC:
        return False, f"Invalid or tiny PNG ({len(data)} bytes)"
    w, h = parse_png_dimensions(data)
    if w < 300 or h < 300:
        return False, f"Unexpected PNG dimensions {w}x{h}"
    try:
        from PIL import Image

        with Image.open(path) as img:
            rgb = img.convert("RGB")
            extrema = rgb.getextrema()
            # If every channel has min == max, image is completely solid (blank white/black)
            if all(lo == hi for lo, hi in extrema):
                return False, f"Solid single-color frame (extrema={extrema})"
            # Check inner viewport (exclude 120px status/nav bars) for near-solid blank screen
            crop = rgb.crop((0, min(140, h // 6), w, max(h - 140, (h * 5) // 6)))
            small = crop.resize((64, 128))
            colors = small.getcolors(maxcolors=256)
            if colors is not None and len(colors) <= 2:
                return False, f"Near-blank viewport (unique sampled colors={len(colors)})"
    except ImportError:
        pass
    except Exception as exc:
        return False, f"PIL verification failed: {exc}"
    return True, f"OK ({w}x{h}, {len(data)} bytes)"


def dismiss_system_dialogs() -> None:
    try:
        adb_out("shell", "am", "broadcast", "-a", "android.intent.action.CLOSE_SYSTEM_DIALOGS")
        dump = adb_out("shell", "dumpsys", "window", "windows")
        if "Application Not Responding" in dump or "is not responding" in dump:
            adb_out("shell", "input", "keyevent", "66")
            time.sleep(0.4)
            adb_out("shell", "input", "keyevent", "4")
    except Exception:
        pass


def check_window_state() -> tuple[bool, str | None]:
    """Return (in_app, overlay_error)."""
    dump = adb_out("shell", "dumpsys", "window")
    overlay_err: str | None = None
    if "GrantPermissionsActivity" in dump or "permission_controller" in dump:
        overlay_err = "Permission dialog overlay visible"
    elif "Application Not Responding" in dump or "is not responding" in dump:
        overlay_err = "ANR dialog overlay visible"

    focus_lines = [
        line.strip()
        for line in dump.splitlines()
        if "mCurrentFocus" in line or "mFocusedApp" in line
    ]
    in_app = any(PACKAGE in line for line in focus_lines)
    return in_app, overlay_err


def dump_ui_xml() -> str:
    remote = "/sdcard/parity_ui_dump.xml"
    for extra_flag in ([], ["--compressed"]):
        adb_out("shell", "rm", "-f", remote)
        adb_out("shell", "uiautomator", "dump", *extra_flag, remote, timeout=20)
        xml = adb_out("shell", "cat", remote, timeout=15)
        adb_out("shell", "rm", "-f", remote)
        if xml and "<hierarchy" in xml:
            return xml
        time.sleep(0.3)
    return ""


def find_node_center(xml: str, query: str) -> tuple[int, int] | None:
    pattern = r'(?:text|content-desc)="([^"]+)"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"'
    for match in re.finditer(pattern, xml):
        if match.group(1).strip() == query:
            x1, y1, x2, y2 = (
                int(match.group(2)),
                int(match.group(3)),
                int(match.group(4)),
                int(match.group(5)),
            )
            return ((x1 + x2) // 2, (y1 + y2) // 2)
    return None


def tap_node(query: str, retries: int = 3, delay: float = 0.8) -> tuple[bool, str]:
    for attempt in range(retries):
        xml = dump_ui_xml()
        pt = find_node_center(xml, query)
        if pt is not None:
            adb_out("shell", "input", "tap", str(pt[0]), str(pt[1]))
            return True, f"Tapped '{query}' at {pt}"
        if attempt < retries - 1:
            time.sleep(delay)
    return False, f"Node '{query}' not found in UI hierarchy"


def capture_screencap(target: pathlib.Path) -> None:
    proc = subprocess.run([ADB, "exec-out", "screencap", "-p"], capture_output=True, timeout=30)
    if proc.returncode == 0 and proc.stdout.startswith(PNG_MAGIC) and len(proc.stdout) > 10240:
        target.write_bytes(proc.stdout)
        return
    # Fallback via /sdcard if exec-out failed
    remote = f"/sdcard/{target.name}"
    adb_out("shell", "screencap", "-p", remote)
    run_adb("pull", remote, str(target), timeout=30)
    adb_out("shell", "rm", "-f", remote)


def grant_permissions() -> None:
    for perm in PERMISSIONS:
        run_adb("shell", "pm", "grant", PACKAGE, perm)


def ensure_apk_installed(apk_path: pathlib.Path) -> dict[str, Any]:
    if not apk_path.exists():
        raise FileNotFoundError(f"APK not found: {apk_path}")
    local_sha = sha256_file(apk_path).lower()
    pkg_line = adb_out("shell", "pm", "path", PACKAGE)
    device_sha = ""
    if pkg_line.startswith("package:"):
        pkg_path = pkg_line.replace("package:", "").strip().splitlines()[0]
        sha_out = adb_out("shell", "sha256sum", pkg_path)
        device_sha = sha_out.split()[0].lower() if sha_out else ""

    installed_fresh = False
    if device_sha != local_sha:
        print(f"[Install] Installing {apk_path.name} (device_sha={device_sha[:12] or 'none'} != local={local_sha[:12]})...")
        res = run_adb("install", "-r", "-d", str(apk_path), timeout=120)
        if res.returncode != 0:
            raise RuntimeError(f"adb install failed: {res.stdout}\n{res.stderr}")
        installed_fresh = True
        pkg_line = adb_out("shell", "pm", "path", PACKAGE)
        pkg_path = pkg_line.replace("package:", "").strip().splitlines()[0]
        sha_out = adb_out("shell", "sha256sum", pkg_path)
        device_sha = sha_out.split()[0].lower() if sha_out else ""
    else:
        print(f"[Install] Verified installed APK matches {apk_path.name} (sha256={local_sha[:12]}...)")

    return {
        "apkPath": str(apk_path),
        "apkSha256": local_sha,
        "deviceApkSha256": device_sha,
        "hashMatch": local_sha == device_sha,
        "installedFresh": installed_fresh,
    }


def launch_main(
    dest: str,
    fixture: bool,
    reset_fixture: bool = False,
    extra: dict[str, Any] | None = None,
) -> None:
    adb_out("shell", "am", "force-stop", PACKAGE)
    time.sleep(0.35)
    cmd = [
        "shell",
        "am",
        "start",
        "-W",
        "-n",
        f"{PACKAGE}/.MainActivity",
        "--ez",
        "ui_review_fixture",
        "true" if fixture else "false",
        "-e",
        "commerce_destination",
        dest,
        "-e",
        "app_language",
        "vi",
    ]
    if reset_fixture:
        cmd.extend(["--ez", "reset_fixture_state", "true"])
    if extra:
        for key, value in extra.items():
            k = str(key)
            if isinstance(value, bool):
                cmd.extend(["--ez", k, "true" if value else "false"])
            elif isinstance(value, int):
                cmd.extend(["--ei", k, str(value)])
            elif isinstance(value, float):
                cmd.extend(["--ef", k, str(value)])
            elif value is not None:
                cmd.extend(["-e", k, str(value)])
    res = run_adb(*cmd, timeout=30)
    if res.returncode != 0 or "SecurityException" in res.stderr:
        raise RuntimeError(f"am start failed for dest={dest}: {res.stdout} {res.stderr}")


def restore_device_defaults() -> None:
    print("[Cleanup] Restoring emulator theme/font/display and clearing app state...")
    try:
        adb_out("shell", "cmd", "uimode", "night", "no")
        adb_out("shell", "settings", "put", "system", "font_scale", "1.0")
        adb_out("shell", "wm", "size", "reset")
        adb_out("shell", "wm", "density", "reset")
        adb_out("shell", "am", "force-stop", PACKAGE)
        adb_out("shell", "rm", "-f", "/data/local/tmp/kinnect_fixture")
        adb_out("shell", "pm", "clear", PACKAGE)
    except Exception as exc:
        print(f"[Cleanup Warning] {exc}")


def check_logcat_crashes() -> list[str]:
    out = adb_out("logcat", "-d", "-s", "AndroidRuntime:E", "FATAL:E", timeout=20)
    crashes: list[str] = []
    if not out:
        return crashes
    lines = out.splitlines()
    for i, line in enumerate(lines):
        if "FATAL EXCEPTION" in line or PACKAGE in line:
            snippet = " | ".join(lines[i : min(len(lines), i + 5)])
            crashes.append(snippet)
    return crashes


def detect_git_commit_sha() -> str:
    try:
        res = subprocess.run(
            ["git", "-C", str(ROOT), "rev-parse", "HEAD"],
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=10,
        )
        if res.returncode == 0:
            return res.stdout.strip()
    except Exception:
        pass
    return ""


def main() -> int:
    parser = argparse.ArgumentParser(description="Capture Android UI parity screenshots (49-screen matrix).")
    parser.add_argument(
        "--only",
        help="Comma-separated screen IDs to re-capture and merge into manifest-android.json (e.g. SCR-02,SCR-44,SCR-45)",
    )
    parser.add_argument("--apk", required=True, help="Path to the Play Debug APK to install and capture.")
    parser.add_argument("--matrix", help=f"Override parity-matrix.json path (default: {MATRIX_PATH}).")
    parser.add_argument("--out-dir", help=f"Override output directory for screenshots and manifest (default: {DEFAULT_OUT_DIR}).")
    parser.add_argument("--commit-sha", default="", help="Git commit SHA of the built APK (auto-detected if omitted).")
    parser.add_argument("--build-run-id", default="", help="Build/Milestone run ID for provenance.")
    parser.add_argument("--source", default="avd-emulator", help="Capture source label (default: avd-emulator).")
    parser.add_argument(
        "--capture-uiautomator",
        action="store_true",
        help="Also dump UI hierarchy XML via uiautomator to <out-dir>/uiautomator/<ID>.xml.",
    )
    args = parser.parse_args()

    apk_path = pathlib.Path(args.apk)
    matrix_path = pathlib.Path(args.matrix) if args.matrix else MATRIX_PATH
    out_dir = pathlib.Path(args.out_dir) if args.out_dir else DEFAULT_OUT_DIR
    manifest_path = out_dir / "manifest-android.json"
    commit_sha = args.commit_sha.strip() or detect_git_commit_sha()
    build_run_id = args.build_run_id.strip()
    capture_source = args.source.strip() or "avd-emulator"
    only_ids = {s.strip() for s in args.only.split(",") if s.strip()} if args.only else None

    if not matrix_path.exists():
        print(f"[Error] Missing parity matrix: {matrix_path}", file=sys.stderr)
        return 1

    matrix = json.loads(matrix_path.read_text(encoding="utf-8"))
    screens: list[dict[str, Any]] = matrix["screens"]
    out_dir.mkdir(parents=True, exist_ok=True)
    uiauto_dir = out_dir / "uiautomator"
    if args.capture_uiautomator:
        uiauto_dir.mkdir(parents=True, exist_ok=True)

    existing_by_id: dict[str, dict[str, Any]] = {}
    if only_ids and manifest_path.exists():
        prev = json.loads(manifest_path.read_text(encoding="utf-8"))
        for item in prev.get("screens", []):
            existing_by_id[item["id"]] = item

    total_screens = len(screens)
    print(f"[Init] Loaded {total_screens} screen definitions from {matrix_path}")
    if only_ids:
        print(f"[Init] Selective recapture mode: {sorted(only_ids)}")
    run_adb("wait-for-device", timeout=30)
    for _ in range(30):
        if adb_out("shell", "getprop", "sys.boot_completed") == "1":
            break
        time.sleep(1)

    apk_info = ensure_apk_installed(apk_path)
    apk_info["commitSha"] = commit_sha
    if build_run_id:
        apk_info["buildRunId"] = build_run_id
    apk_info["source"] = capture_source

    device_meta = {
        "serial": adb_out("get-serialno"),
        "model": adb_out("shell", "getprop", "ro.product.model"),
        "androidRelease": adb_out("shell", "getprop", "ro.build.version.release"),
        "apiLevel": adb_out("shell", "getprop", "ro.build.version.sdk"),
        "buildType": adb_out("shell", "getprop", "ro.build.type"),
        "physicalSize": adb_out("shell", "wm", "size"),
        "physicalDensity": adb_out("shell", "wm", "density"),
    }
    print(f"[Device] {device_meta['model']} API {device_meta['apiLevel']} ({device_meta['buildType']})")

    # Clear app data + fixture file BEFORE SCR-01..05 so auth/splash screens are genuinely logged out
    adb_out("shell", "rm", "-f", "/data/local/tmp/kinnect_fixture")
    adb_out("shell", "pm", "clear", PACKAGE)
    time.sleep(0.5)
    grant_permissions()
    dismiss_system_dialogs()

    # Reset display/theme baseline
    adb_out("shell", "cmd", "uimode", "night", "no")
    adb_out("shell", "settings", "put", "system", "font_scale", "1.0")
    adb_out("shell", "wm", "size", "reset")
    adb_out("shell", "wm", "density", "reset")
    time.sleep(0.8)

    # Clear logcat buffer before starting captures
    run_adb("logcat", "-c")

    current_theme = "light"
    current_font = "1.0"
    current_narrow = False

    entries: list[dict[str, Any]] = []
    seen_hashes: dict[str, str] = {}
    crashes: list[str] = []

    try:
        for idx, scr in enumerate(screens, start=1):
            scr_id: str = scr["id"]
            if only_ids and scr_id not in only_ids:
                if scr_id in existing_by_id:
                    prev_entry = existing_by_id[scr_id]
                    entries.append(prev_entry)
                    prev_sha = prev_entry.get("sha256", "")
                    if prev_sha:
                        seen_hashes.setdefault(prev_sha, scr_id)
                continue

            name: str = scr["name"]
            theme: str = scr.get("theme", "light")
            font_scale: str = str(scr.get("fontScale", "1.0"))
            narrow: bool = bool(scr.get("narrow", False))
            android_cfg: dict[str, Any] = scr["android"]
            dest: str = android_cfg["dest"]
            fixture: bool = bool(android_cfg.get("fixture", True))
            extra: dict[str, Any] = android_cfg.get("extra", {}) or {}
            out_file = out_dir / f"{scr_id}.png"
            note = ""

            # Synchronize device theme / font_scale / narrow viewport
            if theme != current_theme:
                adb_out("shell", "cmd", "uimode", "night", "yes" if theme == "dark" else "no")
                current_theme = theme
                time.sleep(0.8)

            if font_scale != current_font:
                adb_out("shell", "settings", "put", "system", "font_scale", font_scale)
                current_font = font_scale
                time.sleep(0.8)

            if narrow != current_narrow:
                if narrow:
                    adb_out("shell", "wm", "size", "720x1520")
                    adb_out("shell", "wm", "density", "320")
                else:
                    adb_out("shell", "wm", "size", "reset")
                    adb_out("shell", "wm", "density", "reset")
                current_narrow = narrow
                time.sleep(1.0)

            # Route execution cleanly via exported MainActivity + handleExtras(dest, extra)
            reset_fix = scr_id == "SCR-06"
            launch_main(dest, fixture=fixture, reset_fixture=reset_fix, extra=extra)
            if scr_id in ("SCR-44", "SUP-44-DARK", "SUP-44-AX") or dest == "store_packages":
                # Wait for StoreActivity's Google Play unavailable LENGTH_LONG Toast to fade out cleanly
                wait_s = 6.2
            elif scr_id == "SCR-45":
                # Ensure any delayed Google Play Toast from StoreActivity (SCR-44) has completely faded
                wait_s = 5.0
            elif scr_id == "SCR-02":
                # Capture Welcome intro card 1 before the auto-advance carousel crossfade
                wait_s = 1.4
            elif scr_id == "SCR-01":
                wait_s = 2.0
            elif scr_id in LONG_WAIT_IDS:
                wait_s = 3.4
            else:
                wait_s = 2.6
            time.sleep(wait_s)

            # Verify foreground & capture
            in_app, overlay_err = check_window_state()
            if not in_app:
                dismiss_system_dialogs()
                time.sleep(0.6)
                in_app, overlay_err = check_window_state()

            capture_screencap(out_file)
            ok_img, img_detail = check_blank_image(out_file)
            raw = out_file.read_bytes()
            w, h = parse_png_dimensions(raw)
            sha = hashlib.sha256(raw).hexdigest()

            uiauto_rel: str | None = None
            if args.capture_uiautomator:
                xml_text = dump_ui_xml()
                if xml_text:
                    xml_path = uiauto_dir / f"{scr_id}.xml"
                    xml_path.write_text(xml_text, encoding="utf-8")
                    uiauto_rel = f"uiautomator/{scr_id}.xml"
                else:
                    note = (note + " | " if note else "") + "uiautomator dump empty"

            dup_of = seen_hashes.get(sha)
            if not in_app:
                status = "failed"
                note = (note + " | " if note else "") + "App not in foreground at capture time"
            elif overlay_err:
                status = "blocked"
                note = (note + " | " if note else "") + overlay_err
            elif not ok_img:
                status = "failed"
                note = (note + " | " if note else "") + img_detail
            elif dup_of:
                status = "duplicate_warning"
                note = (note + " | " if note else "") + f"Identical SHA-256 to {dup_of}"
            else:
                status = "captured"
                seen_hashes[sha] = scr_id

            if not note:
                note = img_detail

            print(
                f"[{idx:02d}/{total_screens:02d}] {scr_id} ({dest}, {theme}"
                f"{', 1.3x' if font_scale != '1.0' else ''}{', narrow' if narrow else ''}): "
                f"{status} — {len(raw)} bytes ({w}x{h})"
            )

            entry: dict[str, Any] = {
                "id": scr_id,
                "name": name,
                "group": scr.get("group", ""),
                "file": out_file.name,
                "bytes": len(raw),
                "width": w,
                "height": h,
                "sha256": sha,
                "theme": theme,
                "fontScale": float(font_scale),
                "narrow": narrow,
                "source": capture_source,
                "dest": dest,
                "extra": extra,
                "status": status,
                "note": note,
            }
            if uiauto_rel:
                entry["uiautomatorFile"] = uiauto_rel
            entries.append(entry)
    finally:
        try:
            crashes = check_logcat_crashes()
        except Exception as exc:
            crashes = [f"logcat check error: {exc}"]
        restore_device_defaults()

    captured_cnt = sum(1 for e in entries if e["status"] == "captured")
    dup_cnt = sum(1 for e in entries if e["status"] == "duplicate_warning")
    failed_cnt = sum(1 for e in entries if e["status"] in ("failed", "blocked"))
    uiauto_cnt = sum(1 for e in entries if e.get("uiautomatorFile"))
    sizes = [e["bytes"] for e in entries if e["bytes"] > 0]
    min_bytes = min(sizes) if sizes else 0
    max_bytes = max(sizes) if sizes else 0

    manifest = {
        "runId": matrix.get("runId", "ui-parity-20261126"),
        "platform": "android",
        "capturedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "language": "vi",
        "provenance": {
            **apk_info,
            "device": device_meta,
        },
        "summary": {
            "total": len(entries),
            "captured": captured_cnt,
            "duplicateWarnings": dup_cnt,
            "failedOrBlocked": failed_cnt,
            "uiautomatorCaptured": uiauto_cnt,
            "minBytes": min_bytes,
            "maxBytes": max_bytes,
            "fatalCrashes": len(crashes),
            "crashSamples": crashes[:5],
        },
        "screens": entries,
    }

    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
    print(
        f"\n[Done] Captured {captured_cnt}/{len(entries)} screens "
        f"(dup={dup_cnt}, failed={failed_cnt}, crashes={len(crashes)}, "
        f"bytes={min_bytes}..{max_bytes}). Manifest: {manifest_path}"
    )
    return 0 if failed_cnt == 0 and len(crashes) == 0 else 2


if __name__ == "__main__":
    sys.exit(main())
