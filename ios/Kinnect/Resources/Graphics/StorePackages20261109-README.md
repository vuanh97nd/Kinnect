# Store package artwork — 2026-11-09

Delivery for `req-store-package-graphics-20261109`: 19 original banners, one per explicitly requested package. Images use a consistent premium 3D direction, individual package palettes, and a 16:9 safe crop. Package names, durations and Xu prices belong in live UI text; artwork contains no baked prices or currency.

## Resources

- iOS: `Graphics/StorePackages20261109.xcassets`, image names `store_pkg_<package_id>`. Each imageset contains 320×180 @1x, 640×360 @2x and 960×540 @3x PNGs.
- Android: `android/app/src/main/res/drawable/store_pkg_<package_id>.webp`, 960×540, WebP quality 90. When decoding for custom canvas rendering, use `BitmapFactory.Options.inScaled = false` so drawable density does not enlarge the bitmap unnecessarily.
- Masters, exact prompts, source mapping, manifest, hashes, group review sheets and verification report: `outputs/store-package-graphics-20261109/` outside the application bundle.
- Rebuild exports with `python scripts/package-store-artwork-20261109.py` after restoring the source image paths listed in `sources.json`; requires Pillow. The script crops/resamples generated artwork; it does not paint or replace generated subjects.

## Integration handoff

`WalletStoreView.swift` currently renders `StorePackageArtworkView` procedurally. To consume these resources, resolve `store_pkg_` plus the package ID and display the image with a clipped fill inside the existing artwork header. Retain a procedural fallback for unknown or future IDs. Keep accessible package names as real UI labels.

Android `StorePackageDesign.Art` currently draws package previews on a Canvas and is used by both cards and details. Resolve the same resource name, decode outside `onDraw`, and draw center-cropped inside its existing rounded bounds. Preserve the existing procedural fallback. Do not add duplicate image layers over it.

The requested images cover 8 style packages, 4 live packages, 3 gift packages, 2 membership packages and the 30-day option for each of the 2 Studio product lines. The current server catalog also includes 7/180/365-day Studio options. If the UI reuses each Studio illustration for those durations, map them explicitly to `store_pkg_studio_video_30` or `store_pkg_studio_photo_30`; do not change their actual duration or price.

These assets illustrate themes, inventory bundles and creative tools; they do not add entitlements or guarantee a rendered effect. Prices and inventory quantities remain owned by `lib/store-packages.js`. In particular, decorative hearts/chests in the requested gift artwork are not extra inventory items.

This delivery changes resource files only. It does not rewrite purchase logic, remove coin top-up products, replace the current procedural views, or publish a build. Package metadata was checked against the source catalog; payment behavior, Xcode/Android builds, and device rendering require separate integration verification. Source still contains `referenceVnd` display code in Android package details; a complete claim that every cash reference is removed needs a UI review beyond this image delivery.
