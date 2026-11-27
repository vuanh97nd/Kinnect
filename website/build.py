"""Sinh các trang website Kinnect vào dist/ từ src/.

Mỗi file trong src/pages/*.html có dòng đầu là JSON (title, description, path, nav),
phần còn lại là nội dung <main>. Thanh trên, chân trang và hộp hướng dẫn thiết bị
dùng chung từ src/layout.html (hoặc landing-layout.html / standalone-layout.html).

Chạy: python build.py
"""
import json
import hashlib
import re
import pathlib
import shutil

ROOT = pathlib.Path(__file__).parent
SRC = ROOT / "src"
DIST = ROOT / "dist"
SITE = "https://kinnect.io.vn"
APK = "https://app.kinnect.io.vn/download/android"

for src_asset in ["home.css", "home.js", "game.js"]:
    if (SRC / src_asset).is_file():
        shutil.copy2(SRC / src_asset, DIST / src_asset)
NAV = [
    ("features", "/#experience", "Tính năng"),
    ("safety", "/#an-toan", "An toàn"),
    ("faq", "/#faq", "Hỏi đáp"),
    ("community", "/community", "Cộng đồng"),
    ("terms", "/terms", "Điều khoản"),
    ("support", "/support", "Hỗ trợ"),
]

# Native landing assets also need versioned URLs: browsers cache them for a day.
native = DIST / "native-welcome.html"
if native.is_file():
    native_html = native.read_text(encoding="utf-8")
    for asset in ["native-welcome.css", "native-fit.js", "native-welcome.js"]:
        stamp = hashlib.sha256((DIST / asset).read_bytes()).hexdigest()[:12]
        native_html = re.sub(
            r'((?:src|href)="/)' + re.escape(asset) + r'(?:\?v=[^" ]*)?',
            lambda m, a=asset, s=stamp: m.group(1) + a + "?v=" + s,
            native_html,
        )
    native.write_text(native_html, encoding="utf-8")

layout = (SRC / "layout.html").read_text(encoding="utf-8")
landing_layout = (SRC / "landing-layout.html").read_text(encoding="utf-8")
standalone_layout = (SRC / "standalone-layout.html").read_text(encoding="utf-8")

sitemap = []
for page in sorted((SRC / "pages").glob("*.html")):
    head, body = page.read_text(encoding="utf-8").split("\n", 1)
    meta = json.loads(head)
    nav = "".join(
        f'<a href="{href}"{" aria-current=\"page\"" if key == meta.get("nav") else ""}>{label}</a>'
        for key, href, label in NAV
    )
    url = SITE + meta["path"]
    layout_kind = meta.get("layout")
    if layout_kind == "landing-v2":
        page_layout = landing_layout
    elif layout_kind == "standalone":
        page_layout = standalone_layout
    else:
        page_layout = layout
    html = (
        page_layout.replace("{{title}}", meta["title"])
        .replace("{{description}}", meta["description"])
        .replace("{{url}}", url)
        .replace("{{robots}}", meta.get("robots", "index, follow"))
        .replace("{{nav}}", nav)
        .replace("{{main}}", body)
        .replace("{{APK}}", APK)
    )
    # Version changed assets so existing browsers receive the current design.
    html = re.sub(
        r'((?:src|href)="/)(style\.css|app\.js|home\.css|home\.js|game\.js|mobile-home\.css|native-welcome\.html|img/app-(?:feed|chat|discover)\.jpg)(?:\?v=[^" ]*)?',
        lambda match: match.group(1)
        + match.group(2)
        + "?v="
        + hashlib.sha256((DIST / match.group(2)).read_bytes()).hexdigest()[:12],
        html,
    )
    (DIST / page.name).write_text(html, encoding="utf-8")
    if page.name == "game.html" and (DIST / "game").is_dir():
        (DIST / "game" / "index.html").write_text(html, encoding="utf-8")
    if meta.get("robots", "").startswith("noindex"):
        continue
    sitemap.append(url)

(DIST / "sitemap.xml").write_text(
    '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
    + "".join(f"  <url><loc>{u}</loc></url>\n" for u in sitemap)
    + "</urlset>\n",
    encoding="utf-8",
)
print("Đã tạo", len(list((SRC / "pages").glob("*.html"))), "trang;", len(sitemap), "trang trong sitemap")
