"""Build a Windows standby installation kit without production data or secrets."""
from pathlib import Path
import hashlib, json, zipfile

root = Path(__file__).resolve().parent.parent
out = root / 'dist' / 'Kinnect-Standby-Windows.zip'
out.parent.mkdir(exist_ok=True)
files = [root / p for p in ('server.js', 'package.json', 'package-lock.json')]
for directory in ('lib', 'public'):
    files += [p for p in (root / directory).rglob('*') if p.is_file() and p.suffix.lower() not in ('.env', '.key', '.pem', '.sqlite', '.log')]
kit = root / 'scripts' / 'standby-kit'
files += [p for p in kit.iterdir() if p.is_file()]
entries = {}
for p in files:
    name = p.name if p.parent == kit else 'server/' + p.relative_to(root).as_posix()
    entries[name] = p.read_bytes()
manifest = {name: hashlib.sha256(data).hexdigest() for name, data in sorted(entries.items())}
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for name, data in sorted(entries.items()):
        z.writestr(name, data)
    z.writestr('manifest.json', json.dumps(manifest, indent=2))
digest = hashlib.sha256(out.read_bytes()).hexdigest()
out.with_suffix('.zip.sha256').write_text(digest + '  ' + out.name + '\n')
print(f'{out}\n{len(entries)} files; {out.stat().st_size} bytes\nSHA256 {digest}')
