package app.kinnect.live;

import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.os.Handler;
import android.os.Looper;
import android.util.LruCache;
import android.widget.ImageView;
import org.json.JSONArray;
import org.json.JSONObject;
import java.util.Collections;
import java.util.HashSet;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Bounded, account-origin-scoped bitmap memory cache and off-UI-thread downsampling loader.
 * Prevents main-thread JPEG decode jank and unbounded RGBA memory allocations on large feeds.
 */
final class MediaImageLoader {
  interface BitmapCallback { void onDecoded(Bitmap bitmap); }
  interface IntCheck { boolean isValid(); }

  private static final int TAG_MEDIA_KEY = 0x7f0f0042;
  private static final int TAG_MEDIA_TOKEN = 0x7f0f0043;
  private static final java.util.concurrent.atomic.AtomicLong NEXT_TOKEN = new java.util.concurrent.atomic.AtomicLong(1L);
  private static final Set<String> ACTIVE_PREFETCHES = Collections.synchronizedSet(new HashSet<>());

  private static final class Holder {
    static final int CACHE_KB = (int) Math.min(
      32L * 1024L,
      Math.max(4096L, Runtime.getRuntime().maxMemory() / 1024L / 8L)
    );
    static final LruCache<String, Bitmap> MEMORY_CACHE = new LruCache<String, Bitmap>(CACHE_KB) {
      @Override
      protected int sizeOf(String key, Bitmap value) {
        return Math.max(1, value.getAllocationByteCount() / 1024);
      }
    };
    static final ExecutorService DECODE_EXECUTOR = Executors.newFixedThreadPool(2);
    static final Handler MAIN_HANDLER = new Handler(Looper.getMainLooper());
  }

  private MediaImageLoader() {}

  static int calculateInSampleSize(int outWidth, int outHeight, int maxDimPx) {
    int sample = 1;
    int target = Math.max(64, maxDimPx);
    if (outWidth > target || outHeight > target) {
      while ((outWidth / (sample * 2)) >= target || (outHeight / (sample * 2)) >= target) {
        sample *= 2;
      }
    }
    return sample;
  }

  static Bitmap decodeSampledBitmap(byte[] bytes, int maxDimPx) {
    if (bytes == null || bytes.length == 0) return null;
    try {
      BitmapFactory.Options options = new BitmapFactory.Options();
      options.inJustDecodeBounds = true;
      BitmapFactory.decodeByteArray(bytes, 0, bytes.length, options);
      if (options.outWidth <= 0 || options.outHeight <= 0) return null;
      options.inSampleSize = calculateInSampleSize(options.outWidth, options.outHeight, maxDimPx);
      options.inJustDecodeBounds = false;
      return BitmapFactory.decodeByteArray(bytes, 0, bytes.length, options);
    } catch (OutOfMemoryError oom) {
      return null;
    }
  }

  static void decodeAsync(final byte[] bytes, final int maxDimPx, final BitmapCallback callback) {
    if (bytes == null || bytes.length == 0 || callback == null) return;
    Holder.DECODE_EXECUTOR.execute(() -> {
      final Bitmap bitmap = decodeSampledBitmap(bytes, maxDimPx);
      Holder.MAIN_HANDLER.post(() -> callback.onDecoded(bitmap));
    });
  }

  static String cacheKey(NativeApi api, String path, int maxDimPx) {
    return api.origin() + "|" + path + "#" + Math.max(64, maxDimPx);
  }

  static void clear() {
    Holder.MEMORY_CACHE.evictAll();
    ACTIVE_PREFETCHES.clear();
  }

  private static boolean isMutableImagePath(String path) {
    if (path == null) return false;
    String clean = path.split("\\?", 2)[0];
    return clean.contains("/avatar") || clean.contains("/cover");
  }

  static void displayImage(
    final Activity activity,
    final NativeApi api,
    final String path,
    final ImageView target,
    final int maxDimPx,
    final IntCheck stillValid
  ) {
    if (activity == null || api == null || target == null || path == null || path.isEmpty()) return;
    final String key = cacheKey(api, path, maxDimPx);
    final long token = NEXT_TOKEN.incrementAndGet();
    target.setTag(TAG_MEDIA_KEY, key);
    target.setTag(TAG_MEDIA_TOKEN, token);

    Bitmap mem = Holder.MEMORY_CACHE.get(key);
    if (mem != null && !mem.isRecycled()) {
      target.setImageBitmap(mem);
      return;
    }
    target.setImageDrawable(null);

    final java.util.concurrent.atomic.AtomicBoolean networkApplied = new java.util.concurrent.atomic.AtomicBoolean(false);
    final Runnable fetchNetwork = () -> api.image(path, bytes -> {
      if (bytes == null || activity.isDestroyed() || (stillValid != null && !stillValid.isValid())) return;
      if (!Long.valueOf(token).equals(target.getTag(TAG_MEDIA_TOKEN))) return;
      Holder.DECODE_EXECUTOR.execute(() -> {
        final Bitmap netBitmap = decodeSampledBitmap(bytes, maxDimPx);
        if (netBitmap == null) return;
        Holder.MEMORY_CACHE.put(key, netBitmap);
        networkApplied.set(true);
        Holder.MAIN_HANDLER.post(() -> {
          if (!activity.isDestroyed() && (stillValid == null || stillValid.isValid())
              && key.equals(target.getTag(TAG_MEDIA_KEY))
              && Long.valueOf(token).equals(target.getTag(TAG_MEDIA_TOKEN))) {
            target.setImageBitmap(netBitmap);
          }
        });
      });
    });

    final boolean revalidate = isMutableImagePath(path);
    Holder.DECODE_EXECUTOR.execute(() -> {
      if (activity.isDestroyed() || (stillValid != null && !stillValid.isValid())) return;
      if (!Long.valueOf(token).equals(target.getTag(TAG_MEDIA_TOKEN))) return;
      boolean diskHit = false;
      byte[] diskBytes = api.cachedImage(path);
      if (diskBytes != null) {
        final Bitmap diskBitmap = decodeSampledBitmap(diskBytes, maxDimPx);
        if (diskBitmap != null) {
          diskHit = true;
          if (!networkApplied.get()) {
            Holder.MEMORY_CACHE.put(key, diskBitmap);
            Holder.MAIN_HANDLER.post(() -> {
              if (!networkApplied.get() && !activity.isDestroyed()
                  && (stillValid == null || stillValid.isValid())
                  && key.equals(target.getTag(TAG_MEDIA_KEY))
                  && Long.valueOf(token).equals(target.getTag(TAG_MEDIA_TOKEN))) {
                target.setImageBitmap(diskBitmap);
              }
            });
          }
        }
      }
      if (!diskHit || revalidate) {
        fetchNetwork.run();
      }
    });
  }

  static void prefetchPosts(final NativeApi api, final JSONArray posts, final int start, final int count, final int maxDimPx) {
    if (api == null || posts == null || count <= 0) return;
    int end = Math.min(posts.length(), start + count);
    int queued = 0;
    for (int i = Math.max(0, start); i < end && queued < 8; i++) {
      JSONObject post = posts.optJSONObject(i);
      if (post == null) continue;
      JSONObject media = post.optJSONObject("media");
      if (media != null && !"video".equals(media.optString("kind"))) {
        String mediaUrl = media.optString("url", "");
        if (!mediaUrl.isEmpty() && !"null".equals(mediaUrl) && queued < 8) {
          if (prefetchOne(api, mediaUrl, maxDimPx)) queued++;
        }
      }
      JSONArray mediaItems = post.optJSONArray("mediaItems");
      if (mediaItems != null) {
        for (int j = 0; j < mediaItems.length() && queued < 8; j++) {
          JSONObject item = mediaItems.optJSONObject(j);
          if (item == null || "video".equals(item.optString("kind"))) continue;
          String itemUrl = item.optString("url", "");
          if (!itemUrl.isEmpty() && !"null".equals(itemUrl)) {
            if (prefetchOne(api, itemUrl, maxDimPx)) queued++;
          }
        }
      }
      String imgPath = post.optString("image", "");
      if (!imgPath.isEmpty() && !"null".equals(imgPath) && queued < 8) {
        if (prefetchOne(api, imgPath, maxDimPx)) queued++;
      }
      JSONObject author = post.optJSONObject("author");
      String avatarPath = author == null ? "" : author.optString("avatar", "");
      if (!avatarPath.isEmpty() && !"null".equals(avatarPath) && queued < 8) {
        if (prefetchOne(api, avatarPath, 256)) queued++;
      }
    }
  }

  static void prefetchUsers(final NativeApi api, final JSONArray users, final int start, final int count, final int maxDimPx) {
    if (api == null || users == null || count <= 0) return;
    int end = Math.min(users.length(), start + count);
    int queued = 0;
    for (int i = Math.max(0, start); i < end && queued < 9; i++) {
      JSONObject user = users.optJSONObject(i);
      if (user == null) continue;
      String avatarPath = user.optString("avatar", "");
      if (!avatarPath.isEmpty() && !"null".equals(avatarPath)) {
        if (prefetchOne(api, avatarPath, maxDimPx)) queued++;
      }
    }
  }

  private static boolean prefetchOne(final NativeApi api, final String path, final int maxDimPx) {
    if (path == null || !path.startsWith("/") || path.contains("..")) return false;
    final String key = cacheKey(api, path, maxDimPx);
    if (Holder.MEMORY_CACHE.get(key) != null || !ACTIVE_PREFETCHES.add(key)) return false;
    try {
      Holder.DECODE_EXECUTOR.execute(() -> {
        boolean handedOff = false;
        try {
          byte[] saved = api.cachedImage(path);
          if (saved != null) {
            Bitmap bmp = decodeSampledBitmap(saved, maxDimPx);
            if (bmp != null) Holder.MEMORY_CACHE.put(key, bmp);
            return;
          }
          handedOff = true;
          api.image(path, bytes -> {
            if (bytes == null) {
              ACTIVE_PREFETCHES.remove(key);
              return;
            }
            try {
              Holder.DECODE_EXECUTOR.execute(() -> {
                try {
                  Bitmap bmp = decodeSampledBitmap(bytes, maxDimPx);
                  if (bmp != null) Holder.MEMORY_CACHE.put(key, bmp);
                } catch (Throwable ignored) {
                } finally {
                  ACTIVE_PREFETCHES.remove(key);
                }
              });
            } catch (Throwable t) {
              ACTIVE_PREFETCHES.remove(key);
            }
          });
        } catch (Throwable ignored) {
          handedOff = false;
        } finally {
          if (!handedOff) ACTIVE_PREFETCHES.remove(key);
        }
      });
    } catch (Throwable t) {
      ACTIVE_PREFETCHES.remove(key);
      return false;
    }
    return true;
  }
}
