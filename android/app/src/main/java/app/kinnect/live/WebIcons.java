package app.kinnect.live;

/** Native vector assets exported from the same SVG paths as the web. */
final class WebIcons {
  static android.graphics.drawable.Drawable load(android.content.Context context, String name) {
    int preferred = resolve(context, name);
    if (preferred != 0) try { return context.getDrawable(preferred).mutate(); } catch (RuntimeException invalidVector) { }
    int legacy = context.getResources().getIdentifier("ic_" + name, "drawable", context.getPackageName());
    if (legacy != 0 && legacy != preferred) try { return context.getDrawable(legacy).mutate(); } catch (RuntimeException invalidVector) { }
    return new android.graphics.drawable.ColorDrawable(android.graphics.Color.TRANSPARENT);
  }
  static int resolve(android.content.Context context, String name) {
    String web = name;
    switch (name) {
      case "call": web = "phone"; break;
      case "attach": web = "paperclip"; break;
      case "sound": web = "volume_2"; break;
      case "music": web = "music_2"; break;
      case "flip": web = "switch_camera"; break;
      case "wand": web = "wand_sparkles"; break;
      case "flag": web = "circle_help"; break;
      case "feed": web = "house"; break;
      case "discover": web = "compass"; break;
      case "shorts": web = "clapperboard"; break;
      case "live": web = "radio"; break;
      case "inbox": web = "message_square"; break;
      case "message": web = "message_square"; break;
      case "comment": web = "message_circle"; break;
      case "profile": web = "user_round"; break;
      case "person_add": web = "user_plus"; break;
      case "back": web = "arrow_left"; break;
      case "more": web = "ellipsis"; break;
      case "close": web = "x"; break;
      case "share": web = "send"; break;
      case "recall": web = "rotate_ccw"; break;
      case "trash": web = "trash_2"; break;
      case "image": web = "image"; break;
      case "smile": web = "smile"; break;
      case "plus": web = "plus"; break;
      case "settings": web = "settings"; break;
      case "check": web = "check"; break;
      case "search": web = "search"; break;
      case "forward": web = "forward"; break;
      case "bell": web = "bell"; break;
      case "heart": web = "heart"; break;
      case "video": web = "video"; break;
      case "globe": web = "globe"; break;
    }
    int id = context.getResources().getIdentifier("ic_web_" + web.replace('-', '_'), "drawable", context.getPackageName());
    return id != 0 ? id : context.getResources().getIdentifier("ic_" + name, "drawable", context.getPackageName());
  }
}
