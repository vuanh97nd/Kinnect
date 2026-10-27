package app.kinnect.live;
public final class VideoFeedPolicyTest {
  private static void check(boolean value) { if (!value) throw new AssertionError(); }
  public static void main(String[] args) {
    check(VideoFeedPolicy.score(10, 3) == 36);
    check(VideoFeedPolicy.score(0, 8) > VideoFeedPolicy.score(5, 0));
    check(VideoFeedPolicy.score(-1, -10) == 0);
    check(VideoFeedPolicy.score(Integer.MAX_VALUE, Integer.MAX_VALUE) == 10737418235L);
    check(VideoFeedPolicy.compare(10, 0, 1, "z", 0, 14, 99, "a") < 0);
    check(VideoFeedPolicy.compare(2, 0, 1, "a", 0, 3, 2, "z") > 0);
    check(VideoFeedPolicy.compare(2, 0, 2, "a", 0, 3, 2, "z") < 0);
    check(VideoFeedPolicy.compare(0, 0, 0, "a", 0, 0, 0, "a") == 0);
    check(VideoFeedPolicy.index(3, 3, true) == 0);
    check(VideoFeedPolicy.index(-1, 3, true) == 2);
    check(VideoFeedPolicy.index(9, 3, true) == 0);
    check(VideoFeedPolicy.index(3, 3, false) == 2);
    check(VideoFeedPolicy.index(-1, 3, false) == 0);
    check(VideoFeedPolicy.index(8, 1, true) == 0);
    check(VideoFeedPolicy.index(-1, 0, true) == 0);
    System.out.println("VideoFeedPolicy: ranking, overflow, looping and following bounds passed.");
  }
}
