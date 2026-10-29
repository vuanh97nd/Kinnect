package app.kinnect.live;

/** Stable recommendation ordering and navigation shared by every reel entry point. */
final class VideoFeedPolicy {
  static long score(long likes, long comments) {
    return Math.max(0, likes) * 3L + Math.max(0, comments) * 2L;
  }
  static int compare(long likesA, long commentsA, long createdA, String idA,
                     long likesB, long commentsB, long createdB, String idB) {
    int engagement = Long.compare(score(likesB, commentsB), score(likesA, commentsA));
    if (engagement != 0) return engagement;
    int date = Long.compare(createdB, createdA);
    return date != 0 ? date : idA.compareTo(idB);
  }
  static int index(int requested, int count, boolean loop) {
    if (count <= 0) return 0;
    return loop ? Math.floorMod(requested, count) : Math.max(0, Math.min(requested, count - 1));
  }
}
