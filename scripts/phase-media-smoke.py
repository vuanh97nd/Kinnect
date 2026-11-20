"""Phase-1 runtime media + local WebRTC smoke on the disposable emulator-5592 only.

Asserts real behavior: decoded PNG frame statistics (not file presence), advancing video
position and changing frames, and an in-app two-PeerConnection SDP/ICE/DataChannel echo.
"""
import json, os, re, struct, subprocess, sys, time, zlib, xml.etree.ElementTree as ET

PHASE = os.environ.get('KINNECT_PHASE', 'phase2')
ROOT = os.environ.get('KINNECT_WORKTREE', r'D:/Codex/Kinnect-opt-sequential-20261119')
ADB = r'D:/Codex/Kinnect/work/android-emulator/sdk/platform-tools/adb.exe'
APK = os.environ.get('KINNECT_DEBUG_APK', f'D:/Codex/Kinnect/outputs/optimization-controlled-20261119/{PHASE}/android/builds/debug/Kinnect-1.2.17-{PHASE}-universal-debug.apk')
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


def require_device():
    state = run([ADB, 'get-state'], timeout=15, check=False).stdout.decode('utf-8', 'replace').strip()
    if state != 'device':
        raise SystemExit('device not ready: ' + state)
    devices = run([ADB, 'devices'], timeout=15).stdout.decode('utf-8', 'replace')
    online = [l for l in devices.splitlines() if l.endswith('\tdevice')]
    if len(online) != 1 or SERIAL + '\tdevice' not in devices:
        raise SystemExit('unexpected adb device set: ' + devices.strip())


def uidump(name):
    last = ''
    for _ in range(6):
        adb('shell', 'uiautomator', 'dump', '/sdcard/qa_uidump.xml', timeout=45, check=False)
        text = adb('exec-out', 'cat', '/sdcard/qa_uidump.xml', timeout=30, check=False).stdout.decode('utf-8', 'replace')
        m = re.search(r'<\?xml.*</hierarchy>', text, re.S)
        if m:
            if '<!DOCTYPE' in m.group(0) or '<!ENTITY' in m.group(0):
                raise SystemExit('refusing XML with DTD/entities from ' + name)
            open(os.path.join(LOGS, name + '.xml'), 'w', encoding='utf-8').write(m.group(0))
            return ET.fromstring(m.group(0))
        last = text
        time.sleep(1.5)
    raise SystemExit('uiautomator dump failed for ' + name + ' ' + last[-200:])


def shot(name):
    p = adb('exec-out', 'screencap', '-p', timeout=45)
    path = os.path.join(CAP, name + '.png')
    with open(path, 'wb') as f:
        f.write(p.stdout)
    return path


def png_sample(data, step=4):
    """Decode an 8-bit RGB/RGBA PNG (adb screencap format) and return sampled luma + stats."""
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        return None
    pos, idat = 8, b''
    width = height = depth = ctype = None
    while pos + 8 <= len(data):
        length = struct.unpack('>I', data[pos:pos + 4])[0]
        ctype_chunk = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if ctype_chunk == b'IHDR':
            width, height, depth, ctype = struct.unpack('>IIBB', chunk[:10])
        elif ctype_chunk == b'IDAT':
            idat += chunk
        elif ctype_chunk == b'IEND':
            break
    if depth != 8 or ctype not in (2, 6) or not width or not height:
        return {'decoded': False, 'reason': 'unsupported PNG depth=%s type=%s' % (depth, ctype)}
    raw = zlib.decompress(idat)
    bpp = 4 if ctype == 6 else 3
    stride = width * bpp
    prev = bytearray(stride)
    luma = []
    distinct = set()
    i = 0
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
        if y % step == 0:
            for x in range(0, width, step):
                o = x * bpp
                r, g, b = line[o], line[o + 1], line[o + 2]
                distinct.add((r >> 3, g >> 3, b >> 3))
                luma.append((r + g + b) // 3)
    mean = sum(luma) / len(luma)
    var = sum(v * v for v in luma) / len(luma) - mean * mean
    return {'decoded': True, 'width': width, 'height': height, 'distinctColors': len(distinct),
            'meanLuma': round(mean, 1), 'stddevLuma': round(max(0.0, var) ** 0.5, 1), 'sampled': len(luma)}


def compare_frames(a, b):
    """Mean absolute luma difference between two PNGs sampled on the same grid."""
    fa, fb = _frames(a), _frames(b)
    if not fa or not fb or len(fa) != len(fb):
        return None
    return round(sum(abs(x - y) for x, y in zip(fa, fb)) / len(fa), 2)


def _frames(data):
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        return None
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
    if depth != 8 or ctype not in (2, 6):
        return None
    raw = zlib.decompress(idat)
    bpp = 4 if ctype == 6 else 3
    stride = width * bpp
    prev = bytearray(stride)
    out, i = [], 0
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
        if y % 6 == 0:
            out.extend((line[x * bpp] + line[x * bpp + 1] + line[x * bpp + 2]) // 3 for x in range(0, width, 6))
    return out


def nodes(root):
    return root.iter('node')


def find_node(root, text=None, desc=None):
    for n in nodes(root):
        if text is not None and n.get('text') == text:
            return n
        if desc is not None and n.get('content-desc') == desc:
            return n
    return None


def center(n):
    x1, y1, x2, y2 = map(int, re.findall(r'\d+', n.get('bounds')))
    return (x1 + x2) // 2, (y1 + y2) // 2


def tap(n):
    x, y = center(n)
    adb('shell', 'input', 'tap', str(x), str(y))


def qa_log():
    return adb('logcat', '-d', '-s', 'KinnectQA').stdout.decode('utf-8', 'replace')


def main():
    os.makedirs(CAP, exist_ok=True); os.makedirs(LOGS, exist_ok=True)
    require_device()
    model = shell('getprop', 'ro.product.model').strip()
    result = {'jobId': os.environ.get('KINNECT_JOB_ID', f'opt-{PHASE}-android-20261119'), 'agent': 'Qoder', 'device': SERIAL, 'model': model,
              'apk': os.path.basename(APK), 'variant': 'debug (QA fixtures via ui_review_fixture on debuggable build)',
              'cases': [], 'webRtc': {}}
    adb('shell', 'input', 'keyevent', 'KEYCODE_WAKEUP')
    adb('shell', 'wm', 'dismiss-keyguard', check=False)
    adb('install', '-r', '-g', os.path.normpath(APK))
    shell('pm', 'clear', PKG)
    adb('logcat', '-c')
    # CASE 1: short-video fixture playback must decode, render and advance.
    adb('shell', 'am', 'start', '-W', '-n', PKG + '/.MainActivity',
        '--ez', 'ui_review_fixture', 'true', '--ez', 'reset_fixture_state', 'true',
        '-e', 'app_language', 'vi', '-e', 'commerce_destination', 'feed_home')
    time.sleep(3)
    video = root = None
    for _ in range(10):
        root = uidump('media-main-fixture')
        video = find_node(root, text='Video')
        if video is None:
            video = find_node(root, desc='Video')
        if video is not None:
            break
        time.sleep(1.5)
    if video is None:
        result['cases'].append({'case': 'shorts-video-playback', 'pass': False, 'reason': 'bottom Video tab not found', 'dump': 'media-main-fixture.xml'})
    else:
        feed_png = shot('media-feed-fixture')
        feed_stats = png_sample(open(feed_png, 'rb').read())
        result['cases'].append({
            'case': 'feed-image-render',
            'pass': bool(feed_stats and feed_stats.get('decoded') and feed_stats['distinctColors'] > 200 and feed_stats['stddevLuma'] > 8),
            'frame': feed_stats,
            'screenshot': os.path.basename(feed_png),
            'dump': 'media-main-fixture.xml'
        })
        tap(video)
        for _ in range(40):
            if 'SHORTS_EVENT: action=playing' in qa_log():
                break
            time.sleep(0.2)
        # short_sample.mp4 is 1.948s looping; tap stage after 1.0s to record advancing position before wrap.
        time.sleep(1.0)
        adb('shell', 'input', 'tap', '450', '1200')
        time.sleep(0.4)
        adb('shell', 'input', 'tap', '450', '1200')
        time.sleep(0.2)
        png1 = shot('shorts-fixture-video-a')
        time.sleep(0.8)
        png2 = shot('shorts-fixture-video-b')
        root2 = uidump('media-shorts-fixture')
        log = qa_log()
        open(os.path.join(LOGS, 'media-shorts-logcat.txt'), 'w', encoding='utf-8').write(log)
        playing = [l for l in log.splitlines() if 'SHORTS_EVENT' in l and ('action=playing' in l or 'action=pause' in l or 'action=start' in l)]
        positions = [int(m.group(1)) for m in (re.search(r'pos=(\d+)', l) for l in playing) if m]
        data1, data2 = open(png1, 'rb').read(), open(png2, 'rb').read()
        stats1, stats2 = png_sample(data1), png_sample(data2)
        diff = compare_frames(data1, data2)
        cache = shell('run-as', PKG, 'ls', '-l', 'cache/')
        cache_m = re.search(r'\d+\s+\S+\s+\S+\s+(\d+)\s+.*fixture_short\.mp4', cache)
        cache_ok = bool(cache_m) and int(cache_m.group(1)) > 1024
        advancing = bool(positions) and max(positions) > min(positions) and max(positions) > 500
        rendered = bool(stats1 and stats1.get('decoded') and stats2 and stats2.get('decoded')
                        and stats1['distinctColors'] > 200 and stats1['stddevLuma'] > 8)
        animated = diff is not None and diff > 0.5
        result['cases'].append({'case': 'shorts-video-playback', 'pass': bool(advancing and rendered and animated and cache_ok),
                                'positionsMs': positions[-6:], 'advancing': advancing,
                                'frameA': stats1, 'frameB': stats2, 'meanLumaDiffAB': diff, 'rendered': rendered,
                                'fixtureVideoCacheBytes': int(cache_m.group(1)) if cache_m else None,
                                'screenshots': [os.path.basename(png1), os.path.basename(png2)],
                                'logcat': 'media-shorts-logcat.txt'})
    # CASE 2: incoming-call full-screen UI fixture (launched internally via MainActivity so IncomingCallActivity stays non-exported).
    adb('shell', 'am', 'force-stop', PKG)
    adb('shell', 'am', 'start', '-W', '-n', PKG + '/.MainActivity',
        '--ez', 'ui_review_fixture', 'true', '-e', 'app_language', 'vi',
        '-e', 'commerce_destination', 'call_incoming')
    time.sleep(4)
    root3 = uidump('media-incoming-call-fixture')
    texts = [(n.get('text') or '').strip() for n in nodes(root3) if (n.get('text') or '').strip()]
    has_answer = any(t in ('Trả lời video', 'Trả lời') for t in texts)
    has_decline = any(t == 'Từ chối' for t in texts)
    has_kind = any('Cuộc gọi' in t for t in texts)
    png3 = shot('incoming-call-fixture')
    stats3 = png_sample(open(png3, 'rb').read())
    result['cases'].append({'case': 'incoming-call-ui', 'pass': has_answer and has_decline and has_kind and bool(stats3 and stats3.get('decoded')),
                            'texts': texts[:12], 'screenshot': os.path.basename(png3), 'frame': stats3, 'dump': 'media-incoming-call-fixture.xml'})
    # CASE 3: two local PeerConnections, SDP/ICE/DataChannel echo inside the app process (force-stop so onCreate runs).
    adb('shell', 'am', 'force-stop', PKG)
    adb('logcat', '-c')
    adb('shell', 'am', 'start', '-W', '-n', PKG + '/.MainActivity', '--ez', 'qa_webrtc_selftest', 'true')
    events = []
    for _ in range(20):
        time.sleep(0.75)
        events = [l for l in qa_log().splitlines() if 'QA_WEBRTC' in l]
        if any('PASS' in l or 'FAIL' in l for l in events):
            break
    open(os.path.join(LOGS, 'media-webrtc-logcat.txt'), 'w', encoding='utf-8').write('\n'.join(events))
    passed = [l for l in events if 'QA_WEBRTC: PASS' in l]
    failed = [l for l in events if 'QA_WEBRTC: FAIL' in l]
    result['webRtc'] = {
        'scope': 'Two PeerConnections inside the one owned emulator app process: real native SDP offer/answer, ICE gathering/exchange and DTLS/SCTP DataChannel ping/pong.',
        'notCovered': 'Physical-device camera/microphone capture, remote TURN relay RTP and two-device calls; no second device or account automation is available under the phase-1 scope.',
        'pass': bool(passed and not failed),
        'passLine': passed[-1] if passed else None,
        'failLine': failed[-1] if failed else None,
        'events': events[-40:],
        'logcat': 'media-webrtc-logcat.txt'
    }
    adb('shell', 'am', 'force-stop', PKG)
    result['passed'] = all(c['pass'] for c in result['cases']) and result['webRtc']['pass']
    path = os.path.join(OUT, 'runtime', 'media-smoke.json')
    json.dump(result, open(path, 'w', encoding='utf-8'), indent=2)
    print(json.dumps(result, indent=2))
    sys.exit(0 if result['passed'] else 1)


if __name__ == '__main__':
    main()
