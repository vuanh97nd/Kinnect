#!/usr/bin/env python3
"""Capture five focused fixture screens; does not prove live calls or APNs delivery."""
import importlib.util
import json
import os
import plistlib
import subprocess
from pathlib import Path

HELPER_PATH = Path(__file__).with_name("capture-simulator-screenshots.py")
spec = importlib.util.spec_from_file_location("kinnect_capture", HELPER_PATH)
capture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(capture)
capture.OUT_DIR = Path("dist/ios-parity-fixes")
capture.OUT_DIR.mkdir(parents=True, exist_ok=True)


def main():
    devices = capture.ensure_xcode_with_simulator_runtime()
    standard, compact, _ = capture.pick_devices(devices)
    if standard is None:
        raise RuntimeError("No iPhone simulator is available.")
    compact = compact or standard
    print(f"Focused review: compact={compact['name']}, standard={standard['name']}", flush=True)
    capture.run([
        "xcodebuild", "build", "-project", "ios/Kinnect.xcodeproj",
        "-scheme", "Kinnect", "-configuration", "Debug",
        "-destination", f"id={compact['udid']}",
        "-derivedDataPath", "build/ParitySimDerivedData",
        "CODE_SIGN_IDENTITY=", "CODE_SIGNING_REQUIRED=NO",
        "CODE_SIGNING_ALLOWED=NO", "ENABLE_DEBUG_DYLIB=NO",
    ], capture=False)
    app = Path("build/ParitySimDerivedData/Build/Products/Debug-iphonesimulator/Kinnect.app")
    if not app.exists():
        raise RuntimeError("Built simulator application was not found.")
    bundle = capture.get_bundle_id(app)
    capture.run(["codesign", "--force", "--deep", "--sign", "-", str(app)])
    screens = [
        (compact, "01-compact-call-incoming", "call-incoming"),
        (compact, "02-compact-call-outgoing", "call-outgoing"),
        (compact, "03-compact-store", "store"),
        (compact, "06-compact-call-connected", "call-connected"),
        (standard, "04-standard-profile-posts", "profile-posts"),
        (standard, "05-standard-shorts-header", "shorts"),
    ]
    installed = set()
    records = []
    try:
        for device, slug, screen in screens:
            if device["udid"] not in installed:
                capture.boot_and_install(device, app, bundle)
                installed.add(device["udid"])
            path = capture.capture_screen(device, slug, screen, bundle, wait_sec=4.0)
            records.append({
                "screen": screen, "file": path.name,
                "device": device["name"], "udid": device["udid"],
                "runtime": device["runtime"], "fixture": True,
            })
    finally:
        for udid in installed:
            subprocess.run(["xcrun", "simctl", "terminate", udid, bundle], check=False)
            subprocess.run(["xcrun", "simctl", "shutdown", udid], check=False)
    with (app / "Info.plist").open("rb") as file:
        info = plistlib.load(file)
    (capture.OUT_DIR / "capture-info.json").write_text(json.dumps({
        "commit": os.environ.get("GITHUB_SHA"),
        "runId": os.environ.get("GITHUB_RUN_ID"),
        "version": info.get("CFBundleShortVersionString"),
        "build": info.get("CFBundleVersion"),
        "screens": records,
        "scope": "Simulator fixture layout captures only; real media, calls, and APNs require device verification.",
    }, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
