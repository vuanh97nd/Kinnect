package app.kinnect.live;
/** A deliberate vertical gesture; coordinates are density-independent at the caller. */
final class LiveSwipePolicy {
 static int direction(float dx,float dy,float threshold,boolean eligible){if(!eligible||Math.abs(dy)<=threshold||Math.abs(dy)<=Math.abs(dx)*1.4f)return 0;return dy<0?1:-1;}
}
