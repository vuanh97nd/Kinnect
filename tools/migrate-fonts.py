"""Migrate literal font -> KTType token, CHỈ khi cỡ và độ đậm khớp chính xác role.

Chạy dry-run:  python tools/migrate-fonts.py
Áp dụng:       python tools/migrate-fonts.py --apply
"""
import pathlib
import sys

APPLY = "--apply" in sys.argv
ROOT = pathlib.Path("ios/Kinnect")

# size -> (role, weight)  khớp design/tokens.json typography.roles
ROLES = {
    34: ("displayL", "bold"),
    28: ("displayM", "bold"),
    22: ("title", "semibold"),
    20: ("titleS", "semibold"),
    17: ("bodyL", "regular"),
    15: ("body", "regular"),
    13: ("label", "medium"),
    12: ("meta", "regular"),
    11: ("micro", "medium"),
}

NEEDLE = ".font(.system(size:"


def parse(ln):
    """Trả về (size, weight, có_weight) hoặc None."""
    if NEEDLE not in ln:
        return None
    tail = ln.split("size:", 1)[1]
    body = tail.lstrip()
    num = ""
    for ch in body:
        if ch.isdigit() or ch == ".":
            num += ch
        else:
            break
    if not num:
        return None
    size = int(float(num))
    weight = "regular"
    has_weight = False
    if "weight:" in tail:
        after = tail.split("weight:", 1)[1].lstrip()
        w = ""
        for ch in after:
            if ch.isalpha() or ch == ".":
                w += ch
            else:
                break
        weight = w.lstrip(".")
        has_weight = True
    return size, weight, has_weight


changes = []
skipped = []

for p in sorted(ROOT.rglob("*.swift")):
    lines = p.read_text(encoding="utf8", errors="ignore").splitlines(keepends=True)
    dirty = False
    for i, ln in enumerate(lines):
        parsed = parse(ln)
        if not parsed:
            continue
        size, weight, has_weight = parsed
        ctx = "".join(lines[max(0, i - 6): i + 1])
        is_text = "Text(" in ctx and "Image(" not in ctx and "KinnectIcon" not in ctx
        role = ROLES.get(size)
        if not role:
            skipped.append((p, i + 1, size, weight, "cỡ không có role"))
            continue
        name, role_weight = role
        if weight != role_weight:
            skipped.append((p, i + 1, size, weight, f"role {name} là {role_weight}"))
            continue
        if not is_text:
            skipped.append((p, i + 1, size, weight, "không phải Text"))
            continue
        start = ln.index(NEEDLE)
        end = ln.index(")", ln.index("size:")) + 1
        # .font(.system(size: N, weight: .w))  ->  .font(KTType.name)
        close = ln.index("))", start) + 2
        new = ln[:start] + f".font(KTType.{name})" + ln[close:]
        changes.append((p, i + 1, size, weight, name, new.strip()))
        lines[i] = new
        dirty = True
    if dirty and APPLY:
        p.write_text("".join(lines), encoding="utf8")

print(f"{'ÁP DỤNG' if APPLY else 'DRY-RUN'} — thay được: {len(changes)}")
for p, line, size, weight, name, new in changes:
    print(f"  {p.name}:{line}  {size}/{weight} -> KTType.{name}")
print(f"\nBỏ qua: {len(skipped)}")
from collections import Counter
for reason, n in Counter(r for *_, r in skipped).most_common():
    print(f"  {n:3}  {reason}")
