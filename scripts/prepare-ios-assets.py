#!/usr/bin/env python3
"""Generate Apple-compliant opaque RGB AppIcon asset catalog for Kinnect iOS."""

import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SOURCE_CANDIDATES = [
    ROOT / "public" / "kinnect-logo-v106-512.png",
    ROOT / "public" / "kinnect-icon.png",
    ROOT / "public" / "apple-touch-icon.png",
]
ASSETS_DIR = ROOT / "ios" / "Kinnect" / "Resources" / "Assets.xcassets"
APPICON_DIR = ASSETS_DIR / "AppIcon.appiconset"

ICON_SPECS = [
    ("iphone", "20x20", "2x", 40, "Icon-40.png"),
    ("iphone", "20x20", "3x", 60, "Icon-60.png"),
    ("iphone", "29x29", "2x", 58, "Icon-58.png"),
    ("iphone", "29x29", "3x", 87, "Icon-87.png"),
    ("iphone", "40x40", "2x", 80, "Icon-80.png"),
    ("iphone", "40x40", "3x", 120, "Icon-120.png"),
    ("iphone", "60x60", "2x", 120, "Icon-120-app.png"),
    ("iphone", "60x60", "3x", 180, "Icon-180.png"),
    ("ipad", "20x20", "1x", 20, "Icon-20.png"),
    ("ipad", "20x20", "2x", 40, "Icon-40-ipad.png"),
    ("ipad", "29x29", "1x", 29, "Icon-29.png"),
    ("ipad", "29x29", "2x", 58, "Icon-58-ipad.png"),
    ("ipad", "40x40", "1x", 40, "Icon-40-ipad-spotlight.png"),
    ("ipad", "40x40", "2x", 80, "Icon-80-ipad.png"),
    ("ipad", "76x76", "1x", 76, "Icon-76.png"),
    ("ipad", "76x76", "2x", 152, "Icon-152.png"),
    ("ipad", "83.5x83.5", "2x", 167, "Icon-167.png"),
    ("ios-marketing", "1024x1024", "1x", 1024, "Icon-1024.png"),
]


def load_opaque_icon() -> Image.Image:
    source = next((p for p in SOURCE_CANDIDATES if p.exists()), None)
    if source is None:
        raise FileNotFoundError("Could not find Kinnect icon source PNG in public/")
    img = Image.open(source).convert("RGBA")
    bg = Image.new("RGBA", img.size, (21, 20, 25, 255))
    composited = Image.alpha_composite(bg, img).convert("RGB")
    return composited


def main() -> None:
    ASSETS_DIR.mkdir(parents=True, exist_ok=True)
    APPICON_DIR.mkdir(parents=True, exist_ok=True)

    root_contents = {"info": {"author": "xcode", "version": 1}}
    (ASSETS_DIR / "Contents.json").write_text(
        json.dumps(root_contents, indent=2) + "\n", encoding="utf-8"
    )

    base_img = load_opaque_icon()
    images_meta = []

    for idiom, size_str, scale, px, filename in ICON_SPECS:
        resized = base_img.resize((px, px), Image.Resampling.LANCZOS)
        resized.save(APPICON_DIR / filename, format="PNG", optimize=True)
        images_meta.append(
            {
                "filename": filename,
                "idiom": idiom,
                "scale": scale,
                "size": size_str,
            }
        )

    appicon_contents = {
        "images": images_meta,
        "info": {"author": "xcode", "version": 1},
    }
    (APPICON_DIR / "Contents.json").write_text(
        json.dumps(appicon_contents, indent=2) + "\n", encoding="utf-8"
    )
    print(f"Generated {len(ICON_SPECS)} opaque RGB icons in {APPICON_DIR}")


if __name__ == "__main__":
    main()
