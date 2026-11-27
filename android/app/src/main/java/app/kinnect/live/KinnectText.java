package app.kinnect.live;
import android.content.Context;
import android.graphics.*;
import android.graphics.drawable.Drawable;
import android.text.*;
import android.text.style.ReplacementSpan;
import android.widget.TextView;
import java.util.HashMap;

/** App typography and locally bundled Noto reaction artwork; retains Unicode text for accessibility. */
final class KinnectText extends TextView {
  private static final HashMap<Integer, Integer> EMOJI_DRAWABLE_CACHE = new HashMap<>();
  private boolean changing;

  KinnectText(Context c) {
    super(c);
    setTypeface(ApprovedTypography.font(c, Typeface.NORMAL));
    setIncludeFontPadding(true);
  }

  private static Typeface cachedFont(Context ctx, int style) {
    return ApprovedTypography.font(ctx, style);
  }

  private static int resolveEmojiId(Context ctx, int cp) {
    if (cp < 0x2000 || ctx == null) return 0;
    synchronized (EMOJI_DRAWABLE_CACHE) {
      Integer cached = EMOJI_DRAWABLE_CACHE.get(cp);
      if (cached != null) return cached;
    }
    int id = ctx.getResources().getIdentifier("emoji_noto_" + Integer.toHexString(cp), "drawable", ctx.getPackageName());
    synchronized (EMOJI_DRAWABLE_CACHE) {
      EMOJI_DRAWABLE_CACHE.put(cp, id);
    }
    return id;
  }

  @Override
  public void setTypeface(Typeface face, int style) {
    try {
      Typeface chosen = cachedFont(getContext(), style);
      if (chosen != null) {
        super.setTypeface(chosen);
      } else {
        super.setTypeface(face, style);
      }
    } catch (Exception e) {
      super.setTypeface(face);
    }
  }

  @Override
  public void setTypeface(Typeface face) {
    setTypeface(face, face != null ? face.getStyle() : Typeface.NORMAL);
  }

  @Override
  public void setText(CharSequence text, BufferType type) {
    if (changing || text == null || text.length() == 0) {
      super.setText(text, type);
      return;
    }
    boolean hasHighCp = false;
    for (int i = 0; i < text.length(); ) {
      int cp = Character.codePointAt(text, i);
      if (cp >= 0x2000) {
        hasHighCp = true;
        break;
      }
      i += Character.charCount(cp);
    }
    if (!hasHighCp) {
      super.setText(text, type);
      return;
    }
    changing = true;
    try {
      SpannableStringBuilder b = null;
      Context ctx = getContext();
      for (int i = 0; i < text.length(); ) {
        int cp = Character.codePointAt(text, i), n = Character.charCount(cp), end = i + n;
        if (end < text.length() && text.charAt(end) == '\ufe0f') end++;
        if (cp >= 0x2000) {
          int id = resolveEmojiId(ctx, cp);
          boolean compound = (i > 0 && text.charAt(i - 1) == 0x200d)
            || (end < text.length()
              && (text.charAt(end) == 0x200d
                || (Character.codePointAt(text, end) >= 0x1f3fb && Character.codePointAt(text, end) <= 0x1f3ff)));
          if (id != 0 && !compound) {
            Drawable raw = ctx.getDrawable(id);
            if (raw != null) {
              if (b == null) b = new SpannableStringBuilder(text);
              b.setSpan(new Emoji(raw.mutate()), i, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
            }
          }
        }
        i = end;
      }
      super.setText(b != null ? b : text, type);
    } finally {
      changing = false;
    }
  }

  private static final class Emoji extends ReplacementSpan {
    final Drawable icon;
    Emoji(Drawable d) { icon = d; }
    public int getSize(Paint p, CharSequence s, int start, int end, Paint.FontMetricsInt fm) {
      int size = Math.round(p.getTextSize() * 1.12f);
      if (fm != null) {
        p.getFontMetricsInt(fm);
        int mid = (fm.ascent + fm.descent) / 2;
        int half = (size + 1) / 2;
        int spanAscent = mid - half;
        int spanDescent = spanAscent + size;
        if (spanAscent < fm.ascent) fm.ascent = spanAscent;
        if (spanDescent > fm.descent) fm.descent = spanDescent;
        if (fm.ascent < fm.top) fm.top = fm.ascent;
        if (fm.descent > fm.bottom) fm.bottom = fm.descent;
      }
      return size;
    }
    public void draw(Canvas c, CharSequence s, int start, int end, float x, int top, int y, int bottom, Paint p) {
      int size = Math.round(p.getTextSize() * 1.12f);
      int save = c.save();
      c.translate(x, y + (p.ascent() + p.descent() - size) / 2);
      icon.setBounds(0, 0, size, size);
      icon.draw(c);
      c.restoreToCount(save);
    }
  }
}
