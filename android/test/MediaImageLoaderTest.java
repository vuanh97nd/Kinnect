package app.kinnect.live;

final class MediaImageLoaderTest {
  private static void check(boolean ok, String label) {
    if (!ok) throw new AssertionError("Failed: " + label);
  }

  public static void main(String[] args) {
    check(MediaImageLoader.calculateInSampleSize(800, 600, 1280) == 1, "small image keeps sample 1");
    check(MediaImageLoader.calculateInSampleSize(4000, 3000, 1280) == 2, "4000x3000 feed cap uses sample 2");
    check(MediaImageLoader.calculateInSampleSize(4000, 3000, 256) == 8, "4000x3000 avatar cap uses sample 8");
    check(MediaImageLoader.calculateInSampleSize(2560, 2560, 1280) == 2, "2560x2560 halves once cleanly");
    check(MediaImageLoader.calculateInSampleSize(128, 128, 0) == 2, "128px image with clamped min 64 downsamples once");
    check(MediaImageLoader.calculateInSampleSize(64, 64, 0) == 1, "64px image with clamped min 64 keeps sample 1");
    System.out.println("MediaImageLoaderTest: calculateInSampleSize bounds and power-of-2 scaling passed.");
  }
}
