"""Release APK runtime smoke on the disposable emulator-5592 only.

Installs the Phase-1 release APK, launches it signed out, and asserts the app renders a real
entry screen with no QA logging or fixture behavior. It does not touch a production server.
"""
import json, os, re, struct, subprocess, sys, time, zlib
import xml.etree.ElementTree as ET

PHASE = os.environ.get('KINNECT_PHASE', 'phase2')
ADB = r'D:/Codex/Kinnect/work/android-emulator/sdk/platform-tools/adb.exe'
APK = os.environ.get('KINNECT_RELEASE_APK', f'D:/Codex/Kinnect/outputs/optimization-controlled-20261119/{PHASE}/android/builds/release/Kinnect-1.2.17-{PHASE}-universal-release.apk')
OUT = os.environ.get('KINNECT_PHASE_OUT', f'D:/Codex/Kinnect/outputs/optimization-controlled-20261119/{PHASE}/android')
CAP = os.path.join(OUT, 'runtime', 'captures')
LOGS = os.path.join(OUT, 'runtime', 'logs')
PKG = 'app.kinnect.live'
SERIAL = 'emulator-5592'


def run(args, timeout=120, check=True):
    p = subprocess.run(args, capture_output=True, timeout=timeout)
    if check and p.returncode != 0:
        raise SystemExit('FAILED %s rc=%d %s' % (' '.join(map(str, args)), p.returncode, p.stderr.decode('utf-8', 'replace')[-400:]))
    return p


def adb(*a, timeout=120, check=True):
    return run([ADB, '-s', SERIAL] + list(a), timeout=timeout, check=check)


def shell(*a, timeout=120, check=True):
    return adb('shell', *a, timeout=timeout, check=check).stdout.decode('utf-8', 'replace')


def png_stats(data):
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        return {'decoded': False}
    pos, idat = 8, b''
    width = height = depth = ctype = None
    while pos + 8 <= len(data):
        length = struct.unpack('>I', data[pos:pos + 4])[0]
        name = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if name == b'IHDR':
            width, height, depth, ctype = struct.unpack('>IIBB', chunk[:10])
        elif name == b'IDAT':
            idat += chunk
        elif name == b'IEND':
            break
    if depth != 8 or ctype not in (2, 6) or not width or not height:
        return {'decoded': False, 'reason': 'unsupported png'}
    raw = zlib.decompress(idat)
    bpp = 4 if ctype == 6 else 3
    stride = width * bpp
    prev = bytearray(stride)
    colors, lumas, i = set(), [], 0
    for y in range(height):
        f = raw[i]; i += 1
        line = bytearray(raw[i:i + stride]); i += stride
        if f == 1:
            for x in range(bpp, stride): line[x] = (line[x] + line[x - bpp]) & 255
        elif f == 2:
            for x in range(stride): line[x] = (line[x] + prev[x]) & 255
        elif f == 3:
            for x in range(stride):
                a = line[x - bpp] if x >= bpp else 0
                line[x] = (line[x] + ((a + prev[x]) >> 1)) & 255
        elif f == 4:
            for x in range(stride):
                a = line[x - bpp] if x >= bpp else 0
                b = prev[x]; c = prev[x - bpp] if x >= bpp else 0
                p = a + b - c; pa = abs(p - a); pb = abs(p - b); pc = abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + pr) & 255
        prev = line
        if y % 4 == 0:
            for x in range(0, width, 4):
                o = x * bpp
                r, g, b = line[o], line[o + 1], line[o + 2]
                colors.add((r >> 3, g >> 3, b >> 3))
                lumas.append((r + g + b) // 3)
    mean = sum(lumas) / len(lumas)
    return {'decoded': True, 'width': width, 'height': height, 'distinctColors': len(colors), 'meanLuma': round(mean, 1)}


def main():
    os.makedirs(CAP, exist_ok=True); os.makedirs(LOGS, exist_ok=True)
    if run([ADB, 'get-state'], timeout=15, check=False).stdout.decode().strip() != 'device':
        raise SystemExit('device not ready')
    adb('shell', 'input', 'keyevent', 'KEYCODE_WAKEUP')
    adb('shell', 'wm', 'dismiss-keyguard', check=False)
    adb('uninstall', PKG, check=False)
    adb('install', os.path.normpath(APK))
    pkg = shell('dumpsys', 'package', PKG)
    debuggable = 'DEBUGGABLE' in pkg
    if debuggable:
        raise SystemExit('release APK unexpectedly debuggable')
    adb('logcat', '-c')
    adb('shell', 'am', 'start', '-W', '-n', PKG + '/.MainActivity')
    text = ''
    for _ in range(12):
        time.sleep(1.5)
        adb('shell', 'uiautomator', 'dump', '/sdcard/qa_release.xml', timeout=45, check=False)
        text = adb('exec-out', 'cat', '/sdcard/qa_release.xml', timeout=30, check=False).stdout.decode('utf-8', 'replace')
        if '<hierarchy' in text and any(t in text for t in ('Kết nối đúng gu', 'Find your people', 'Đăng nhập', 'Log in')):
            break
    m = re.search(r'<\?xml.*</hierarchy>', text, re.S)
    if not m:
        raise SystemExit('release UI dump failed')
    if '<!DOCTYPE' in m.group(0) or '<!ENTITY' in m.group(0):
        raise SystemExit('refusing XML with DTD/entities')
    root = ET.fromstring(m.group(0))
    texts = [(n.get('text') or '').strip() for n in root.iter('node')]
    descs = [(n.get('content-desc') or '').strip() for n in root.iter('node')]
    visible = [t for t in texts + descs if t]
    entry = any(t in ('Kết nối đúng gu', 'Find your people', 'Đăng nhập', 'Log in') for t in visible)
    crashed = 'has died' in shell('dumpsys', 'activity', 'activities') or 'FATAL EXCEPTION' in adb('logcat', '-d').stdout.decode('utf-8', 'replace')
    qa_logs = [l for l in adb('logcat', '-d', '-s', 'KinnectQA').stdout.decode('utf-8', 'replace').splitlines() if l.strip()]
    p = adb('exec-out', 'screencap', '-p', timeout=45)
    shot = os.path.join(CAP, 'release-entry-signed-out.png')
    open(shot, 'wb').write(p.stdout)
    stats = png_stats(p.stdout)
    result = {
        'jobId': os.environ.get('KINNECT_JOB_ID', f'opt-{PHASE}-android-20261119'), 'agent': 'Qoder', 'device': SERIAL,
        'apk': os.path.basename(APK), 'sha256': __import__('hashlib').sha256(open(APK, 'rb').read()).hexdigest(),
        'case': 'release-entry-signed-out', 'debuggable': debuggable,
        'entryScreenVisible': entry, 'visibleTexts': visible[:15],
        'crashed': crashed, 'qaLogLines': qa_logs[:10], 'qaLogCount': len(qa_logs),
        'screenshot': os.path.basename(shot), 'frame': stats,
        'pass': bool(entry and not crashed and not qa_logs and stats.get('decoded') and stats.get('distinctColors', 0) > 50)
    }
    json.dump(result, open(os.path.join(OUT, 'runtime', 'release-smoke.json'), 'w', encoding='utf-8'), indent=2)
    print(json.dumps(result, indent=2))
    sys.exit(0 if result['pass'] else 1)


if __name__ == '__main__':
    main()
