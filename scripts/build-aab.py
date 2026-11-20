"""Build, sign, validate, and evaluate a Release Android App Bundle (.aab) via aapt2 --proto-format + bundletool."""
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
PLAY = pathlib.Path(r"D:/Codex/Kinnect/work/play-tools")
JAVA = TOOLS / "jdk/jdk-21.0.8+9/bin/java.exe"
JARSIGNER = TOOLS / "jdk/jdk-21.0.8+9/bin/jarsigner.exe"
BT = TOOLS / "build-tools/android-15"
AAPT2 = PLAY / "aapt2/aapt2.exe"
BUNDLETOOL = PLAY / "bundletool.jar"
PLATFORM = TOOLS / "platform/android-35-ext15/android.jar"
DEPS = TOOLS / "deps"
JARS = [DEPS / "webrtc/classes.jar", DEPS / "okhttp.jar", DEPS / "okio.jar"]
ROOT_KEY = pathlib.Path(r"D:/Codex/Kinnect/android/debug.keystore")


def sha(p):
    return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()


def run(out, steps, name, cmd):
    result = subprocess.run([str(x) for x in cmd], capture_output=True, encoding="utf-8", errors="replace")
    (out / f"{name}.log").write_text(result.stdout + result.stderr, encoding="utf-8")
    steps.append({"step": name, "exitCode": result.returncode})
    print(name, result.returncode, flush=True)
    if result.returncode:
        raise SystemExit(f"{name} failed rc={result.returncode}: {(result.stderr or result.stdout)[-600:]}")
    return result.stdout + result.stderr


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--phase", required=True)
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--aab-name", default=None)
    args = ap.parse_args()

    out = pathlib.Path(args.out_dir)
    if out.exists():
        shutil.rmtree(out, ignore_errors=True)
    (out / "classes").mkdir(parents=True)
    (out / "dex").mkdir()
    steps = []

    manifest_path = WORKTREE / "android/app/src/main/AndroidManifest.xml"
    version = re.search(r'versionName="([^"]+)"', manifest_path.read_text(encoding="utf-8")).group(1)

    sources = sorted((WORKTREE / "android/app/src/main/java/app/kinnect/live").glob("*.java"))
    sources += sorted((WORKTREE / "android/app/src/release/java/app/kinnect/live").glob("*.java"))

    main_assets = WORKTREE / "android/app/src/main/assets"
    asset_files = {}
    for p in main_assets.rglob("*"):
        if p.is_file():
            asset_files["assets/" + p.relative_to(main_assets).as_posix()] = p
    for name in ["welcome-profile.png", "welcome-profile-1.png", "welcome-profile-2.png", "welcome-profile-3.png"]:
        source = WORKTREE / "public" / name
        if source.is_file():
            asset_files["assets/" + name] = source
    rel_assets = WORKTREE / "android/app/src/release/assets"
    if rel_assets.is_dir():
        for p in rel_assets.rglob("*"):
            if p.is_file():
                asset_files["assets/" + p.relative_to(rel_assets).as_posix()] = p

    run(out, steps, "aapt-compile", [AAPT2, "compile", "--dir", WORKTREE / "android/app/src/main/res", "-o", out / "resources.zip"])
    run(out, steps, "aapt-link-proto", [
        AAPT2, "link", "--proto-format", out / "resources.zip", "-I", PLATFORM,
        "--manifest", manifest_path, "-o", out / "proto.apk",
    ])
    run(out, steps, "ecj", [
        JAVA, "-jar", TOOLS / "ecj.jar", "-1.8", "-encoding", "UTF-8", "-proc:none", "-nowarn",
        "-bootclasspath", str(PLATFORM) + ";" + str(BT / "core-lambda-stubs.jar"),
        "-classpath", ";".join(map(str, JARS)), "-d", out / "classes", *sources,
    ])
    d8_args = out / "d8.args"
    d8_args.write_text("\n".join(p.resolve().as_posix() for p in (out / "classes").rglob("*.class")), encoding="utf-8")
    run(out, steps, "d8", [
        JAVA, "-Xmx2g", "-cp", BT / "lib/d8.jar", "com.android.tools.r8.D8", "--min-api", "26",
        "--lib", PLATFORM, "--output", out / "dex", "@" + str(d8_args), *JARS,
    ])

    base_zip = out / "base.zip"
    abis = []
    with zipfile.ZipFile(out / "proto.apk", "r") as proto_zf, zipfile.ZipFile(base_zip, "w", zipfile.ZIP_DEFLATED) as mod_zf:
        for info in proto_zf.infolist():
            if info.is_dir():
                continue
            data = proto_zf.read(info)
            if info.filename == "AndroidManifest.xml":
                mod_zf.writestr("manifest/AndroidManifest.xml", data)
            elif info.filename == "resources.pb" or info.filename.startswith("res/"):
                mod_zf.writestr(info.filename, data)
        for p in sorted((out / "dex").glob("*.dex")):
            mod_zf.write(p, "dex/" + p.name)
        for key, p in sorted(asset_files.items()):
            mod_zf.write(p, key)
        jni = DEPS / "webrtc/jni"
        for p in sorted(jni.rglob("*.so")):
            rel_jni = p.relative_to(jni)
            abis.append(rel_jni.parts[0])
            mod_zf.write(p, "lib/" + rel_jni.as_posix())

    aab_name = args.aab_name or f"Kinnect-{version}-{args.phase}-release.aab"
    aab_path = out / aab_name
    run(out, steps, "bundletool-build", [
        JAVA, "-jar", BUNDLETOOL, "build-bundle",
        f"--modules={base_zip}", f"--output={aab_path}", "--overwrite",
    ])
    run(out, steps, "jarsigner-sign", [
        JARSIGNER, "-keystore", ROOT_KEY, "-storepass", "android", "-keypass", "android",
        str(aab_path), "androiddebugkey",
    ])
    run(out, steps, "jarsigner-verify", [JARSIGNER, "-verify", "-verbose", str(aab_path)])
    validate_out = run(out, steps, "bundletool-validate", [JAVA, "-jar", BUNDLETOOL, "validate", f"--bundle={aab_path}"])

    splits_apks = out / "splits.apks"
    universal_apks = out / "universal.apks"
    run(out, steps, "bundletool-splits", [
        JAVA, "-jar", BUNDLETOOL, "build-apks", f"--bundle={aab_path}", f"--output={splits_apks}",
        f"--aapt2={AAPT2}", f"--ks={ROOT_KEY}", "--ks-pass=pass:android",
        "--ks-key-alias=androiddebugkey", "--key-pass=pass:android", "--overwrite",
    ])
    run(out, steps, "bundletool-universal", [
        JAVA, "-jar", BUNDLETOOL, "build-apks", "--mode=universal", f"--bundle={aab_path}", f"--output={universal_apks}",
        f"--aapt2={AAPT2}", f"--ks={ROOT_KEY}", "--ks-pass=pass:android",
        "--ks-key-alias=androiddebugkey", "--key-pass=pass:android", "--overwrite",
    ])

    split_entries = {}
    with zipfile.ZipFile(splits_apks, "r") as zf:
        for i in zf.infolist():
            if i.filename.endswith(".apk"):
                split_entries[i.filename] = i.file_size
    univ_entries = {}
    with zipfile.ZipFile(universal_apks, "r") as zf:
        for i in zf.infolist():
            if i.filename.endswith(".apk"):
                univ_entries[i.filename] = i.file_size

    # Estimate Play ABI-targeted download total (master + xxhdpi/mdpi + abi split or min/max reported by bundletool get-size)
    size_total = run(out, steps, "bundletool-size-total", [JAVA, "-jar", BUNDLETOOL, "get-size", "total", f"--apks={splits_apks}"])

    res = {
        "phase": args.phase,
        "version": version,
        "aab": str(aab_path),
        "aabBytes": aab_path.stat().st_size,
        "aabSha256": sha(aab_path),
        "abisIncluded": sorted(set(abis)),
        "steps": steps,
        "validateSnippet": validate_out.strip().splitlines()[-10:],
        "splitApkEntries": split_entries,
        "universalApksEntry": univ_entries,
        "getSizeTotal": size_total.strip().splitlines(),
        "localTestKeyOnly": True,
        "builtAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    }
    (out / "aab-result.json").write_text(json.dumps(res, indent=2), encoding="utf-8")
    print("AAB_OK", aab_path, res["aabBytes"], res["aabSha256"], flush=True)


if __name__ == "__main__":
    main()
