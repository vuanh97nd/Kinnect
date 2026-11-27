package app.kinnect.live;
import android.content.Context;import android.graphics.Typeface;
final class ApprovedTypography {
  private static volatile Typeface familyBase, regularBase, semiboldBase;
  private static volatile boolean fontsLoaded;
  private static final Typeface[] STYLED_CACHE = new Typeface[4];

  static Typeface font(Context c, int style) {
    int safeStyle = style & 3;
    Typeface cached = STYLED_CACHE[safeStyle];
    if (cached != null) return cached;
    if (!fontsLoaded && c != null) {
      synchronized (STYLED_CACHE) {
        if (!fontsLoaded) {
          android.content.res.Resources res = null;
          String pkg = null;
          try {
            res = c.getResources();
            pkg = c.getPackageName();
          } catch (Throwable ignored) {
          }
          if (res != null && pkg != null && !pkg.isEmpty()) {
            try {
              int famId = res.getIdentifier("kinnect_family", "font", pkg);
              if (famId != 0) familyBase = res.getFont(famId);
            } catch (Throwable ignored) {
            }
            if (familyBase == null) {
              try {
                int regId = res.getIdentifier("kinnect_regular", "font", pkg);
                if (regId != 0) regularBase = res.getFont(regId);
              } catch (Throwable ignored) {
              }
              try {
                int semiId = res.getIdentifier("kinnect_semibold", "font", pkg);
                if (semiId != 0) semiboldBase = res.getFont(semiId);
              } catch (Throwable ignored) {
              }
            }
            if (familyBase != null || regularBase != null || semiboldBase != null) {
              fontsLoaded = true;
            }
          }
        }
      }
    }
    Typeface base = familyBase != null ? familyBase
        : ((safeStyle & Typeface.BOLD) != 0
            ? (semiboldBase != null ? semiboldBase : regularBase)
            : regularBase);
    if (base != null) {
      Typeface styled = Typeface.create(base, safeStyle);
      if (styled != null) {
        STYLED_CACHE[safeStyle] = styled;
        return styled;
      }
    }
    return Typeface.create((safeStyle & Typeface.BOLD) != 0 ? "sans-serif-medium" : "sans-serif", safeStyle);
  }
  static void sheet(android.view.View view){if(view instanceof android.widget.TextView){android.widget.TextView text=(android.widget.TextView)view;String value=text.getText().toString();if(value.codePoints().anyMatch(Character::isLetterOrDigit)||text instanceof android.widget.EditText){int style=text.getTypeface()==null?Typeface.NORMAL:text.getTypeface().getStyle();text.setTypeface(font(view.getContext(),style));float size=text.getTextSize()/view.getResources().getDisplayMetrics().scaledDensity;Object tag=text.getTag();float max="sheet:title".equals(tag)?22:"sheet:display".equals(tag)?28:"sheet:heading".equals(tag)?20:text instanceof android.widget.Button?15:text instanceof android.widget.EditText?16:15;if(size>max)text.setTextSize(max);}}if(view instanceof android.view.ViewGroup){android.view.ViewGroup group=(android.view.ViewGroup)view;for(int i=0;i<group.getChildCount();i++)sheet(group.getChildAt(i));}}
}
