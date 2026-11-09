# Kinnect portrait-and-frame artwork — 2026-11-09

Delivery for `req-avatar-frames-graphics-20261109`: 13 square 3D profile illustrations, each showing an adult human portrait inside the requested package-specific decorative frame.

The set covers 8 profile styles (`neon`, `aurora`, `galaxy`, `ice`, `ruby`, `forest`, `paper`, `ember`), 2 memberships (`member_plus`, `member_creator`) and 3 Live themes (`live_chill`, `live_gaming`, `live_spotlight`). Live Game is not part of this 13-frame request.

## Assets

- iOS catalog: `Graphics/AvatarFrames20261109.xcassets`. Asset names are exactly `avatar_frame_<id>`. The universal 1x/2x/3x variants are 256/512/768 px square, respectively.
- Android: `android/app/src/main/res/drawable/avatar_frame_<id>.webp`, 1024 px square, quality 92. When decoding manually, use `BitmapFactory.Options.inScaled = false` to avoid drawable-density upscaling.
- Full 1024 px PNG exports, exact generation prompts, source paths, hashes and review sheets: `outputs/avatar-frames-graphics-20261109/` outside the application bundle.
- Requested overview: `outputs/avatar-frames-graphics-20261109/all-avatar-frames-review.jpg`.
- Re-export with `python scripts/package-avatar-frames-20261109.py` (Pillow). Source masters must be available at the paths in `sources.json`.

## Intended use

These are static package previews containing illustrated people, as requested. They are opaque RGB images and are not transparent wearable frame layers. Use them in store cards, frame previews or a style picker. Do not replace a real user's profile photo with the generated character or draw this complete image over it.

For actual avatar decoration, a separate portrait-free transparent frame layer and alignment contract would be needed. Preserve the outer ornaments when displaying previews: do not apply an additional circular crop to the entire square illustration. Character identity may vary slightly across independent generated images; these are illustrative human avatars, not identity-preserving portraits of an actual user.

This delivery adds resources without changing view rendering, account appearance, membership entitlements, purchase prices or release configuration. Runtime integration, native builds and physical-device rendering have not been verified.
