#!/usr/bin/env python3
"""
Orchestrates real-transport iOS XCUITest behavioral verification (IOS-N1, IOS-N2, IOS-N3)
and real-backend parity screenshot captures on a macOS CI runner.
"""
import hashlib
import json
import os
import re
import secrets
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path.cwd()
OUT_DIR = ROOT / "dist" / "ios-qa-network"
CAPTURES_DIR = OUT_DIR / "captures"
LOGS_DIR = OUT_DIR / "logs"
VIDEOS_DIR = OUT_DIR / "videos"


def run(cmd, check=True, capture=True, env=None):
    print(f"+ {' '.join(str(c) for c in cmd)}", flush=True)
    res = subprocess.run(cmd, text=True, capture_output=capture, env=env)
    if check and res.returncode != 0:
        if capture:
            print("STDOUT:", res.stdout[-4000:], flush=True)
            print("STDERR:", res.stderr[-4000:], flush=True)
        raise RuntimeError(f"Command failed ({res.returncode}): {' '.join(str(c) for c in cmd)}")
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


def pick_iphone_393(devices):
    iphones = [d for d in devices if "iPhone" in d["name"] and "SE" not in d["name"] and "mini" not in d["name"]]
    for preferred in ["iPhone 16", "iPhone 15", "iPhone 16 Pro", "iPhone 15 Pro", "iPhone 14 Pro"]:
        for d in iphones:
            if d["name"] == preferred:
                return d
    if iphones:
        return iphones[0]
    all_iphones = [d for d in devices if "iPhone" in d["name"]]
    if all_iphones:
        return all_iphones[0]
    raise RuntimeError("No available iPhone Simulator found")


def generate_ephemeral_tls(cert_dir: Path):
    ca_key = cert_dir / "ca.key"
    ca_pem = cert_dir / "ca.pem"
    leaf_key = cert_dir / "leaf.key"
    leaf_csr = cert_dir / "leaf.csr"
    leaf_pem = cert_dir / "leaf.pem"
    ext_cfg = cert_dir / "leaf.ext"

    run([
        "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
        "-keyout", str(ca_key), "-out", str(ca_pem),
        "-days", "7", "-sha256",
        "-subj", "/CN=Kinnect QA Ephemeral Root CA",
        "-addext", "basicConstraints=critical,CA:TRUE",
        "-addext", "keyUsage=critical,keyCertSign,cRLSign",
    ])
    run([
        "openssl", "req", "-newkey", "rsa:2048", "-nodes",
        "-keyout", str(leaf_key), "-out", str(leaf_csr),
        "-subj", "/CN=127.0.0.1",
    ])
    ext_cfg.write_text(
        "\n".join([
            "basicConstraints=critical,CA:FALSE",
            "keyUsage=critical,digitalSignature,keyEncipherment",
            "extendedKeyUsage=serverAuth",
            "subjectAltName=IP:127.0.0.1,DNS:localhost",
        ]) + "\n",
        encoding="utf-8",
    )
    run([
        "openssl", "x509", "-req", "-in", str(leaf_csr),
        "-CA", str(ca_pem), "-CAkey", str(ca_key), "-CAcreateserial",
        "-out", str(leaf_pem), "-days", "7", "-sha256",
        "-extfile", str(ext_cfg),
    ])
    leaf_der = cert_dir / "leaf.der"
    run([
        "openssl", "x509", "-in", str(leaf_pem), "-outform", "DER", "-out", str(leaf_der)
    ])
    leaf_sha256 = hashlib.sha256(leaf_der.read_bytes()).hexdigest().lower()
    print(f"Ephemeral QA leaf cert SHA-256: {leaf_sha256}", flush=True)
    return ca_pem, leaf_sha256, leaf_key, leaf_pem


def redact_secrets(text: str, secret: str) -> str:
    if not text:
        return text
    out = re.sub(
        r"Type '[^']*' into \"qa\.login\.password\" SecureTextField",
        'Type \'[REDACTED]\' into "qa.login.password" SecureTextField',
        text,
    )
    if secret:
        out = out.replace(secret, "[REDACTED]")
        if len(secret) >= 12:
            out = out.replace(secret[:12], "[REDACTED]")
    return out


def run_xcuitest_case(udid, test_id, env, log_file: Path, secret: str, video_file: Path | None = None):
    rec_proc = None
    if video_file is not None:
        rec_proc = subprocess.Popen(
            ["xcrun", "simctl", "io", udid, "recordVideo", "--codec=h264", "--force", str(video_file)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        time.sleep(0.8)

    cmd = [
        "xcodebuild", "test-without-building",
        "-project", "ios/Kinnect.xcodeproj",
        "-scheme", "Kinnect",
        "-destination", f"id={udid}",
        "-derivedDataPath", "build/QADerivedData",
        f"-only-testing:{test_id}",
        "CODE_SIGN_IDENTITY=",
        "CODE_SIGNING_REQUIRED=NO",
        "CODE_SIGNING_ALLOWED=NO",
    ]
    print(f"+ {' '.join(cmd)}", flush=True)
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=env)
    sanitized = redact_secrets(proc.stdout or "", secret)
    log_file.write_text(sanitized, encoding="utf-8")

    if rec_proc is not None:
        time.sleep(0.4)
        rec_proc.send_signal(signal.SIGINT)
        try:
            rec_proc.wait(timeout=10)
        except Exception:
            rec_proc.kill()

    tail = sanitized.splitlines()[-40:]
    print(f"--- {test_id} exit={proc.returncode} ---", flush=True)
    for line in tail:
        print("  " + line, flush=True)
    return proc.returncode


def main():
    for d in (OUT_DIR, CAPTURES_DIR, LOGS_DIR, VIDEOS_DIR):
        d.mkdir(parents=True, exist_ok=True)

    git_sha = os.environ.get("GITHUB_SHA", "").strip()
    if not git_sha:
        git_sha = subprocess.run(["git", "rev-parse", "HEAD"], text=True, capture_output=True).stdout.strip()

    devices = get_available_simulators()
    device = pick_iphone_393(devices)
    udid = device["udid"]
    print(f"Selected simulator: {device['name']} ({udid}) runtime={device['runtime']}", flush=True)

    cert_tmp = Path(tempfile.mkdtemp(prefix="kinnect-qa-tls-"))
    server_proc = None
    try:
        ca_pem, leaf_sha256, leaf_key, leaf_pem = generate_ephemeral_tls(cert_tmp)

        subprocess.run(["xcrun", "simctl", "boot", udid], check=False)
        run(["xcrun", "simctl", "bootstatus", udid, "-b"])
        subprocess.run(["xcrun", "simctl", "ui", udid, "appearance", "dark"], check=False)
        subprocess.run([
            "xcrun", "simctl", "status_bar", udid, "override",
            "--time", "09:41", "--batteryState", "charged", "--batteryLevel", "100",
        ], check=False)
        # Trust ephemeral QA Root CA in Simulator keychain (no release TLS weakening)
        run(["xcrun", "simctl", "keychain", udid, "add-root-cert", str(ca_pem)])

        # Build app + KinnectUITests once
        build_log = LOGS_DIR / "xcodebuild-build-for-testing.log"
        build_cmd = [
            "xcodebuild", "build-for-testing",
            "-project", "ios/Kinnect.xcodeproj",
            "-scheme", "Kinnect",
            "-configuration", "Debug",
            "-destination", f"id={udid}",
            "-derivedDataPath", "build/QADerivedData",
            "CODE_SIGN_IDENTITY=",
            "CODE_SIGNING_REQUIRED=NO",
            "CODE_SIGNING_ALLOWED=NO",
            "ENABLE_DEBUG_DYLIB=NO",
        ]
        print(f"+ {' '.join(build_cmd)}", flush=True)
        with open(build_log, "w", encoding="utf-8") as fh:
            bres = subprocess.run(build_cmd, stdout=fh, stderr=subprocess.STDOUT, text=True)
        if bres.returncode != 0:
            lines = build_log.read_text(encoding="utf-8", errors="replace").splitlines()[-80:]
            print("\n".join(lines), flush=True)
            raise RuntimeError(f"xcodebuild build-for-testing failed ({bres.returncode})")

        # Start real createApp HTTPS backend harness
        test_password = secrets.token_hex(16)
        info_file = cert_tmp / "qa-server-info.json"
        req_log = LOGS_DIR / "server-requests.jsonl"
        server_log = LOGS_DIR / "qa-server.log"

        server_env = os.environ.copy()
        server_env.update({
            "QA_TLS_KEY": str(leaf_key),
            "QA_TLS_CERT": str(leaf_pem),
            "QA_INFO_OUT": str(info_file),
            "QA_REQ_LOG": str(req_log),
            "QA_TEST_PASSWORD": test_password,
        })
        server_fh = open(server_log, "w", encoding="utf-8")
        server_proc = subprocess.Popen(
            ["node", "ios/scripts/qa-network-server.mjs"],
            stdout=server_fh,
            stderr=subprocess.STDOUT,
            env=server_env,
        )

        deadline = time.time() + 25
        while time.time() < deadline:
            if info_file.exists() and info_file.stat().st_size > 10:
                break
            if server_proc.poll() is not None:
                server_fh.close()
                print(server_log.read_text(encoding="utf-8", errors="replace"), flush=True)
                raise RuntimeError(f"qa-network-server exited early ({server_proc.returncode})")
            time.sleep(0.25)
        if not info_file.exists():
            raise RuntimeError("Timed out waiting for qa-network-server ready info")

        info = json.loads(info_file.read_text(encoding="utf-8"))
        print("QA Server Info:", json.dumps(info), flush=True)

        qa_tmp_out = Path("/tmp/qa-ios-out")
        if qa_tmp_out.exists():
            shutil.rmtree(qa_tmp_out, ignore_errors=True)
        (qa_tmp_out / "captures").mkdir(parents=True, exist_ok=True)

        test_env = os.environ.copy()
        test_env.update({
            "TEST_RUNNER_QA_CTRL_URL": info["ctrlOrigin"],
            "TEST_RUNNER_QA_PRIMARY_ORIGIN": info["primaryOrigin"],
            "TEST_RUNNER_QA_FALLBACK_ORIGIN": info["fallbackOrigin"],
            "TEST_RUNNER_QA_USERNAME": info["seed"]["username"],
            "TEST_RUNNER_QA_PASSWORD": test_password,
            "TEST_RUNNER_QA_OUT_DIR": str(qa_tmp_out),
            "TEST_RUNNER_QA_LEAF_SHA256": leaf_sha256,
            "TEST_RUNNER_QA_DEVICE_NAME": device["name"],
            "TEST_RUNNER_QA_GIT_SHA": git_sha,
        })

        rc_unit = run_xcuitest_case(
            udid,
            "KinnectTests/KinnectOriginIsolationTests",
            test_env,
            LOGS_DIR / "xctest-origin-isolation.log",
            test_password,
            None,
        )
        rc_n1_n2 = run_xcuitest_case(
            udid,
            "KinnectUITests/KinnectNetworkParityUITests/testIOS_N1_N2_UnreadTotalAndMarkReadNoLoop",
            test_env,
            LOGS_DIR / "xcuitest-n1-n2.log",
            test_password,
            VIDEOS_DIR / "ios-n1-n2.mp4",
        )
        rc_n3 = run_xcuitest_case(
            udid,
            "KinnectUITests/KinnectNetworkParityUITests/testIOS_N3_PostCommitDropAndFallbackBounds",
            test_env,
            LOGS_DIR / "xcuitest-n3.log",
            test_password,
            VIDEOS_DIR / "ios-n3.mp4",
        )
        rc_parity = run_xcuitest_case(
            udid,
            "KinnectUITests/KinnectNetworkParityUITests/testParityCapturesRealBackend",
            test_env,
            LOGS_DIR / "xcuitest-parity.log",
            test_password,
            None,
        )

        # Copy all XCUITest outputs (evidence JSON + captures + manifest) into dist/ios-qa-network
        if qa_tmp_out.exists():
            for item in qa_tmp_out.rglob("*"):
                if item.is_file():
                    rel = item.relative_to(qa_tmp_out)
                    dst = OUT_DIR / rel
                    dst.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(item, dst)

        # Enrich captures/manifest.json with exact byte sizes and SHA-256 hashes
        manifest_path = CAPTURES_DIR / "manifest.json"
        if manifest_path.exists():
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            for cap in manifest.get("captures", []):
                rel_file = cap.get("file", "")
                fp = OUT_DIR / rel_file
                if fp.exists():
                    raw = fp.read_bytes()
                    cap["bytes"] = len(raw)
                    cap["sha256"] = hashlib.sha256(raw).hexdigest()
            manifest_path.write_text(
                json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8"
            )

        summary = {
            "gitSha": git_sha,
            "githubRunId": os.environ.get("GITHUB_RUN_ID"),
            "device": device["name"],
            "runtime": device["runtime"],
            "primaryOrigin": info["primaryOrigin"],
            "fallbackOrigin": info["fallbackOrigin"],
            "fixtureEnabled": False,
            "exitCodes": {
                "buildForTesting": bres.returncode,
                "originIsolationUnitTests": rc_unit,
                "IOS_N1_N2": rc_n1_n2,
                "IOS_N3": rc_n3,
                "parityCaptures": rc_parity,
            },
            "capturedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        }
        (OUT_DIR / "run-summary.json").write_text(
            json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8"
        )
        print("RUN_SUMMARY:", json.dumps(summary), flush=True)

        if rc_unit != 0 or rc_n1_n2 != 0 or rc_n3 != 0 or rc_parity != 0:
            sys.exit(1)
    finally:
        if server_proc is not None and server_proc.poll() is None:
            server_proc.terminate()
            try:
                server_proc.wait(timeout=5)
            except Exception:
                server_proc.kill()
        shutil.rmtree(cert_tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
