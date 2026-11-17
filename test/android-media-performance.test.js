import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

test("Android MediaImageLoader provides bounded LruCache, power-of-2 inSampleSize downsampling, off-UI decode, and prefetch", () => {
  const loaderSrc = readFileSync(
    new URL("../android/app/src/main/java/app/kinnect/live/MediaImageLoader.java", import.meta.url),
    "utf8"
  );
  assert.match(loaderSrc, /LruCache<String,\s*Bitmap>/);
  assert.match(loaderSrc, /calculateInSampleSize\(/);
  assert.match(loaderSrc, /options\.inJustDecodeBounds\s*=\s*true/);
  assert.match(loaderSrc, /Executors\.newFixedThreadPool\(2\)/);
  assert.match(loaderSrc, /prefetchPosts\(/);
  assert.match(loaderSrc, /prefetchUsers\(/);
  assert.match(loaderSrc, /TAG_MEDIA_KEY/);
  assert.match(loaderSrc, /MEMORY_CACHE\.evictAll\(\)/);

  const mainSrc = readFileSync(
    new URL("../android/app/src/main/java/app/kinnect/live/MainActivity.java", import.meta.url),
    "utf8"
  );
  assert.match(mainSrc, /private void clearClientSessionCaches\(\)/);
  assert.match(mainSrc, /MediaImageLoader\.clear\(\)/);
  assert.match(mainSrc, /MediaImageLoader\.displayImage\(this,\s*api,\s*path,\s*target/);
  assert.match(mainSrc, /MediaImageLoader\.decodeAsync\(/);
  assert.match(mainSrc, /FEED_WINDOW_BATCH\s*=\s*10/);
  assert.match(mainSrc, /WindowedListBinder\.bind\(/);
  assert.match(mainSrc, /decodeAssetThumbnail\(/);
  assert.match(mainSrc, /MediaImageLoader\.prefetchPosts\(/);
  assert.match(mainSrc, /MediaImageLoader\.prefetchUsers\(/);
  assert.match(mainSrc, /renderPostSlice\(/);

  const binderSrc = readFileSync(
    new URL("../android/app/src/main/java/app/kinnect/live/WindowedListBinder.java", import.meta.url),
    "utf8"
  );
  assert.match(binderSrc, /TAG_BATCH_TOKEN/);
  assert.match(binderSrc, /removeOnScrollChangedListener/);

  const policySrc = readFileSync(
    new URL("../android/app/src/main/java/app/kinnect/live/PolicyText.java", import.meta.url),
    "utf8"
  );
  assert.match(policySrc, /case "index":/);
});
