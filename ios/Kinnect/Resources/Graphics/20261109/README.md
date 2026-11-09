# Kinnect iOS graphics — 2026-11-09

New, versioned artwork for `req-graphic-assets-ios-20261109`. Existing resources and active AppIcon were preserved.

- `KinnectGraphics20261109.xcassets`: use `Image("kg20261109_gift_rose")`, for example. Universal image sets contain 256/512 px exports; feature icons contain 128/256 px exports.
- `outputs/ios-graphics-20261109/PNG`: exact requested gift and sticker filenames, plus filter preview artwork, at up to 1024 px; kept outside the application bundle to avoid duplicate payloads.
- `outputs/ios-graphics-20261109/Icons`: ten established Kinnect glyphs exported at 128 and 256 px.
- `outputs/ios-graphics-20261109/Badges`: x2, x5, x10, x50 transparent combo badges.
- `KinnectCyber20261109.appiconset`: opaque RGB candidate at all 18 existing project sizes. The build setting still selects `AppIcon`. Select this candidate only when integrating the new design.

Artwork and prompts were produced with the built-in image generation tool. Feature glyphs derive from `design/ios-icon-kit/svg`; the app icon and badges use reproducible native SVG geometry. Packaging: `python scripts/package-ios-graphics-20261109.py` (Pillow and resvg-py).

Source mapping, exact prompts, SHA-256 hashes and review sheets are in `outputs/ios-graphics-20261109/`. Source masters remain outside the application resource directory.

## Integration limits

This delivery creates assets. It does not change Swift views, effect rendering, wallet prices, or the active application icon. Xcode compilation and physical-device rendering have not been verified on this Windows host.

Face stickers are transparent static overlays, not face tracking implementations or animations. Their placement must be calibrated to face landmarks and tested in exported media. Preview portraits are independently generated illustrative samples: their identities and framing vary, so they are not an exact before/after comparison or a verified preview of the Core Image algorithms.

Current CameraStudio names differ from this request. Suggested mappings: `bunny -> bunny_ears`, `cat -> cat_whiskers`, `dog -> dog_ears`, `glasses -> neon_glasses`, `crown -> golden_tiara`, `flowers -> flower_crown`, `hearts -> cheek_hearts`, `sparkle -> sparkle_eyes`, `butterfly -> butterfly_clip`, `halo -> angel_halo`, `rainbow -> rainbow_paint`, `stars/confetti -> star_confetti`. Current items `bow`, `freckles`, `round_glasses`, `heart_glasses`, `bubbles`, `snow` are not replacements for the newly requested designs. Add explicit selections for the other new stickers rather than silently changing these meanings.

Filter mapping: `none -> original`, `cool -> cold`, `mono -> bw`; the other matching names retain their meanings. New thumbnails alone do not add a working filter preset. Beauty Glow has its own illustration.

Requested gift prices (metadata only): rose 10, heart 20, coffee 50, love_gun 100, fireworks 200, yacht 500, crown 1000, diamond 2000, sports_car 5000, castle 10000. Reconcile with the server catalog before wiring prices into the UI.
