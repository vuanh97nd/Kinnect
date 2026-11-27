package app.kinnect.live;

import android.content.Context;

/** Google Play flavor stub: floating game comment overlay is disabled on Play. */
final class GameCommentOverlay {
 interface Actions { void mic(); void pause(); void room(); void reply(String message); }
 GameCommentOverlay(Context context, Actions actions) {}
 boolean show() { return false; }
 void comment(String name, String message) {}
 void flags(boolean pause, boolean mute) {}
 void viewers(int value) {}
 void openReply(String prefix) {}
 void closeReply() {}
 void hide() {}
 void clear() {}
}
