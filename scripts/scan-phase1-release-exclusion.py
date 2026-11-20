"""Binary + archive evidence that the release APK excludes QA implementation, fixtures and sample media."""
import hashlib, json, pathlib, re, sys, zipfile

BUILDS = pathlib.Path(r"D:/Codex/Kinnect/outputs/optimization-controlled-20261119/phase1/android/builds")
OUT = pathlib.Path(r"D:/Codex/Kinnect/outputs/optimization-controlled-20261119/phase1/android/release-exclusion")
BASELINE = pathlib.Path(r"D:/Codex/Kinnect/dist/mobile/1.2.17-b129/Kinnect-1.2.17-b129-android.apk")

TOKENS = {
    "fixture_user_id": "usr_qa_review",
    "fixture_room_id": "fixture_room_1",
    "fixture_call_id": "call_qa_01",
    "fixture_prefs": "kinnect_qa_fixture_state",
    "fixture_flag_path": "/data/local/tmp/kinnect_fixture",
    "synthetic_session_cookie": "kinnect_session=qa_synthetic",
    "session_regression_log": "QA_SESSION_REGRESSION",
    "debug_loopback_log": "DEBUG_LOOPBACK",
    "debug_loopback_host": "10.0.2.2",
    "fixture_sample_media": "short_sample.mp4",
    "fixture_preview_prefix": "qa_preview_",
    "live_fixture_log": "LIVE_FIXTURE_ROOM_STATE",
    "qa_log_tag": "KinnectQA",
}

def scan_apk(path):
    entries = {}
    hits = {name: [] for name in TOKENS}
    with zipfile.ZipFile(path) as archive:
        for info in archive.infolist():
            if info.is_dir():
                continue
            data = archive.read(info)
            entries[info.filename] = hashlib.sha256(data).hexdigest()
            for name, token in TOKENS.items():
                if token.encode() in data:
                    hits[name].append(info.filename)
    return entries, hits

result = {"generatedAt": __import__("datetime").datetime.now(__import__("datetime").timezone.utc).isoformat(),
          "tokens": list(TOKENS.values()), "apks": {}}
problems = []
for variant, name in [("release", "Kinnect-1.2.17-phase1-release.apk"), ("debug", "Kinnect-1.2.17-phase1-debug.apk")]:
    apk = BUILDS / variant / name
    entries, hits = scan_apk(apk)
    present = sorted(k for k, v in hits.items() if v)
    result["apks"][variant] = {
        "path": str(apk),
        "sha256": hashlib.sha256(apk.read_bytes()).hexdigest(),
        "entries": len(entries),
        "hasSampleMediaAsset": "assets/short_sample.mp4" in entries,
        "qaTokenHits": {k: v for k, v in hits.items() if v},
        "absentTokens": sorted(set(TOKENS) - set(present)),
    }
    if variant == "release":
        if "assets/short_sample.mp4" in entries: problems.append("release contains assets/short_sample.mp4")
        if present: problems.append("release contains QA tokens: " + ", ".join(present))
        if any(n.startswith("assets/") and ("gifts/" in n) for n in entries): pass
    else:
        for token in ["fixture_user_id", "fixture_room_id", "fixture_call_id", "fixture_prefs", "fixture_flag_path",
                      "synthetic_session_cookie", "session_regression_log", "debug_loopback_log", "fixture_sample_media",
                      "live_fixture_log", "qa_log_tag"]:
            if token not in present: problems.append("debug missing expected token " + token)
        if "assets/short_sample.mp4" not in entries: problems.append("debug missing assets/short_sample.mp4")
result["problems"] = problems
result["passed"] = not problems

if BASELINE.exists():
    entries, hits = scan_apk(BASELINE)
    result["baseline"] = {
        "path": str(BASELINE),
        "sha256": hashlib.sha256(BASELINE.read_bytes()).hexdigest(),
        "qaTokenHits": {k: len(v) for k, v in hits.items() if v},
        "note": "Baseline main 2b7e053b shipped the QA fixture layer inside main sources; recorded for comparison only.",
    }
OUT.mkdir(parents=True, exist_ok=True)
(OUT / "release-exclusion.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
print(json.dumps({"passed": result["passed"], "problems": problems,
                  "releaseTokens": list(result["apks"]["release"]["qaTokenHits"]),
                  "debugTokens": list(result["apks"]["debug"]["qaTokenHits"])}, indent=2))
sys.exit(0 if result["passed"] else 1)
