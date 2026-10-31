package app.kinnect.live;

import java.io.File;
import java.util.*;

/**
 * Timeline model of the media editor. Main clips play one after another; a transition into a clip
 * overlaps it with the previous clip. Layers (text, stickers, images, captions) and audio tracks sit
 * on their own lanes. All times are in seconds on the output timeline unless named "source".
 */
final class EditorProject {
  private static int nextId = 1;
  static int newId() { return nextId++; }

  /** Keyframe of an item's transform, at a time relative to the item's start. */
  static final class Key {
    float t, x, y, scale, rotation, opacity; boolean smooth = true;
    Key copy() { Key k = new Key(); k.t = t; k.x = x; k.y = y; k.scale = scale; k.rotation = rotation; k.opacity = opacity; k.smooth = smooth; return k; }
  }

  static final int X = 0, Y = 1, SCALE = 2, ROTATION = 3, OPACITY = 4;

  /** Anything with a transform that can be animated with keyframes. */
  static class Item {
    int id = nextId++;
    float x = .5f, y = .5f, scale = 1, rotation = 0, opacity = 1;
    final ArrayList<Key> keys = new ArrayList<>();

    void copyInto(Item o) { o.id = id; o.x = x; o.y = y; o.scale = scale; o.rotation = rotation; o.opacity = opacity; for (Key k : keys) o.keys.add(k.copy()); }

    float base(int field) { return field == X ? x : field == Y ? y : field == SCALE ? scale : field == ROTATION ? rotation : opacity; }
    void setBase(int field, float v) { if (field == X) x = v; else if (field == Y) y = v; else if (field == SCALE) scale = v; else if (field == ROTATION) rotation = v; else opacity = v; }
    static float get(Key k, int field) { return field == X ? k.x : field == Y ? k.y : field == SCALE ? k.scale : field == ROTATION ? k.rotation : k.opacity; }
    static void put(Key k, int field, float v) { if (field == X) k.x = v; else if (field == Y) k.y = v; else if (field == SCALE) k.scale = v; else if (field == ROTATION) k.rotation = v; else k.opacity = v; }

    /** {x, y, scale, rotation, opacity} at a local time, interpolating keyframes. */
    float[] pose(float local) {
      float[] p = new float[5];
      if (keys.isEmpty()) { for (int f = 0; f < 5; f++) p[f] = base(f); return p; }
      Key a = keys.get(0), b = keys.get(keys.size() - 1);
      if (local <= a.t) { for (int f = 0; f < 5; f++) p[f] = get(a, f); return p; }
      if (local >= b.t) { for (int f = 0; f < 5; f++) p[f] = get(b, f); return p; }
      for (int i = 1; i < keys.size(); i++) {
        Key k0 = keys.get(i - 1), k1 = keys.get(i);
        if (local > k1.t) continue;
        float u = (local - k0.t) / Math.max(.0001f, k1.t - k0.t);
        if (k0.smooth) u = u * u * (3 - 2 * u);
        for (int f = 0; f < 5; f++) p[f] = get(k0, f) + (get(k1, f) - get(k0, f)) * u;
        break;
      }
      return p;
    }

    Key keyAt(float local) { for (Key k : keys) if (Math.abs(k.t - local) < .05f) return k; return null; }

    /** Adds a keyframe at the local time holding the current pose, or returns the existing one. */
    Key addKey(float local) {
      Key k = keyAt(local); if (k != null) return k;
      float[] p = pose(local); k = new Key(); k.t = local; k.x = p[X]; k.y = p[Y]; k.scale = p[SCALE]; k.rotation = p[ROTATION]; k.opacity = p[OPACITY];
      keys.add(k); Collections.sort(keys, (l, r) -> Float.compare(l.t, r.t)); return k;
    }

    /** Edits one property. With keyframes the change lands on a keyframe at the playhead, like CapCut. */
    void edit(float local, int field, float v) { if (keys.isEmpty()) setBase(field, v); else put(addKey(local), field, v); }

    void shiftKeys(float by, float length) {
      for (Iterator<Key> it = keys.iterator(); it.hasNext();) { Key k = it.next(); k.t += by; if (k.t < -.001f || k.t > length + .001f) it.remove(); }
    }
  }

  static final class Clip extends Item {
    File file; boolean video, hasAudio;
    int width, height;             // display size, rotation applied
    float in, out, source;         // source seconds; source = full source length
    float speed = 1, volume = 1;
    int turn;                      // 0/90/180/270
    String transition = "none";    // transition INTO this clip
    float transitionLength = .5f;
    FxEngine fx = new FxEngine();
    float length() { return Math.max(.1f, (out - in) / speed); }
    Clip copy() {
      Clip c = new Clip(); copyInto(c); c.file = file; c.video = video; c.hasAudio = hasAudio; c.width = width; c.height = height;
      c.in = in; c.out = out; c.source = source; c.speed = speed; c.volume = volume; c.turn = turn; c.transition = transition;
      c.transitionLength = transitionLength; c.fx = fx.copy(); c.fx.beautyOn = fx.beautyOn; return c;
    }
  }

  static final class Layer extends Item {
    String kind = "text";          // text, caption, sticker, image
    String text = "", font = "sans-serif", style = "stroke", align = "center", animIn = "fade", animOut = "fade";
    int color = 0xffffffff; float size = .06f, start, length = 3, animLength = .4f;
    File image;
    Layer copy() {
      Layer l = new Layer(); copyInto(l); l.kind = kind; l.text = text; l.font = font; l.style = style; l.align = align; l.animIn = animIn;
      l.animOut = animOut; l.color = color; l.size = size; l.start = start; l.length = length; l.animLength = animLength; l.image = image; return l;
    }
  }

  static final class Track {
    int id = nextId++;
    String kind = "music", name = "";  // music, voice
    File file; float start, in, length, source, gain = 1, fadeIn, fadeOut;
    Track copy() {
      Track t = new Track(); t.id = id; t.kind = kind; t.name = name; t.file = file; t.start = start; t.in = in; t.length = length;
      t.source = source; t.gain = gain; t.fadeIn = fadeIn; t.fadeOut = fadeOut; return t;
    }
  }

  final ArrayList<Clip> clips = new ArrayList<>();
  final ArrayList<Layer> layers = new ArrayList<>();
  final ArrayList<Track> tracks = new ArrayList<>();
  float aspect = 0;                // 0 = follow the first clip
  String background = "blur";      // black, white, blur, or #rrggbb
  int exportSide = 1080;

  EditorProject copy() {
    EditorProject p = new EditorProject();
    for (Clip c : clips) p.clips.add(c.copy());
    for (Layer l : layers) p.layers.add(l.copy());
    for (Track t : tracks) p.tracks.add(t.copy());
    p.aspect = aspect; p.background = background; p.exportSide = exportSide; return p;
  }

  /** Effective transition overlap into clip i (never more than half of either neighbour). */
  float overlap(int i) {
    if (i <= 0 || i >= clips.size()) return 0;
    Clip c = clips.get(i); if (c.transition.equals("none")) return 0;
    return Math.min(c.transitionLength, Math.min(clips.get(i - 1).length(), c.length()) / 2);
  }

  float[] starts() {
    float[] s = new float[clips.size()]; float t = 0;
    for (int i = 0; i < clips.size(); i++) { t -= overlap(i); s[i] = t; t += clips.get(i).length(); }
    return s;
  }

  float duration() {
    if (clips.isEmpty()) return 0; float[] s = starts();
    return s[s.length - 1] + clips.get(clips.size() - 1).length();
  }

  int indexOf(int clipId) { for (int i = 0; i < clips.size(); i++) if (clips.get(i).id == clipId) return i; return -1; }
  Clip clip(int id) { for (Clip c : clips) if (c.id == id) return c; return null; }
  Layer layer(int id) { for (Layer l : layers) if (l.id == id) return l; return null; }
  Track track(int id) { for (Track t : tracks) if (t.id == id) return t; return null; }

  /** Index of the clip shown at time t (the incoming one while a transition runs). */
  int clipAt(float t) {
    float[] s = starts(); int found = clips.isEmpty() ? -1 : 0;
    for (int i = 0; i < s.length; i++) if (t >= s[i] - .0001f) found = i;
    return found;
  }

  float outputAspect() {
    if (aspect > 0) return aspect;
    if (clips.isEmpty()) return 9 / 16f;
    Clip c = clips.get(0); boolean side = c.turn % 180 != 0;
    return side ? c.height / (float) Math.max(1, c.width) : c.width / (float) Math.max(1, c.height);
  }

  /** True when the result is a single still photo, so it can be exported as an image. */
  boolean still() {
    if (clips.size() != 1 || clips.get(0).video || !tracks.isEmpty()) return false;
    if (!clips.get(0).keys.isEmpty()) return false;
    for (Layer l : layers) if (!l.keys.isEmpty()) return false;
    return true;
  }
}
