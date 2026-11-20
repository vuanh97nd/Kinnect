"""Phase-1 variant builder: compiles main + debug|release source sets with explicit paths.

Never edits the source manifest, never writes outside the phase-1 outputs/ or work/.
Universal ABIs are preserved from deps/webrtc/jni. Local test signing keys only.
"""
import argparse, datetime, hashlib, json, pathlib, re, shutil, subprocess, zipfile

WORKTREE = pathlib.Path(__file__).resolve().parents[1]
TOOLS = pathlib.Path(r"D:/Codex/Kinnect/work/android-tools")
JAVA = TOOLS / "jdk/jdk-21.0.8+9/bin/java.exe"
KEYTOOL = TOOLS / "jdk/jdk-21.0.8+9/bin/keytool.exe"
BT = TOOLS / "build-tools/android-15"
PLATFORM = TOOLS / "platform/android-35-ext15/android.jar"
DEPS = TOOLS / "deps"
JARS = [DEPS / "webrtc/classes.jar", DEPS / "okhttp.jar", DEPS / "okio.jar"]
OUTPUTS = pathlib.Path(r"D:/Codex/Kinnect/outputs/optimization-controlled-20261119/phase1/android/builds")
ROOT_KEY = pathlib.Path(r"D:/Codex/Kinnect/android/debug.keystore")

ap = argparse.ArgumentParser()
ap.add_argument("--variant", choices=["debug", "release"], required=True)
variant = ap.parse_args().variant
OUT = OUTPUTS / variant
steps = []

def run(name, cmd):
    result = subprocess.run([str(x) for x in cmd], capture_output=True, encoding="utf-8", errors="replace")
    (OUT / (name + ".log")).write_text(result.stdout + result.stderr, encoding="utf-8")
    steps.append({"step": name, "exitCode": result.returncode})
    print(name, result.returncode, flush=True)
    if result.returncode:
        (OUT / "build-result.json").write_text(json.dumps({"variant": variant, "steps": steps, "passed": False}, indent=2), encoding="utf-8")
        raise SystemExit(result.returncode)

def sha(p):
    return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()

if OUT.exists():
    for child in OUT.iterdir():
        if child.is_dir():
            shutil.rmtree(child, ignore_errors=True)
        else:
            child.unlink()
(OUT / "classes").mkdir(parents=True)
(OUT / "dex").mkdir()

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
# Production packaging (outputs/integrated-build-20261119/build-android.py) injects these
# welcome artwork files from public/ into assets for both variants; mirror it for fidelity.
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
run("aapt-link", [BT / "aapt2.exe", "link", OUT / "resources.zip", "-I", PLATFORM,
                  "--manifest", manifest_used, "-o", OUT / "unsigned.apk"])
run("ecj", [JAVA, "-jar", TOOLS / "ecj.jar", "-1.8", "-encoding", "UTF-8", "-proc:none", "-nowarn",
            "-bootclasspath", str(PLATFORM) + ";" + str(BT / "core-lambda-stubs.jar"),
            "-classpath", ";".join(map(str, JARS)), "-d", OUT / "classes", *sources])
args = OUT / "d8.args"
args.write_text("\n".join(p.resolve().as_posix() for p in (OUT / "classes").rglob("*.class")), encoding="utf-8")
run("d8", [JAVA, "-Xmx2g", "-cp", BT / "lib/d8.jar", "com.android.tools.r8.D8", "--min-api", "26",
           "--lib", PLATFORM, "--output", OUT / "dex", "@" + str(args), *JARS])
with zipfile.ZipFile(OUT / "unsigned.apk", "a") as archive:
    for p in sorted((OUT / "dex").glob("*.dex")):
        archive.write(p, p.name)
    for key, p in sorted(asset_files.items()):
        archive.write(p, key)
    jni = DEPS / "webrtc/jni"
    for p in sorted(jni.rglob("*.so")):
        archive.write(p, "lib/" + p.relative_to(jni).as_posix(), compress_type=zipfile.ZIP_STORED)
APK = OUT / f"Kinnect-{version}-phase1-{variant}.apk"
run("zipalign", [BT / "zipalign.exe", "-P", "16", "-f", "4", OUT / "unsigned.apk", APK])
if variant == "debug":
    keystore = OUTPUTS / "qa-debug.keystore"
    if not keystore.exists():
        run("keytool", [KEYTOOL, "-genkeypair", "-keystore", keystore, "-storepass", "android", "-keypass", "android",
                        "-alias", "androiddebugkey", "-keyalg", "RSA", "-keysize", "2048", "-validity", "10000",
                        "-dname", "CN=Kinnect QA,O=Kinnect,C=VN"])
else:
    keystore = ROOT_KEY
    assert keystore.exists(), "local test keystore missing"
run("sign", [JAVA, "-jar", BT / "lib/apksigner.jar", "sign", "--ks", keystore,
             "--ks-pass", "pass:android", "--key-pass", "pass:android", APK])
run("verify", [JAVA, "-jar", BT / "lib/apksigner.jar", "verify", "--print-certs", APK])
verify = (OUT / "verify.log").read_text(encoding="utf-8")
cert = ""
for line in verify.splitlines():
    if line.startswith("Signer #1 certificate SHA-256 digest:"):
        cert = line.split(":", 1)[1].strip()

with zipfile.ZipFile(APK) as archive:
    entries = [{"name": i.filename, "bytes": i.file_size, "sha256": hashlib.sha256(archive.read(i)).hexdigest()}
               for i in archive.infolist() if not i.is_dir()]
(OUT / "apk-entries.json").write_text(json.dumps(entries, indent=2), encoding="utf-8")

changed = [rel for rel, h in source_hashes.items() if sha(WORKTREE / rel) != h]
result = {
    "variant": variant,
    "worktree": str(WORKTREE),
    "version": version,
    "steps": steps,
    "passed": not changed,
    "sourceChangedDuringBuild": changed,
    "sourceSet": {"main": "android/app/src/main/java/app/kinnect/live",
                  "variant": f"android/app/src/{variant}/java/app/kinnect/live"},
    "sourceHashes": source_hashes,
    "assets": asset_hashes,
    "debuggableInjectedAtLink": variant == "debug",
    "sourceManifestUntouched": "android:debuggable" not in manifest_path.read_text(encoding="utf-8"),
    "universalAbis": sorted({p.relative_to(DEPS / "webrtc/jni").parts[0] for p in (DEPS / "webrtc/jni").rglob("*.so")}),
    "jars": [str(j) for j in JARS],
    "apk": str(APK),
    "apkBytes": APK.stat().st_size,
    "apkSha256": sha(APK),
    "signerCertSha256": cert,
    "localTestKeyOnly": True,
    "builtAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
}
(OUT / "build-result.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
print("APK", APK, result["apkSha256"], flush=True)
