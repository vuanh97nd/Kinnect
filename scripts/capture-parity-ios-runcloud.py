#!/usr/bin/env python3
"""
Capture all UI-parity iOS screens (49-screen matrix) in a single run.cloud iOS Simulator session.

Flow:
  1. Load RUN_CLOUD_API_KEY / RUN_CLOUD_API_TOKEN / RUN_CLOUD_API_URL (with Windows
     HKCU\\Environment fallback when missing from the inherited process environment).
  2. Verify authentication via `runcloud account --json`.
  3. Create ONE remote Apple Silicon iOS Simulator session (`iPhone 17e`, iOS `26.5`)
     with `--inactivity-timeout 3m --hard-timeout 25m` and install the built arm64
     Simulator `.app.tar.gz` (or pre-uploaded `--asset`).
  4. Inside `try ... finally`:
     - Grant privacy permissions (camera, microphone, notifications, photos, location)
       for `app.kinnect.live` so no system dialog blocks captures.
     - Iterate every entry in `parity-matrix.json`:
       * Switch `runcloud ios appearance <id> light|dark --json` when theme changes.
       * Switch screen live via `#if DEBUG` deep-link:
         `runcloud ios open-url --id <id> "kinnect://ui-review?screen=<slug>&light=<1|0>&dyn=<1|0>" --json`
       * Wait settle time (2.2s-3.0s) and capture PNG via `runcloud ios screenshot`.
       * Optionally capture `runcloud ios accessibility-tree` when `--capture-a11y` is set.
       * Record per-screen `sha256` and check for duplicate hashes.
     - Write `manifest-ios.json` with `appSha256`, `commitSha`, `buildRunId`, `total`, and `duplicateWarnings`.
  5. `finally`: ALWAYS release the session via `runcloud ios delete <id> --json`
     so no remote simulator credit is ever leaked.

Security rules:
  - NEVER prints or logs API keys, tokens, signed viewer URLs, or tunnel URLs.
  - Bypasses Windows `cmd.exe` shim parsing by invoking `node <run-cloud.js>` directly
    when available, preventing `&` query-parameter splitting in `kinnect://` URLs.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import shutil
import signal
import struct
import subprocess
import sys
import time
from pathlib import Path
from typing import Any
from urllib.parse import quote


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_MATRIX_PATH = REPO_ROOT / "outputs" / "ui-parity-20261126" / "parity-matrix.json"
DEFAULT_OUT_DIR = REPO_ROOT / "outputs" / "ui-parity-20261126" / "ios"
DEFAULT_BUNDLE_ID = "app.kinnect.live"
DEFAULT_DEVICE_NAME = "iPhone 17e"
DEFAULT_PLATFORM_VERSION = "26.5"
DEFAULT_INACTIVITY_TIMEOUT = "3m"
DEFAULT_HARD_TIMEOUT = "25m"

PERMISSIONS_TO_GRANT = [
    "camera",
    "microphone",
    "notifications",
    "photos",
    "location",
]

SENSITIVE_ENV_KEYS = (
    "RUN_CLOUD_API_KEY",
    "RUN_CLOUD_API_TOKEN",
    "RUN_CLOUD_API_URL",
)

SENSITIVE_JSON_KEY_RE = re.compile(
    r"(token|secret|key|password|authorization|cookie|viewer|signed|stream|tunnel|wss?url|embedurl)",
    re.IGNORECASE,
)
SIGNED_URL_RE = re.compile(r"https?://[^\s\"']+[?&](?:token|sig|signature|auth|key)=[^\s\"']+", re.IGNORECASE)
BEARER_RE = re.compile(r"(Bearer\s+)[A-Za-z0-9._\-~+/]+=*", re.IGNORECASE)
SECRET_TOKEN_RE = re.compile(r"\b(?:rc|rk|sk|pk)_[A-Za-z0-9_\-]{12,}\b")


def load_runcloud_env() -> tuple[dict[str, str], list[str]]:
    """
    Build subprocess environment with Windows User Registry (HKCU\\Environment)
    fallback for RUN_CLOUD_API_KEY / RUN_CLOUD_API_TOKEN / RUN_CLOUD_API_URL.
    Never logs or exposes secret values.
    """
    env = os.environ.copy()
    loaded_from_registry: list[str] = []

    if sys.platform == "win32":
        try:
            import winreg  # type: ignore

            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as reg_key:
                for key_name in SENSITIVE_ENV_KEYS:
                    if env.get(key_name, "").strip():
                        continue
                    try:
                        value, reg_type = winreg.QueryValueEx(reg_key, key_name)
                        if isinstance(value, str):
                            if reg_type == winreg.REG_EXPAND_SZ:
                                value = os.path.expandvars(value)
                            cleaned = value.strip()
                            if cleaned:
                                env[key_name] = cleaned
                                loaded_from_registry.append(key_name)
                    except FileNotFoundError:
                        continue
                    except OSError:
                        continue
        except OSError:
            pass

    return env, loaded_from_registry


def redact_text(text: str, env: dict[str, str] | None = None) -> str:
    """Strip any secret env values, bearer tokens, or signed URLs from text."""
    if not text:
        return ""
    out = text
    if env:
        for key_name in ("RUN_CLOUD_API_KEY", "RUN_CLOUD_API_TOKEN"):
            secret_val = env.get(key_name, "").strip()
            if secret_val and len(secret_val) >= 6:
                out = out.replace(secret_val, "[REDACTED]")
    out = SIGNED_URL_RE.sub("[REDACTED_URL]", out)
    out = BEARER_RE.sub(r"\1[REDACTED]", out)
    out = SECRET_TOKEN_RE.sub("[REDACTED_TOKEN]", out)
    return out


def sanitize_json(obj: Any, env: dict[str, str] | None = None) -> Any:
    """Recursively redact sensitive keys/values before writing or displaying JSON."""
    if isinstance(obj, dict):
        sanitized: dict[str, Any] = {}
        for k, v in obj.items():
            if SENSITIVE_JSON_KEY_RE.search(str(k)):
                sanitized[k] = "[REDACTED]"
            else:
                sanitized[k] = sanitize_json(v, env)
        return sanitized
    if isinstance(obj, list):
        return [sanitize_json(item, env) for item in obj]
    if isinstance(obj, str):
        return redact_text(obj, env)
    return obj


def resolve_runcloud_command() -> list[str]:
    """
    Resolve `runcloud` CLI invocation cleanly across Windows / macOS / Linux.
    On Windows, bypass `runcloud.cmd` and invoke `node <dist/run-cloud.js>` directly
    so `cmd.exe` never splits `&` query parameters inside `kinnect://` deep links.
    """
    which_bin = shutil.which("runcloud")
    if not which_bin and sys.platform == "win32":
        which_bin = shutil.which("runcloud.cmd")

    if not which_bin:
        raise RuntimeError(
            "Không tìm thấy CLI `runcloud` trong PATH. Cài đặt bằng: npm install -g runcloud"
        )

    bin_path = Path(which_bin)
    if sys.platform == "win32" and bin_path.suffix.lower() in (".cmd", ".bat"):
        cli_js = bin_path.parent / "node_modules" / "runcloud" / "dist" / "run-cloud.js"
        if cli_js.is_file():
            local_node = bin_path.parent / "node.exe"
            node_bin = str(local_node) if local_node.is_file() else shutil.which("node")
            if node_bin:
                return [node_bin, str(cli_js)]

    return [str(bin_path)]


def parse_json_output(raw: str) -> Any:
    """Parse JSON from CLI stdout, tolerating leading non-JSON notice lines if any."""
    text = raw.strip()
    if not text:
        return {}
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        for idx, ch in enumerate(text):
            if ch in "{[":
                try:
                    return json.loads(text[idx:])
                except json.JSONDecodeError:
                    continue
        raise


def run_runcloud_json(
    base_cmd: list[str],
    args: list[str],
    env: dict[str, str],
    *,
    timeout_sec: int = 120,
    check: bool = True,
) -> tuple[int, Any, str]:
    """
    Execute a `runcloud ... --json` command and return (returncode, parsed_json, redacted_err).
    Never prints raw unredacted stdout/stderr.
    """
    full_cmd = [*base_cmd, *args]
    try:
        proc = subprocess.run(
            full_cmd,
            env=env,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout_sec,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        msg = f"Lệnh runcloud quá thời gian ({timeout_sec}s): {' '.join(args[:3])}"
        if check:
            raise RuntimeError(msg) from exc
        return 124, {}, msg

    parsed: Any = {}
    if proc.stdout.strip():
        try:
            parsed = parse_json_output(proc.stdout)
        except json.JSONDecodeError:
            parsed = {"rawText": redact_text(proc.stdout.strip()[:400], env)}

    redacted_err = redact_text(proc.stderr.strip(), env)
    if proc.returncode != 0 and check:
        err_detail = ""
        if isinstance(parsed, dict):
            code = parsed.get("code") or parsed.get("errorCode") or ""
            message = parsed.get("message") or parsed.get("error") or ""
            if isinstance(message, dict):
                code = code or message.get("code", "")
                message = message.get("message", "")
            parts = [p for p in (str(code).strip(), redact_text(str(message).strip(), env)) if p]
            err_detail = " - ".join(parts)
        if not err_detail:
            err_detail = redacted_err[:400] or f"exit code {proc.returncode}"
        raise RuntimeError(f"runcloud {' '.join(args[:3])} thất bại: {err_detail}")

    return proc.returncode, parsed, redacted_err


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()


def read_png_dimensions(png_path: Path) -> tuple[int, int, int]:
    """Validate PNG header and return (byte_size, width, height)."""
    data = png_path.read_bytes()
    if len(data) < 24 or data[:8] != b"\x89PNG\r\n\x1a\n":
        raise RuntimeError(f"Ảnh chụp không hợp lệ (không phải PNG): {png_path.name}")
    width, height = struct.unpack(">II", data[16:24])
    return len(data), width, height


def check_account(base_cmd: list[str], env: dict[str, str]) -> dict[str, Any]:
    """Verify run.cloud authentication via `runcloud account --json` before metered calls."""
    rc, data, err = run_runcloud_json(
        base_cmd,
        ["account", "--json"],
        env,
        timeout_sec=30,
        check=False,
    )
    if rc != 0 or not isinstance(data, dict) or data.get("error"):
        detail = err
        if isinstance(data, dict):
            msg = data.get("message") or data.get("error")
            if msg:
                detail = redact_text(str(msg), env)
        raise RuntimeError(
            "Chưa đăng nhập run.cloud hoặc thông tin xác thực không hợp lệ. "
            "Hãy chạy `runcloud login` hoặc thiết lập `RUN_CLOUD_API_KEY` rồi thử lại. "
            f"(Chi tiết: {detail or f'exit {rc}'})"
        )
    return data


def extract_session_id(create_payload: Any) -> str:
    if isinstance(create_payload, dict):
        for candidate in (
            create_payload.get("id"),
            create_payload.get("sessionId"),
            (create_payload.get("session") or {}).get("id")
            if isinstance(create_payload.get("session"), dict)
            else None,
        ):
            if isinstance(candidate, str) and candidate.strip():
                return candidate.strip()
    raise RuntimeError("Không trích xuất được `id` phiên từ kết quả `runcloud ios create --json`.")


def _find_open_in_button(tree: Any) -> tuple[bool, tuple[float, float] | None]:
    """Detect iOS 26 SpringBoard 'Open in \"Kinnect\"?' dialog in accessibility-tree."""
    has_open_in_title = False
    open_bounds: dict[str, Any] | None = None
    root_w, root_h = 0.0, 0.0

    def walk(node: Any) -> None:
        nonlocal has_open_in_title, open_bounds, root_w, root_h
        if isinstance(node, list):
            for child in node:
                walk(child)
            return
        if not isinstance(node, dict):
            return
        frame = node.get("frame") or node.get("bounds") or {}
        if isinstance(frame, dict):
            w = float(frame.get("width", frame.get("w", 0)) or 0)
            h = float(frame.get("height", frame.get("h", 0)) or 0)
            if w > root_w:
                root_w = w
            if h > root_h:
                root_h = h
        label = str(node.get("label") or node.get("title") or node.get("value") or "").strip()
        role = str(node.get("role") or node.get("type") or "").lower()
        low = label.lower()
        if "open in" in low or ("mở trong" in low and "kinnect" in low):
            has_open_in_title = True
        if label in ("Open", "Mở") and ("button" in role or not role):
            if isinstance(frame, dict) and (frame.get("width") or frame.get("w")):
                open_bounds = frame
        for key in ("children", "elements", "nodes", "tree", "root", "data"):
            if key in node:
                walk(node[key])

    walk(tree)
    if not has_open_in_title:
        return False, None
    if open_bounds and root_w > 100 and root_h > 100:
        x = float(open_bounds.get("x", 0) or 0) + float(open_bounds.get("width", open_bounds.get("w", 0)) or 0) / 2.0
        y = float(open_bounds.get("y", 0) or 0) + float(open_bounds.get("height", open_bounds.get("h", 0)) or 0) / 2.0
        nx = max(0.05, min(0.95, x / root_w))
        ny = max(0.05, min(0.95, y / root_h))
        return True, (nx, ny)
    return True, (0.688, 0.535)


def dismiss_open_in_prompt(
    base_cmd: list[str],
    env: dict[str, str],
    session_id: str,
    *,
    force_tap_if_undetected: bool = False,
) -> bool:
    """Dismiss iOS SpringBoard 'Open in \"Kinnect\"?' alert if visible. Returns True if tapped."""
    rc, tree, _ = run_runcloud_json(
        base_cmd,
        ["ios", "accessibility-tree", "--json", session_id],
        env,
        timeout_sec=25,
        check=False,
    )
    detected, coords = _find_open_in_button(tree) if rc == 0 else (False, None)
    if detected and coords:
        tx, ty = coords
        run_runcloud_json(
            base_cmd,
            ["ios", "tap", "--json", session_id, f"{tx:.4f}", f"{ty:.4f}"],
            env,
            timeout_sec=20,
            check=False,
        )
        return True
    if force_tap_if_undetected:
        # SpringBoard system alerts on iOS 26.5 may sit outside the app's accessibility root;
        # tap the verified blue "Open" pill center (0.688, 0.535) cleanly.
        run_runcloud_json(
            base_cmd,
            ["ios", "tap", "--json", session_id, "0.688", "0.535"],
            env,
            timeout_sec=20,
            check=False,
        )
        return True
    return False


def grant_app_permissions(
    base_cmd: list[str],
    env: dict[str, str],
    session_id: str,
    bundle_id: str,
) -> list[str]:
    """Grant required iOS privacy permissions up front so no system alerts interrupt screenshots."""
    rc, _, err = run_runcloud_json(
        base_cmd,
        [
            "ios",
            "permissions",
            "grant",
            "--app",
            bundle_id,
            "--json",
            session_id,
            *PERMISSIONS_TO_GRANT,
        ],
        env,
        timeout_sec=45,
        check=False,
    )
    if rc == 0:
        return list(PERMISSIONS_TO_GRANT)

    print(
        f"[warn] Cấp hàng loạt quyền trả mã {rc} ({err[:180]}); thử cấp từng quyền...",
        flush=True,
    )
    granted: list[str] = []
    for perm in PERMISSIONS_TO_GRANT:
        p_rc, _, p_err = run_runcloud_json(
            base_cmd,
            ["ios", "permissions", "grant", "--app", bundle_id, "--json", session_id, perm],
            env,
            timeout_sec=30,
            check=False,
        )
        if p_rc == 0:
            granted.append(perm)
        else:
            print(f"[warn] Không cấp được quyền `{perm}`: {p_err[:160]}", flush=True)
    return granted


def delete_session_safely(
    base_cmd: list[str],
    env: dict[str, str],
    session_id: str,
) -> bool:
    """Release the remote iOS simulator session (with one retry on transient failure)."""
    for attempt in range(1, 3):
        rc, _, err = run_runcloud_json(
            base_cmd,
            ["ios", "delete", "--json", session_id],
            env,
            timeout_sec=45,
            check=False,
        )
        if rc == 0:
            print(f"[cleanup] Đã giải phóng phiên run.cloud iOS ({session_id}).", flush=True)
            return True
        print(
            f"[warn] Lần {attempt} xóa phiên {session_id} thất bại (exit {rc}): {err[:200]}",
            flush=True,
        )
        time.sleep(1.5)
    print(
        f"[ERROR] Không thể tự động xóa phiên {session_id}! Hãy kiểm tra và chạy `runcloud ios delete {session_id}` ngay.",
        file=sys.stderr,
        flush=True,
    )
    return False


def build_ui_review_url(screen_slug: str, is_light: bool, is_dyn: bool) -> str:
    safe_slug = quote(screen_slug.strip(), safe="-_.")
    light_val = "1" if is_light else "0"
    dyn_val = "1" if is_dyn else "0"
    return f"kinnect://ui-review?screen={safe_slug}&light={light_val}&dyn={dyn_val}"


def settle_duration_for(screen_slug: str, base_seconds: float, is_first: bool) -> float:
    if is_first:
        return max(3.0, base_seconds + 0.6)
    if (
        screen_slug in ("feed", "shorts", "video", "live", "live-empty", "live-room", "live-gifts", "studio-music-picker", "studio-pro-sheet")
        or screen_slug.startswith("camera-studio")
    ):
        return max(2.6, base_seconds)
    return max(2.2, base_seconds)


def write_manifest(manifest_path: Path, payload: dict[str, Any]) -> None:
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = manifest_path.with_suffix(".json.tmp")
    tmp_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    tmp_path.replace(manifest_path)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Chụp toàn bộ 49 màn hình iOS Parity trên run.cloud iOS Simulator qua deep-link #if DEBUG."
    )
    source = parser.add_mutually_exclusive_group(required=False)
    source.add_argument(
        "--app",
        type=Path,
        help="Đường dẫn tới gói Apple Silicon Simulator .tar.gz / .zip / .app (vd: dist/Kinnect-Simulator-arm64.tar.gz)",
    )
    source.add_argument(
        "--asset",
        type=str,
        help="Tên hoặc ID asset đã upload sẵn lên run.cloud (`--install-asset`)",
    )
    parser.add_argument(
        "--check-only",
        action="store_true",
        help="Chỉ kiểm tra xác thực `runcloud account --json` và thoát (không tạo phiên, không tốn credit).",
    )
    parser.add_argument(
        "--matrix",
        type=Path,
        default=DEFAULT_MATRIX_PATH,
        help=f"Đường dẫn parity-matrix.json (mặc định: {DEFAULT_MATRIX_PATH})",
    )
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=DEFAULT_OUT_DIR,
        help=f"Thư mục xuất ảnh PNG và manifest-ios.json (mặc định: {DEFAULT_OUT_DIR})",
    )
    parser.add_argument(
        "--bundle-id",
        type=str,
        default=DEFAULT_BUNDLE_ID,
        help=f"iOS Bundle Identifier (mặc định: {DEFAULT_BUNDLE_ID})",
    )
    parser.add_argument(
        "--device-name",
        type=str,
        default=DEFAULT_DEVICE_NAME,
        help=f"Tên thiết bị iOS Simulator trên run.cloud (mặc định: {DEFAULT_DEVICE_NAME})",
    )
    parser.add_argument(
        "--platform-version",
        type=str,
        default=DEFAULT_PLATFORM_VERSION,
        help=f"Phiên bản iOS runtime trên run.cloud (mặc định: {DEFAULT_PLATFORM_VERSION})",
    )
    parser.add_argument(
        "--inactivity-timeout",
        type=str,
        default=DEFAULT_INACTIVITY_TIMEOUT,
        help=f"Timeout tự đóng khi rảnh (mặc định: {DEFAULT_INACTIVITY_TIMEOUT})",
    )
    parser.add_argument(
        "--hard-timeout",
        type=str,
        default=DEFAULT_HARD_TIMEOUT,
        help=f"Thời lượng tối đa phiên (mặc định: {DEFAULT_HARD_TIMEOUT})",
    )
    parser.add_argument(
        "--settle-seconds",
        type=float,
        default=2.4,
        help="Thời gian chờ ổn định UI (giây) sau open-url trước khi chụp (mặc định: 2.4s).",
    )
    parser.add_argument(
        "--only",
        type=str,
        default="",
        help="Chỉ chụp các mã màn hình cụ thể cách nhau dấu phẩy (vd: SCR-01,SCR-06,SCR-47).",
    )
    parser.add_argument(
        "--capture-a11y",
        action="store_true",
        help="Đồng thời thu `accessibility-tree --json` cho mỗi màn vào <out-dir>/a11y/<ID>.json.",
    )
    parser.add_argument(
        "--commit-sha",
        type=str,
        default="",
        help="Git commit SHA của bản build iOS Simulator.",
    )
    parser.add_argument(
        "--build-run-id",
        type=str,
        default="",
        help="GitHub Actions run ID của bản build iOS Simulator.",
    )
    parser.add_argument(
        "--app-sha256",
        type=str,
        default="",
        help="SHA-256 của gói .tar.gz/.app (tự tính từ --app nếu bỏ trống).",
    )
    args = parser.parse_args(argv)
    if not args.check_only and not args.app and not args.asset:
        parser.error("Cần truyền `--app <path>` hoặc `--asset <name>` (hoặc `--check-only`).")
    if args.app and not args.app.exists():
        parser.error(f"Không tìm thấy tệp ứng dụng Simulator: {args.app}")
    return args


def _rebuild_manifest_entries(
    all_screens: list[dict[str, Any]],
    records_by_id: dict[str, dict[str, Any]],
) -> tuple[list[dict[str, Any]], int, int, int, list[dict[str, str]]]:
    ordered: list[dict[str, Any]] = []
    seen_hashes: dict[str, str] = {}
    dup_hashes: list[dict[str, str]] = []
    captured_cnt = 0
    failed_cnt = 0

    for item in all_screens:
        sid = str(item.get("id", ""))
        rec = records_by_id.get(sid)
        if not rec:
            continue
        rec_copy = dict(rec)
        rec_sha = str(rec_copy.get("sha256") or "").lower()
        if rec_copy.get("status") == "ok":
            captured_cnt += 1
            if rec_sha:
                if rec_sha in seen_hashes and seen_hashes[rec_sha] != sid:
                    rec_copy["duplicateOf"] = seen_hashes[rec_sha]
                    dup_hashes.append({"id": sid, "duplicateOf": seen_hashes[rec_sha], "sha256": rec_sha})
                else:
                    seen_hashes[rec_sha] = sid
                    rec_copy.pop("duplicateOf", None)
        elif rec_copy.get("status") == "failed":
            failed_cnt += 1
        ordered.append(rec_copy)

    return ordered, captured_cnt, failed_cnt, len(dup_hashes), dup_hashes


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    env, reg_loaded = load_runcloud_env()
    if reg_loaded:
        print(
            f"[auth] Đã nạp fallback từ Windows User Environment (HKCU\\Environment): {', '.join(reg_loaded)}",
            flush=True,
        )

    base_cmd = resolve_runcloud_command()

    # 1. Pre-flight auth check (no metered session yet)
    try:
        account_info = check_account(base_cmd, env)
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr, flush=True)
        return 1

    has_runcloud = account_info.get("runCloud")
    auth_ok_label = f"runCloud={has_runcloud}" if has_runcloud is not None else "authenticated"
    print(f"[auth] Xác thực run.cloud thành công ({auth_ok_label}).", flush=True)

    if args.check_only:
        return 0

    # 2. Load parity matrix
    if not args.matrix.is_file():
        print(f"[ERROR] Không tìm thấy parity-matrix.json tại: {args.matrix}", file=sys.stderr, flush=True)
        return 1

    matrix_data = json.loads(args.matrix.read_text(encoding="utf-8"))
    all_screens = matrix_data.get("screens", [])
    if not isinstance(all_screens, list) or not all_screens:
        print("[ERROR] parity-matrix.json không có danh sách `screens` hợp lệ.", file=sys.stderr, flush=True)
        return 1

    only_filter = {s.strip().upper() for s in args.only.split(",") if s.strip()}
    target_screens = [
        item for item in all_screens
        if not only_filter or str(item.get("id", "")).upper() in only_filter
    ]
    if not target_screens:
        print(f"[ERROR] Không có màn nào khớp `--only {args.only}`.", file=sys.stderr, flush=True)
        return 1

    out_dir: Path = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    a11y_dir = out_dir / "a11y"
    if args.capture_a11y:
        a11y_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = out_dir / "manifest-ios.json"

    records_by_id: dict[str, dict[str, Any]] = {}
    if only_filter and manifest_path.is_file():
        try:
            prev_manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            for prev_rec in prev_manifest.get("screens", []):
                if isinstance(prev_rec, dict) and prev_rec.get("id"):
                    records_by_id[str(prev_rec["id"])] = prev_rec
        except Exception as exc:
            print(f"[warn] Không đọc được manifest cũ để merge --only: {exc}", flush=True)

    started_at = dt.datetime.now(dt.timezone.utc).isoformat()
    app_source_label = args.app.name if args.app else f"asset:{args.asset}"
    app_sha256 = args.app_sha256.strip().lower()
    if not app_sha256 and args.app and args.app.is_file():
        app_sha256 = sha256_file(args.app).lower()

    manifest: dict[str, Any] = {
        "runId": matrix_data.get("runId", "ui-parity"),
        "platform": "ios",
        "runner": "run.cloud iOS Simulator",
        "deviceName": args.device_name,
        "platformVersion": args.platform_version,
        "bundleId": args.bundle_id,
        "appSource": app_source_label,
        "appSha256": app_sha256,
        "commitSha": args.commit_sha.strip(),
        "buildRunId": args.build_run_id.strip(),
        "startedAt": started_at,
        "finishedAt": None,
        "grantedPermissions": [],
        "total": len(target_screens),
        "totalScreens": len(target_screens),
        "capturedCount": 0,
        "failedCount": 0,
        "duplicateWarnings": 0,
        "duplicateHashes": [],
        "screens": [],
    }

    # Handle Ctrl+C / SIGTERM cleanly so `finally` ALWAYS deletes the session
    def _handle_signal(signum: int, _frame: Any) -> None:
        raise KeyboardInterrupt(f"Received signal {signum}")

    signal.signal(signal.SIGINT, _handle_signal)
    if hasattr(signal, "SIGTERM"):
        signal.signal(signal.SIGTERM, _handle_signal)

    # 3. Create ONE metered run.cloud iOS simulator session
    create_args = [
        "ios",
        "create",
        "--device-name",
        args.device_name,
        "--platform-version",
        args.platform_version,
        "--inactivity-timeout",
        args.inactivity_timeout,
        "--hard-timeout",
        args.hard_timeout,
        "--json",
    ]
    if args.app:
        create_args.extend(["--install", str(args.app.resolve())])
    else:
        create_args.extend(["--install-asset", str(args.asset)])

    print(
        f"[session] Đang tạo phiên run.cloud iOS ({args.device_name} / iOS {args.platform_version}, "
        f"inactivity={args.inactivity_timeout}, hard={args.hard_timeout}) và cài {app_source_label}...",
        flush=True,
    )
    _, create_payload, _ = run_runcloud_json(
        base_cmd,
        create_args,
        env,
        timeout_sec=300,
        check=True,
    )
    session_id = extract_session_id(create_payload)
    try:
        # Never print raw create_payload (may include signed viewer URLs or bearer tokens)
        print(f"[session] Đã khởi tạo phiên thành công (id={session_id}).", flush=True)

        current_theme: str | None = None
        open_prompt_seen: bool = False

        # 4. Grant permissions up front
        granted = grant_app_permissions(base_cmd, env, session_id, args.bundle_id)
        manifest["grantedPermissions"] = granted
        print(f"[permissions] Đã cấp quyền cho {args.bundle_id}: {', '.join(granted)}", flush=True)

        # 5. Iterate all screens in parity-matrix.json
        for idx, entry in enumerate(target_screens, start=1):
            screen_id = str(entry["id"])
            screen_name = str(entry.get("name", screen_id))
            group = str(entry.get("group", ""))
            ios_cfg = entry.get("ios", {})
            slug = str(ios_cfg.get("screen", "")).strip()
            is_light = bool(ios_cfg.get("light", entry.get("theme", "light") == "light"))
            is_dyn = bool(ios_cfg.get("dyn", False))
            desired_theme = "light" if is_light else "dark"
            deep_link = build_ui_review_url(slug, is_light=is_light, is_dyn=is_dyn)
            out_png = out_dir / f"{screen_id}.png"

            t0 = time.monotonic()
            record: dict[str, Any] = {
                "id": screen_id,
                "group": group,
                "name": screen_name,
                "screen": slug,
                "theme": desired_theme,
                "light": is_light,
                "dyn": is_dyn,
                "url": deep_link,
                "file": out_png.name,
                "status": "pending",
                "bytes": 0,
                "width": 0,
                "height": 0,
                "sha256": "",
                "elapsedSec": 0.0,
                "error": None,
            }

            try:
                if not slug:
                    raise RuntimeError(f"Thiếu `ios.screen` trong matrix cho {screen_id}")

                if desired_theme != current_theme:
                    run_runcloud_json(
                        base_cmd,
                        ["ios", "appearance", "--json", session_id, desired_theme],
                        env,
                        timeout_sec=30,
                        check=True,
                    )
                    current_theme = desired_theme
                    time.sleep(0.4)

                run_runcloud_json(
                    base_cmd,
                    ["ios", "open-url", "--id", session_id, "--json", deep_link],
                    env,
                    timeout_sec=45,
                    check=True,
                )

                # iOS 26.5 shows SpringBoard 'Open in "Kinnect"?' confirmation overlay
                # on custom-scheme open-url (sometimes outside app a11y tree).
                time.sleep(0.7)
                if idx <= 2 or open_prompt_seen:
                    tapped = dismiss_open_in_prompt(
                        base_cmd,
                        env,
                        session_id,
                        force_tap_if_undetected=(idx == 1),
                    )
                    if tapped and idx >= 2:
                        open_prompt_seen = True

                wait_sec = settle_duration_for(slug, args.settle_seconds, is_first=(idx == 1))
                time.sleep(wait_sec)

                # Capture screenshot (with 1 automatic retry on transient failure)
                last_shot_err: Exception | None = None
                for attempt in range(1, 3):
                    try:
                        run_runcloud_json(
                            base_cmd,
                            [
                                "ios",
                                "screenshot",
                                "--output",
                                str(out_png),
                                "--json",
                                session_id,
                            ],
                            env,
                            timeout_sec=45,
                            check=True,
                        )
                        byte_size, width, height = read_png_dimensions(out_png)
                        record["bytes"] = byte_size
                        record["width"] = width
                        record["height"] = height
                        record["sha256"] = sha256_file(out_png).lower()
                        last_shot_err = None
                        break
                    except Exception as shot_exc:
                        last_shot_err = shot_exc
                        if attempt < 2:
                            time.sleep(1.0)
                if last_shot_err is not None:
                    raise last_shot_err

                if args.capture_a11y:
                    a11y_rc, a11y_data, _ = run_runcloud_json(
                        base_cmd,
                        ["ios", "accessibility-tree", "--json", session_id],
                        env,
                        timeout_sec=35,
                        check=False,
                    )
                    if a11y_rc == 0:
                        a11y_out = a11y_dir / f"{screen_id}.json"
                        a11y_out.write_text(
                            json.dumps(sanitize_json(a11y_data, env), ensure_ascii=False, indent=2) + "\n",
                            encoding="utf-8",
                        )
                        record["a11yFile"] = f"a11y/{screen_id}.json"

                record["status"] = "ok"
                elapsed = round(time.monotonic() - t0, 2)
                record["elapsedSec"] = elapsed
                print(
                    f"[{idx:02d}/{len(target_screens):02d}] OK   {screen_id} ({slug}, {desired_theme}"
                    f"{', dyn' if is_dyn else ''}) -> {out_png.name} "
                    f"({record['width']}x{record['height']}, {record['bytes']}B, {elapsed:.2f}s)",
                    flush=True,
                )
            except KeyboardInterrupt:
                record["status"] = "interrupted"
                record["elapsedSec"] = round(time.monotonic() - t0, 2)
                records_by_id[screen_id] = record
                ordered, cap_cnt, fail_cnt, dup_cnt, dup_list = _rebuild_manifest_entries(all_screens, records_by_id)
                manifest["screens"] = ordered
                manifest["total"] = len(ordered)
                manifest["totalScreens"] = len(ordered)
                manifest["capturedCount"] = cap_cnt
                manifest["failedCount"] = fail_cnt
                manifest["duplicateWarnings"] = dup_cnt
                manifest["duplicateHashes"] = dup_list
                raise
            except Exception as exc:
                record["status"] = "failed"
                record["error"] = redact_text(str(exc), env)
                record["elapsedSec"] = round(time.monotonic() - t0, 2)
                print(
                    f"[{idx:02d}/{len(target_screens):02d}] FAIL {screen_id} ({slug}): {record['error']}",
                    file=sys.stderr,
                    flush=True,
                )

            records_by_id[screen_id] = record
            ordered, cap_cnt, fail_cnt, dup_cnt, dup_list = _rebuild_manifest_entries(all_screens, records_by_id)
            manifest["screens"] = ordered
            manifest["total"] = len(ordered)
            manifest["totalScreens"] = len(ordered)
            manifest["capturedCount"] = cap_cnt
            manifest["failedCount"] = fail_cnt
            manifest["duplicateWarnings"] = dup_cnt
            manifest["duplicateHashes"] = dup_list
            write_manifest(manifest_path, manifest)

    finally:
        manifest["finishedAt"] = dt.datetime.now(dt.timezone.utc).isoformat()
        write_manifest(manifest_path, manifest)
        delete_session_safely(base_cmd, env, session_id)

    print(
        f"[done] Hoàn tất chụp iOS: {manifest['capturedCount']}/{manifest['total']} thành công, "
        f"trùng={manifest['duplicateWarnings']}, lỗi={manifest['failedCount']}. Manifest: {manifest_path}",
        flush=True,
    )
    return 0 if manifest["failedCount"] == 0 else 2


if __name__ == "__main__":
    sys.exit(main())
