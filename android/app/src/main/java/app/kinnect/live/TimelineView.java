package app.kinnect.live;

import android.content.Context;
import android.graphics.*;
import android.graphics.drawable.Drawable;
import android.os.SystemClock;
import android.view.*;
import java.util.*;

/**
 * CapCut-style multi-track timeline. The playhead stays in the middle; dragging scrolls time,
 * pinching zooms, the white handles of the selected item trim it, and a long press drags a layer
 * or audio clip to a new time.
 */
final class TimelineView extends View {
  interface Host {
    EditorProject project(); float playhead(); void scrub(float t, boolean done);
    String selectedKind(); int selectedId(); void select(String kind, int id);
    Bitmap[] thumbs(EditorProject.Clip clip); void addClip(); void transition(int clipIndex);
    void beginChange(); void changed();
  }

  private final Host host; private final float dp;
  private float pps; // pixels per second
  private final Paint fill = new Paint(Paint.ANTI_ALIAS_FLAG), stroke = new Paint(Paint.ANTI_ALIAS_FLAG), label = new Paint(Paint.ANTI_ALIAS_FLAG), bmp = new Paint(Paint.FILTER_BITMAP_FLAG);
  private final ScaleGestureDetector pinch;
  private final Drawable transitionIcon, transitionOn, plusIcon;
  private final float ruler, mainTop, mainH, laneH, laneGap;
  private final List<Object> laneItems = new ArrayList<>(); // parallel to laneRows
  private final List<Integer> laneRows = new ArrayList<>();
  private int lanes;

  TimelineView(Context c, Host host) {
    super(c); this.host = host; dp = c.getResources().getDisplayMetrics().density; pps = 56 * dp;
    ruler = 22 * dp; mainTop = ruler + 6 * dp; mainH = 54 * dp; laneH = 26 * dp; laneGap = 5 * dp;
    label.setTextSize(10.5f * dp); label.setColor(Color.WHITE); label.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
    stroke.setStyle(Paint.Style.STROKE);
    transitionIcon = icon(c, "transition", 0xff201b2e); transitionOn = icon(c, "transition", Color.WHITE); plusIcon = icon(c, "add", 0xff201b2e);
    pinch = new ScaleGestureDetector(c, new ScaleGestureDetector.SimpleOnScaleGestureListener() {
      @Override public boolean onScale(ScaleGestureDetector d) { pps = Math.max(8 * dp, Math.min(420 * dp, pps * d.getScaleFactor())); invalidate(); return true; }
    });
  }

  private static Drawable icon(Context c, String name, int tint) {
    int id = c.getResources().getIdentifier("ic_editor_" + name, "drawable", c.getPackageName());
    if (id == 0) return null; Drawable d = c.getDrawable(id).mutate(); d.setTint(tint); return d;
  }

  private float x(float t) { return getWidth() / 2f + (t - host.playhead()) * pps; }
  private float time(float x) { return host.playhead() + (x - getWidth() / 2f) / pps; }

  /** Packs layers then tracks into non-overlapping lanes. */
  private void pack() {
    laneItems.clear(); laneRows.clear(); EditorProject p = host.project();
    List<float[]> ends = new ArrayList<>(); int layerLanes;
    List<EditorProject.Layer> layers = new ArrayList<>(p.layers); Collections.sort(layers, (a, b) -> Float.compare(a.start, b.start));
    for (EditorProject.Layer l : layers) { int row = 0; while (row < ends.size() && ends.get(row)[0] > l.start + .001f) row++; if (row == ends.size()) ends.add(new float[1]); ends.get(row)[0] = l.start + l.length; laneItems.add(l); laneRows.add(row); }
    layerLanes = ends.size(); ends.clear();
    List<EditorProject.Track> tracks = new ArrayList<>(p.tracks); Collections.sort(tracks, (a, b) -> Float.compare(a.start, b.start));
    for (EditorProject.Track t : tracks) { int row = 0; while (row < ends.size() && ends.get(row)[0] > t.start + .001f) row++; if (row == ends.size()) ends.add(new float[1]); ends.get(row)[0] = t.start + t.length; laneItems.add(t); laneRows.add(layerLanes + row); }
    int newLanes = layerLanes + ends.size();
    if (newLanes != lanes) { lanes = newLanes; requestLayout(); }
  }

  @Override protected void onMeasure(int w, int h) {
    pack(); int height = Math.round(mainTop + mainH + 10 * dp + Math.max(2, lanes) * (laneH + laneGap) + 8 * dp);
    setMeasuredDimension(MeasureSpec.getSize(w), height);
  }

  private float laneTop(int row) { return mainTop + mainH + 10 * dp + row * (laneH + laneGap); }

  @Override protected void onDraw(Canvas c) {
    pack(); EditorProject p = host.project(); float w = getWidth(); float[] starts = p.starts(); float duration = p.duration();
    c.drawColor(0xff15121d);
    // Ruler: pick a tick spacing that leaves at least ~56dp between labels.
    float[] steps = { .25f, .5f, 1, 2, 5, 10, 15, 30, 60 }; float step = 60; for (float s : steps) if (s * pps >= 56 * dp) { step = s; break; }
    label.setColor(0xff8f86a3); label.setTextAlign(Paint.Align.CENTER);
    float first = (float) Math.floor(time(0) / step) * step;
    for (float t = Math.max(0, first); t <= time(w) && t <= duration + step; t += step) {
      float x = x(t); c.drawText(clock(t), x, ruler - 8 * dp, label);
      fill.setColor(0xff4a4358); c.drawCircle(x + step * pps / 2, ruler - 11.5f * dp, 1.4f * dp, fill);
    }
    // Main clips with filmstrip thumbnails.
    String kind = host.selectedKind(); int sel = host.selectedId();
    for (int i = 0; i < p.clips.size(); i++) {
      EditorProject.Clip clip = p.clips.get(i); float l = x(starts[i]), r = x(starts[i] + clip.length());
      if (r < 0 || l > w) continue;
      RectF box = new RectF(l + 1 * dp, mainTop, r - 1 * dp, mainTop + mainH);
      c.save(); Path round = new Path(); round.addRoundRect(box, 6 * dp, 6 * dp, Path.Direction.CW); c.clipPath(round);
      fill.setColor(0xff2d2638); c.drawRect(box, fill);
      Bitmap[] thumbs = host.thumbs(clip);
      if (thumbs != null && thumbs.length > 0 && thumbs[0] != null) {
        float tile = mainH * thumbs[0].getWidth() / (float) Math.max(1, thumbs[0].getHeight());
        for (float tx = box.left; tx < box.right; tx += tile) {
          if (tx + tile < 0 || tx > w) continue;
          float source = clip.in + (tx + tile / 2 - l) / pps * clip.speed; int idx = Math.max(0, Math.min(thumbs.length - 1, (int) (source / Math.max(.01f, clip.source) * thumbs.length)));
          if (!clip.video) idx = 0; Bitmap b = thumbs[idx]; if (b != null && !b.isRecycled()) c.drawBitmap(b, null, new RectF(tx, box.top, tx + tile, box.bottom), bmp);
        }
      }
      if (clip.speed != 1 || clip.volume == 0) {
        String tag = (clip.speed != 1 ? trimNumber(clip.speed) + "×" : "") + (clip.volume == 0 ? (clip.speed != 1 ? " · " : "") + "Tắt tiếng" : "");
        label.setTextAlign(Paint.Align.LEFT); float tw = label.measureText(tag); fill.setColor(0x99000000);
        c.drawRoundRect(new RectF(box.left + 4 * dp, box.top + 4 * dp, box.left + 12 * dp + tw, box.top + 20 * dp), 4 * dp, 4 * dp, fill);
        label.setColor(Color.WHITE); c.drawText(tag, box.left + 8 * dp, box.top + 16 * dp, label);
      }
      c.restore();
      label.setTextAlign(Paint.Align.RIGHT); label.setColor(Color.WHITE); label.setShadowLayer(3 * dp, 0, 0, Color.BLACK);
      if (box.width() > 48 * dp) c.drawText(clock(clip.length()), box.right - 5 * dp, box.bottom - 5 * dp, label);
      label.clearShadowLayer();
      drawKeys(c, clip, starts[i], box, "clip".equals(kind) && sel == clip.id);
      if ("clip".equals(kind) && sel == clip.id) handles(c, box);
    }
    // Transition markers between clips.
    for (int i = 1; i < p.clips.size(); i++) {
      float mx = x(starts[i] + p.overlap(i) / 2); if (mx < -20 * dp || mx > w + 20 * dp) continue;
      boolean on = !p.clips.get(i).transition.equals("none"); float s = 10 * dp, cy = mainTop + mainH / 2;
      fill.setColor(on ? 0xff7c5cff : Color.WHITE); c.drawRoundRect(new RectF(mx - s, cy - s, mx + s, cy + s), 4 * dp, 4 * dp, fill);
      Drawable d = on ? transitionOn : transitionIcon; if (d != null) { d.setBounds(Math.round(mx - 7 * dp), Math.round(cy - 7 * dp), Math.round(mx + 7 * dp), Math.round(cy + 7 * dp)); d.draw(c); }
    }
    // Add-clip button after the last clip.
    if (!p.clips.isEmpty()) {
      float ax = x(duration) + 10 * dp, cy = mainTop + mainH / 2, s = 15 * dp;
      fill.setColor(Color.WHITE); c.drawRoundRect(new RectF(ax, cy - s, ax + 2 * s, cy + s), 6 * dp, 6 * dp, fill);
      if (plusIcon != null) { plusIcon.setBounds(Math.round(ax + 5 * dp), Math.round(cy - 10 * dp), Math.round(ax + 25 * dp), Math.round(cy + 10 * dp)); plusIcon.draw(c); }
    }
    // Lanes.
    for (int i = 0; i < laneItems.size(); i++) {
      Object o = laneItems.get(i); float top = laneTop(laneRows.get(i));
      float start, length; int color; String name; boolean selected; EditorProject.Item keyed = null;
      if (o instanceof EditorProject.Layer) {
        EditorProject.Layer l = (EditorProject.Layer) o; start = l.start; length = l.length; keyed = l; selected = "layer".equals(kind) && sel == l.id;
        color = l.kind.equals("caption") ? 0xff8b5cf6 : l.kind.equals("sticker") ? 0xffd69e2e : l.kind.equals("image") ? 0xff3b82f6 : 0xffe0803a;
        name = l.kind.equals("image") ? "Lớp phủ ảnh" : l.text.replace('\n', ' ');
      } else {
        EditorProject.Track t = (EditorProject.Track) o; start = t.start; length = t.length; selected = "track".equals(kind) && sel == t.id;
        color = t.kind.equals("voice") ? 0xff0ea5b7 : 0xff22a565; name = (t.kind.equals("voice") ? "Ghi âm" : "Nhạc") + (t.name.isEmpty() ? "" : " · " + t.name);
      }
      RectF box = new RectF(x(start) + 1 * dp, top, x(start + length) - 1 * dp, top + laneH);
      if (box.right < 0 || box.left > w) continue;
      fill.setColor(color); c.drawRoundRect(box, 5 * dp, 5 * dp, fill);
      if (o instanceof EditorProject.Track) wave(c, box);
      c.save(); c.clipRect(box); label.setTextAlign(Paint.Align.LEFT); label.setColor(Color.WHITE);
      c.drawText(name, Math.max(box.left, 0) + 8 * dp, box.centerY() + 4 * dp, label); c.restore();
      if (keyed != null) drawKeys(c, keyed, start, box, selected);
      if (selected) handles(c, box);
    }
    // Playhead.
    fill.setColor(Color.WHITE); c.drawRect(w / 2f - 1 * dp, 2 * dp, w / 2f + 1 * dp, getHeight(), fill);
    c.drawCircle(w / 2f, 3 * dp, 3.5f * dp, fill);
  }

  private void wave(Canvas c, RectF box) {
    fill.setColor(0x40ffffff); float bar = 3 * dp;
    for (float x = box.left + 4 * dp; x < box.right - 4 * dp; x += bar) {
      double n = Math.abs(Math.sin(x * 0.37) * Math.cos(x * 0.11)); float hh = (float) (box.height() * (.15 + .55 * n));
      c.drawRect(x, box.centerY() - hh / 2, x + bar * .55f, box.centerY() + hh / 2, fill);
    }
  }

  private void drawKeys(Canvas c, EditorProject.Item item, float start, RectF box, boolean selected) {
    if (item.keys.isEmpty()) return; fill.setColor(selected ? 0xffffd45c : 0xccffffff);
    for (EditorProject.Key k : item.keys) {
      float kx = x(start + k.t), cy = box.bottom - 6 * dp, s = 4.5f * dp; Path d = new Path();
      d.moveTo(kx, cy - s); d.lineTo(kx + s, cy); d.lineTo(kx, cy + s); d.lineTo(kx - s, cy); d.close(); c.drawPath(d, fill);
    }
  }

  private void handles(Canvas c, RectF box) {
    stroke.setColor(Color.WHITE); stroke.setStrokeWidth(2 * dp); c.drawRoundRect(box, 6 * dp, 6 * dp, stroke);
    fill.setColor(Color.WHITE); float hw = 11 * dp;
    RectF left = new RectF(box.left - hw, box.top, box.left, box.bottom), right = new RectF(box.right, box.top, box.right + hw, box.bottom);
    c.drawRoundRect(left, 4 * dp, 4 * dp, fill); c.drawRoundRect(right, 4 * dp, 4 * dp, fill);
    fill.setColor(0xff201b2e); float gh = Math.min(10 * dp, box.height() / 3);
    c.drawRect(left.centerX() - .8f * dp, left.centerY() - gh, left.centerX() + .8f * dp, left.centerY() + gh, fill);
    c.drawRect(right.centerX() - .8f * dp, right.centerY() - gh, right.centerX() + .8f * dp, right.centerY() + gh, fill);
  }

  static String clock(float t) { int s = Math.max(0, Math.round(t * 10)); int tenths = s % 10; s /= 10; return String.format(Locale.US, s >= 60 ? "%d:%02d" : "00:%02d", s >= 60 ? s / 60 : s, s % 60) + (tenths != 0 && s < 10 ? "." + tenths : ""); }
  private static String trimNumber(float v) { return v == Math.round(v) ? String.valueOf(Math.round(v)) : String.valueOf(v); }

  // ----- Touch -----
  private static final int NONE = 0, PENDING = 1, SCROLL = 2, TRIM_LEFT = 3, TRIM_RIGHT = 4, MOVE = 5;
  private int mode; private float downX, downY, lastX; private long downAt; private Object hitItem; private boolean longPressed;

  private Object hit(float px, float py) {
    EditorProject p = host.project(); float t = time(px);
    if (py >= mainTop && py <= mainTop + mainH) { float[] s = p.starts(); for (int i = p.clips.size() - 1; i >= 0; i--) if (t >= s[i] && t < s[i] + p.clips.get(i).length()) return p.clips.get(i); }
    for (int i = 0; i < laneItems.size(); i++) {
      float top = laneTop(laneRows.get(i)); if (py < top - 2 * dp || py > top + laneH + 2 * dp) continue;
      Object o = laneItems.get(i); float start = o instanceof EditorProject.Layer ? ((EditorProject.Layer) o).start : ((EditorProject.Track) o).start;
      float length = o instanceof EditorProject.Layer ? ((EditorProject.Layer) o).length : ((EditorProject.Track) o).length;
      if (t >= start && t <= start + length) return o;
    }
    return null;
  }

  private RectF selectedBox() {
    EditorProject p = host.project(); String kind = host.selectedKind(); int id = host.selectedId(); if (kind == null) return null;
    if (kind.equals("clip")) { int i = p.indexOf(id); if (i < 0) return null; float s = p.starts()[i]; return new RectF(x(s), mainTop, x(s + p.clips.get(i).length()), mainTop + mainH); }
    for (int i = 0; i < laneItems.size(); i++) {
      Object o = laneItems.get(i); boolean match = o instanceof EditorProject.Layer ? kind.equals("layer") && ((EditorProject.Layer) o).id == id : kind.equals("track") && ((EditorProject.Track) o).id == id;
      if (!match) continue; float top = laneTop(laneRows.get(i));
      float start = o instanceof EditorProject.Layer ? ((EditorProject.Layer) o).start : ((EditorProject.Track) o).start, length = o instanceof EditorProject.Layer ? ((EditorProject.Layer) o).length : ((EditorProject.Track) o).length;
      return new RectF(x(start), top, x(start + length), top + laneH);
    }
    return null;
  }

  @Override public boolean onTouchEvent(MotionEvent e) {
    pinch.onTouchEvent(e);
    if (e.getPointerCount() > 1) { if (mode == SCROLL || mode == PENDING) mode = NONE; getParent().requestDisallowInterceptTouchEvent(true); return true; }
    float px = e.getX(), py = e.getY(); float slop = 8 * dp;
    switch (e.getActionMasked()) {
      case MotionEvent.ACTION_DOWN: {
        downX = lastX = px; downY = py; downAt = SystemClock.uptimeMillis(); longPressed = false; mode = PENDING; hitItem = hit(px, py);
        RectF box = selectedBox();
        if (box != null && py >= box.top - 4 * dp && py <= box.bottom + 4 * dp) {
          if (Math.abs(px - box.left) < 16 * dp) { mode = TRIM_LEFT; host.beginChange(); }
          else if (Math.abs(px - box.right) < 16 * dp) { mode = TRIM_RIGHT; host.beginChange(); }
        }
        if (mode != PENDING) getParent().requestDisallowInterceptTouchEvent(true);
        else postDelayed(() -> { if (mode == PENDING && hitItem != null && !(hitItem instanceof EditorProject.Clip)) { longPressed = true; mode = MOVE; select(hitItem); host.beginChange(); performHapticFeedback(HapticFeedbackConstants.LONG_PRESS); getParent().requestDisallowInterceptTouchEvent(true); } }, 380);
        return true; }
      case MotionEvent.ACTION_MOVE: {
        float dx = px - lastX;
        if (mode == PENDING && (Math.abs(px - downX) > slop || Math.abs(py - downY) > slop)) {
          if (Math.abs(px - downX) > Math.abs(py - downY)) { mode = SCROLL; getParent().requestDisallowInterceptTouchEvent(true); }
          else { mode = NONE; return false; }
        }
        if (mode == SCROLL) { host.scrub(Math.max(0, Math.min(host.project().duration(), host.playhead() - dx / pps)), false); }
        else if (mode == TRIM_LEFT || mode == TRIM_RIGHT) trim(dx / pps, mode == TRIM_LEFT);
        else if (mode == MOVE) move(dx / pps);
        lastX = px; invalidate(); return true; }
      case MotionEvent.ACTION_UP: {
        if (mode == PENDING && !longPressed) tap(px, py);
        else if (mode == SCROLL) host.scrub(host.playhead(), true);
        else if (mode == TRIM_LEFT || mode == TRIM_RIGHT || mode == MOVE) host.changed();
        mode = NONE; invalidate(); return true; }
      case MotionEvent.ACTION_CANCEL:
        if (mode == TRIM_LEFT || mode == TRIM_RIGHT || mode == MOVE) host.changed();
        mode = NONE; return true;
    }
    return true;
  }

  private void select(Object o) {
    if (o instanceof EditorProject.Clip) host.select("clip", ((EditorProject.Clip) o).id);
    else if (o instanceof EditorProject.Layer) host.select("layer", ((EditorProject.Layer) o).id);
    else if (o instanceof EditorProject.Track) host.select("track", ((EditorProject.Track) o).id);
    else host.select(null, 0);
  }

  private void tap(float px, float py) {
    EditorProject p = host.project(); float[] s = p.starts();
    for (int i = 1; i < p.clips.size(); i++) { float mx = x(s[i] + p.overlap(i) / 2), cy = mainTop + mainH / 2; if (Math.abs(px - mx) < 16 * dp && Math.abs(py - cy) < 16 * dp) { host.transition(i); return; } }
    if (!p.clips.isEmpty()) { float ax = x(p.duration()) + 10 * dp, cy = mainTop + mainH / 2; if (px >= ax - 4 * dp && px <= ax + 34 * dp && Math.abs(py - cy) < 20 * dp) { host.addClip(); return; } }
    Object o = hit(px, py);
    String kind = host.selectedKind(); int id = host.selectedId();
    boolean same = o instanceof EditorProject.Clip && "clip".equals(kind) && ((EditorProject.Clip) o).id == id || o instanceof EditorProject.Layer && "layer".equals(kind) && ((EditorProject.Layer) o).id == id || o instanceof EditorProject.Track && "track".equals(kind) && ((EditorProject.Track) o).id == id;
    select(same ? null : o);
  }

  private void trim(float dt, boolean left) {
    EditorProject p = host.project(); String kind = host.selectedKind(); int id = host.selectedId(); if (kind == null) return;
    if (kind.equals("clip")) {
      EditorProject.Clip c = p.clip(id); if (c == null) return; float ds = dt * c.speed, min = .1f * c.speed;
      if (left) { float before = c.in; c.in = Math.max(0, Math.min(c.out - min, c.in + ds)); c.shiftKeys(-(c.in - before) / c.speed, c.length()); }
      else c.out = Math.max(c.in + min, Math.min(c.source, c.out + ds));
    } else if (kind.equals("layer")) {
      EditorProject.Layer l = p.layer(id); if (l == null) return;
      if (left) { float end = l.start + l.length, start = Math.max(0, Math.min(end - .2f, l.start + dt)); l.shiftKeys(-(start - l.start), end - start); l.start = start; l.length = end - start; }
      else l.length = Math.max(.2f, l.length + dt);
    } else {
      EditorProject.Track t = p.track(id); if (t == null) return;
      if (left) { float d = Math.max(-t.in, Math.max(-t.start, Math.min(t.length - .2f, dt))); t.start += d; t.in += d; t.length -= d; }
      else t.length = Math.max(.2f, Math.min(t.source - t.in, t.length + dt));
    }
  }

  private void move(float dt) {
    EditorProject p = host.project(); String kind = host.selectedKind(); int id = host.selectedId();
    if ("layer".equals(kind)) { EditorProject.Layer l = p.layer(id); if (l != null) l.start = Math.max(0, l.start + dt); }
    else if ("track".equals(kind)) { EditorProject.Track t = p.track(id); if (t != null) t.start = Math.max(0, t.start + dt); }
  }
}
