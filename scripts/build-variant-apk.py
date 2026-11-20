"""Parameterized variant APK builder for sequential phases 2..6.

Supports --phase <name>, --variant <debug|release>, --abi <universal|arm64>, --out-dir <path>.
Never edits the source AndroidManifest.xml. Uses local test signing keys only.
"""
import argparse
import datetime
import hashlib
import json
import pathlib
import re
import shutil
import subprocess
import zipfile

WORKTREE = pathlib.Path(__file__).resolve().parents[1]
TOOLS = pathlib.Path(r"D:/Codex/Kinnect/work/android-tools")
JAVA = TOOLS / "jdk/jdk-21.0.8+9/bin/java.exe"
KEYTOOL = TOOLS / "jdk/jdk-21.0.8+9/bin/keytool.exe"
BT = TOOLS / "build-tools/android-15"
PLATFORM = TOOLS / "platform/android-35-ext15/android.jar"
DEPS = TOOLS / "deps"
JARS = [DEPS / "webrtc/classes.jar", DEPS / "okhttp.jar", DEPS / "okio.jar"]
ROOT_KEY = pathlib.Path(r"D:/Codex/Kinnect/android/debug.keystore")

ap = argparse.ArgumentParser()
ap.add_argument("--phase", required=True)
ap.add_argument("--variant", choices=["debug", "release"], required=True)
ap.add_argument("--abi", choices=["universal", "arm64"], default="universal")
ap.add_argument("--out-dir", required=True)
ap.add_argument("--apk-name", default=None)
args_cli = ap.parse_args()

variant = args_cli.variant
abi_mode = args_cli.abi
OUT = pathlib.Path(args_cli.out_dir)
STEPS = []


def run(name, cmd):
    result = subprocess.run([str(x) for x in cmd], capture_output=True, encoding="utf-8", errors="replace")
    (OUT / (name + ".log")).write_text(result.stdout + result.stderr, encoding="utf-8")
    STEPS.append({"step": name, "exitCode": result.returncode})
    print(name, result.returncode, flush=True)
    if result.returncode:
        (OUT / "build-result.json").write_text(
            json.dumps({"phase": args_cli.phase, "variant": variant, "abiMode": abi_mode, "steps": STEPS, "passed": False}, indent=2),
            encoding="utf-8",
        )
        raise SystemExit(result.returncode)


def sha(p):
    return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()


if OUT.exists():
    for child in OUT.iterdir():
        if child.is_dir():
            shutil.rmtree(child, ignore_errors=True)
        else:
            child.unlink(missing_ok=True)
(OUT / "classes").mkdir(parents=True, exist_ok=True)
(OUT / "dex").mkdir(parents=True, exist_ok=True)

manifest_path = WORKTREE / "android/app/src/main/AndroidManifest.xml"
version = re.search(r'versionName="([^"]+)"', manifest_path.read_text(encoding="utf-8")).group(1)

sources = sorted((WORKTREE / "android/app/src/main/java/app/kinnect/live").glob("*.java"))
sources += sorted((WORKTREE / f"android/app/src/{variant}/java/app/kinnect/live").glob("*.java"))
assert any(p.name == "QaRuntime.java" for p in sources), "variant QaRuntime missing"
source_hashes = {str(p.relative_to(WORKTREE)): sha(p) for p in sources}

main_assets = WORKTREE / "android/app/src/main/assets"
asset_files = {}
for p in main_assets.rglob("*"):
    if p.is_file():
        asset_files["assets/" + p.relative_to(main_assets).as_posix()] = p
for name in ["welcome-profile.png", "welcome-profile-1.png", "welcome-profile-2.png", "welcome-profile-3.png"]:
    source = WORKTREE / "public" / name
    if source.is_file():
        asset_files["assets/" + name] = source
variant_assets = WORKTREE / f"android/app/src/{variant}/assets"
if variant_assets.is_dir():
    for p in variant_assets.rglob("*"):
        if p.is_file():
            asset_files["assets/" + p.relative_to(variant_assets).as_posix()] = p
asset_hashes = {k: sha(v) for k, v in sorted(asset_files.items())}

run("aapt-compile", [BT / "aapt2.exe", "compile", "--dir", WORKTREE / "android/app/src/main/res", "-o", OUT / "resources.zip"])
manifest_src = manifest_path.read_text(encoding="utf-8")
if variant == "debug":
    assert "android:debuggable" not in manifest_src, "source manifest already declares debuggable"
    manifest_src = manifest_src.replace("<application ", '<application android:debuggable="true" ', 1)
manifest_used = OUT / "AndroidManifest.used.xml"
manifest_used.write_text(manifest_src, encoding="utf-8")
run("aapt-link", [BT / "aapt2.exe", "link", OUT / "resources.zip", "-I", PLATFORM, "--manifest", manifest_used, "-o", OUT / "unsigned.apk"])
run("ecj", [
    JAVA, "-jar", TOOLS / "ecj.jar", "-1.8", "-encoding", "UTF-8", "-proc:none", "-nowarn",
    "-bootclasspath", str(PLATFORM) + ";" + str(BT / "core-lambda-stubs.jar"),
    "-classpath", ";".join(map(str, JARS)), "-d", OUT / "classes", *sources,
])
d8_args = OUT / "d8.args"
d8_args.write_text("\n".join(p.resolve().as_posix() for p in (OUT / "classes").rglob("*.class")), encoding="utf-8")
run("d8", [
    JAVA, "-Xmx2g", "-cp", BT / "lib/d8.jar", "com.android.tools.r8.D8", "--min-api", "26",
    "--lib", PLATFORM, "--output", OUT / "dex", "@" + str(d8_args), *JARS,
])

allowed_abis = {"arm64-v8a"} if abi_mode == "arm64" else {"arm64-v8a", "armeabi-v7a", "x86", "x86_64"}
included_abis = set()
with zipfile.ZipFile(OUT / "unsigned.apk", "a") as archive:
    for p in sorted((OUT / "dex").glob("*.dex")):
        archive.write(p, p.name)
    for key, p in sorted(asset_files.items()):
        archive.write(p, key)
    jni = DEPS / "webrtc/jni"
    for p in sorted(jni.rglob("*.so")):
        rel_jni = p.relative_to(jni)
        if rel_jni.parts[0] in allowed_abis:
            included_abis.add(rel_jni.parts[0])
            archive.write(p, "lib/" + rel_jni.as_posix(), compress_type=zipfile.ZIP_STORED)

apk_filename = args_cli.apk_name or f"Kinnect-{version}-{args_cli.phase}-{abi_mode}-{variant}.apk"
APK = OUT / apk_filename
run("zipalign", [BT / "zipalign.exe", "-P", "16", "-f", "4", OUT / "unsigned.apk", APK])
if variant == "debug":
    keystore = OUT.parent / "qa-debug.keystore"
    if not keystore.exists():
        run("keytool", [
            KEYTOOL, "-genkeypair", "-keystore", keystore, "-storepass", "android", "-keypass", "android",
            "-alias", "androiddebugkey", "-keyalg", "RSA", "-keysize", "2048", "-validity", "10000",
            "-dname", "CN=Kinnect QA,O=Kinnect,C=VN",
        ])
else:
    keystore = ROOT_KEY
    assert keystore.exists(), "local test keystore missing"
run("sign", [JAVA, "-jar", BT / "lib/apksigner.jar", "sign", "--ks", keystore, "--ks-pass", "pass:android", "--key-pass", "pass:android", APK])
run("verify", [JAVA, "-jar", BT / "lib/apksigner.jar", "verify", "--print-certs", APK])

verify = (OUT / "verify.log").read_text(encoding="utf-8")
cert = ""
for line in verify.splitlines():
    if line.startswith("Signer #1 certificate SHA-256 digest:"):
        cert = line.split(":", 1)[1].strip()

with zipfile.ZipFile(APK) as archive:
    entries = [{"name": i.filename, "bytes": i.file_size, "sha256": hashlib.sha256(archive.read(i)).hexdigest()} for i in archive.infolist() if not i.is_dir()]
(OUT / "apk-entries.json").write_text(json.dumps(entries, indent=2), encoding="utf-8")

changed = [rel for rel, h in source_hashes.items() if sha(WORKTREE / rel) != h]
result = {
    "phase": args_cli.phase,
    "variant": variant,
    "abiMode": abi_mode,
    "abis": sorted(included_abis),
    "worktree": str(WORKTREE),
    "version": version,
    "steps": STEPS,
    "passed": not changed,
    "sourceChangedDuringBuild": changed,
    "sourceSet": {"main": "android/app/src/main/java/app/kinnect/live", "variant": f"android/app/src/{variant}/java/app/kinnect/live"},
    "sourceHashes": source_hashes,
    "assets": asset_hashes,
    "debuggableInjectedAtLink": variant == "debug",
    "sourceManifestUntouched": "android:debuggable" not in manifest_path.read_text(encoding="utf-8"),
    "apk": str(APK),
    "apkBytes": APK.stat().st_size,
    "apkSha256": sha(APK),
    "signerCertSha256": cert,
    "localTestKeyOnly": True,
    "builtAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
}
(OUT / "build-result.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
print("APK", APK, result["apkBytes"], result["apkSha256"], flush=True)
