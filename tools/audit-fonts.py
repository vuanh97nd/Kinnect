"""Phân loại 142 literal font trong app iOS: Text vs Image, và cỡ nào trùng role token."""
import pathlib

ROLES = {11, 12, 13, 15, 17, 20, 22, 28, 34}
NEEDLE = ".font(.system(size:"

text_c = img_c = other = exact = 0
by_file = {}

for p in pathlib.Path('.').rglob('*.swift'):
    lines = p.read_text(encoding='utf8', errors='ignore').splitlines()
    for i, ln in enumerate(lines):
        if NEEDLE not in ln:
            continue
        tail = ln.split("size:", 1)[1].lstrip()
        num = ""
        for ch in tail:
            if ch.isdigit() or ch == ".":
                num += ch
            else:
                break
        size = float(num) if num else 0
        ctx = "\n".join(lines[max(0, i - 6): i + 1])
        if "Image(" in ctx or "KinnectIcon" in ctx:
            img_c += 1
        elif "Text(" in ctx:
            text_c += 1
        else:
            other += 1
        if size == int(size) and int(size) in ROLES:
            exact += 1
        by_file[str(p)] = by_file.get(str(p), 0) + 1

print(f"Tổng literal font : {sum(by_file.values())}")
print(f"  gán cho Text    : {text_c}")
print(f"  gán cho Image   : {img_c}")
print(f"  không rõ        : {other}")
print(f"  trùng đúng role : {exact}")
print("\nTop file:")
for f, c in sorted(by_file.items(), key=lambda x: -x[1])[:6]:
    print(f"  {c:3}  {f}")
