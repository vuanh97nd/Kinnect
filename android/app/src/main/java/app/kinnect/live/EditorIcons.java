package app.kinnect.live;
import android.widget.TextView;import android.graphics.drawable.Drawable;
/** Consistent outline vectors. Numeric speed and duration controls stay numeric. */
final class EditorIcons {
 static String alias(String id){switch(id){case "×":return "close";case "✧":case "✨":return "beauty";case "🕶":return "sticker";case "◈":return "filter";case "✂":return "cut";case "1×":return "speed";case "♫":return "music";case "T":return "text";case "↶":return "undo";case "↷":return "redo";case "◐":return "compare";case "▷":return "play";case "⇩":return "export";case "✓":return "check";case "○":return "none";case "🌸":return "blush";case "🎀":return "beauty";case "👀":return "eyes";case "💋":return "lips";}return id;}
 static Drawable drawable(android.content.Context c,String id,int color){int resource=c.getResources().getIdentifier("ic_editor_"+alias(id),"drawable",c.getPackageName());if(resource==0)return null;Drawable d=c.getDrawable(resource).mutate();d.setTint(color);return d;}
 static boolean apply(TextView view,String id,int size,int color){int resource=view.getResources().getIdentifier("ic_editor_"+alias(id),"drawable",view.getContext().getPackageName());if(resource==0)return false;Drawable d=view.getContext().getDrawable(resource).mutate();d.setTint(color);int px=Math.round(size*view.getResources().getDisplayMetrics().density);d.setBounds(0,0,px,px);view.setText("");view.setCompoundDrawables(d,null,null,null);view.setCompoundDrawablePadding(0);return true;}
}
