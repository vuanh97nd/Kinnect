package app.kinnect.live;

/** Native vector assets exported from the same SVG paths as the web. */
final class WebIcons {
  static android.graphics.drawable.Drawable load(android.content.Context context, String name) {
    if(name.equals("call")||name.equals("phone")||name.equals("phone_off")){int call=context.getResources().getIdentifier("ic_flow_call_"+(name.equals("call")?"phone":name),"drawable",context.getPackageName());if(call!=0)return context.getDrawable(call).mutate();}
    int preferred = resolve(context, name);
    if (preferred != 0) try { return context.getDrawable(preferred).mutate(); } catch (RuntimeException invalidVector) { }
    int legacy = context.getResources().getIdentifier("ic_" + name, "drawable", context.getPackageName());
    if (legacy != 0 && legacy != preferred) try { return context.getDrawable(legacy).mutate(); } catch (RuntimeException invalidVector) { }
    return new android.graphics.drawable.ColorDrawable(android.graphics.Color.TRANSPARENT);
  }
  static int resolve(android.content.Context context, String name) {
    String web = name;
    switch (name.replace('-','_')) {
      case "group_three":web="users_round";break;
      case "menu_lines":web="menu";break;
      case "about_info":web="info";break;
      case "bell_ring":web="bell";break;
      case "user_search":web="search";break;
      case "distance_pins":web="map_pin";break;
      case "activity_status":web="radio";break;
      case "image_lock":web="lock_keyhole";break;
      case "user_block":web="user_round_x";break;
      case "post_heart":web="heart";break;
      case "location_off":web="map_pin_off";break;
      case "circle_help":web="circle_help";break;

      case "call": web = "phone"; break;
      case "attach": web = "paperclip"; break;
      case "sound": web = "volume_2"; break;
      case "music": web = "music_2"; break;
      case "flip": web = "switch_camera"; break;
      case "send_horizontal":web="send_horizontal";break;
      case "shield_check":web="shield_check";break;
      case "wand": web = "wand_sparkles"; break;
      case "flag": web = "flag"; break;
      case "type": web = "type"; break;
      case "upload": web = "upload"; break;
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
    int flow=context.getResources().getIdentifier("ic_flow_web_"+web.replace('-','_'),"drawable",context.getPackageName());if(flow!=0)return flow;
    int legacyFlow=context.getResources().getIdentifier("ic_flow_"+name.replace('-','_'),"drawable",context.getPackageName());if(legacyFlow!=0)return legacyFlow;
    int id = context.getResources().getIdentifier("ic_web_" + web.replace('-', '_'), "drawable", context.getPackageName());
    return id != 0 ? id : context.getResources().getIdentifier("ic_" + name, "drawable", context.getPackageName());
  }
}
