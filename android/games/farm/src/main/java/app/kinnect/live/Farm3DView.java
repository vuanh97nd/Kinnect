package app.kinnect.live;

import android.content.Context;
import android.graphics.Color;
import android.graphics.SurfaceTexture;
import android.opengl.EGL14;
import android.opengl.EGLContext;
import android.opengl.EGLDisplay;
import android.opengl.EGLSurface;
import android.opengl.GLES20;
import android.opengl.GLSurfaceView;
import android.opengl.Matrix;
import android.os.SystemClock;
import android.util.Log;
import android.view.MotionEvent;
import android.view.Surface;
import android.view.TextureView;
import android.view.ViewConfiguration;

import org.json.JSONArray;
import org.json.JSONObject;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.FloatBuffer;
import java.util.Arrays;

import javax.microedition.khronos.egl.EGLConfig;
import javax.microedition.khronos.opengles.GL10;

/** Stylized low-poly 3D farm rendered with OpenGL ES 2.0. */
final class Farm3DView extends TextureView implements TextureView.SurfaceTextureListener {
  interface PlotTapListener { void onPlotTap(int slot); }

  private static final float PLOT_GAP = 3.0f;
  private static final float PLOT_ROW = 1.75f;
  private static final float PICK_HALF = 1.32f;

  private final SceneRenderer scene;
  private RenderThread renderThread;
  private PlotTapListener listener;
  private volatile float yaw = 0.32f;
  private volatile float pitch = 0.70f;
  private volatile float distance = 15.5f;
  private volatile int selectedSlot = -1;
  private volatile float[] lastViewProj;
  private final int touchSlop;
  private float downX, downY, lastX, lastY, pinchStart, pinchDistance;
  private boolean dragging, moved;
  private long downAt;

  Farm3DView(Context context) {
    super(context);
    scene = new SceneRenderer(this);
    setSurfaceTextureListener(this);
    setOpaque(true);
    Log.d("Farm3D", "view created");
    touchSlop = ViewConfiguration.get(context).getScaledTouchSlop();
  }

  @Override public void onSurfaceTextureAvailable(SurfaceTexture texture, int width, int height) {
    startRender(texture, width, height);
  }

  @Override public void onSurfaceTextureSizeChanged(SurfaceTexture texture, int width, int height) {
    if (renderThread != null) {
      stopRender();
      startRender(texture, width, height);
    }
  }

  @Override public boolean onSurfaceTextureDestroyed(SurfaceTexture texture) {
    stopRender();
    return true;
  }

  @Override public void onSurfaceTextureUpdated(SurfaceTexture texture) { }

  private void startRender(SurfaceTexture texture, int width, int height) {
    stopRender();
    renderThread = new RenderThread(texture, Math.max(1, width), Math.max(1, height));
    renderThread.start();
  }

  private void stopRender() {
    RenderThread thread = renderThread;
    renderThread = null;
    if (thread == null) return;
    thread.stopRendering();
    try { thread.join(1500); } catch (InterruptedException ignored) { Thread.currentThread().interrupt(); }
  }

  private final class RenderThread extends Thread {
    private final SurfaceTexture texture;
    private final int width, height;
    private volatile boolean running = true;
    private EglCore egl;

    RenderThread(SurfaceTexture texture, int width, int height) {
      this.texture = texture;
      this.width = width;
      this.height = height;
    }

    @Override public void run() {
      try {
        egl = new EglCore(texture, width, height);
        scene.onSurfaceCreated(null, null);
        scene.onSurfaceChanged(null, width, height);
        while (running) {
          scene.onDrawFrame(null);
          egl.swap();
          if (!running) break;
          try { Thread.sleep(16); } catch (InterruptedException stopped) { break; }
        }
      } catch (RuntimeException failure) {
        Log.e("Farm3D", "render thread", failure);
      } finally {
        if (egl != null) egl.release();
      }
      Log.d("Farm3D", "render stopped");
    }

    void stopRendering() {
      running = false;
      interrupt();
    }
  }

  private static final class EglCore {
    private EGLDisplay display = EGL14.EGL_NO_DISPLAY;
    private EGLContext context = EGL14.EGL_NO_CONTEXT;
    private EGLSurface surface = EGL14.EGL_NO_SURFACE;
    private Surface windowSurface;

    EglCore(SurfaceTexture texture, int width, int height) {
      display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY);
      if (display == EGL14.EGL_NO_DISPLAY) throw new RuntimeException("eglGetDisplay failed");
      int[] version = new int[2];
      if (!EGL14.eglInitialize(display, version, 0, version, 1)) throw new RuntimeException("eglInitialize failed " + EGL14.eglGetError());
      int[] attributes = {
        EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
        EGL14.EGL_SURFACE_TYPE, EGL14.EGL_WINDOW_BIT,
        EGL14.EGL_RED_SIZE, 8, EGL14.EGL_GREEN_SIZE, 8, EGL14.EGL_BLUE_SIZE, 8, EGL14.EGL_ALPHA_SIZE, 8,
        EGL14.EGL_DEPTH_SIZE, 16, EGL14.EGL_NONE
      };
      android.opengl.EGLConfig[] configs = new android.opengl.EGLConfig[1];
      int[] count = new int[1];
      if (!EGL14.eglChooseConfig(display, attributes, 0, configs, 0, 1, count, 0) || count[0] == 0) throw new RuntimeException("eglChooseConfig failed " + EGL14.eglGetError());
      int[] contextAttributes = {EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE};
      context = EGL14.eglCreateContext(display, configs[0], EGL14.EGL_NO_CONTEXT, contextAttributes, 0);
      if (context == EGL14.EGL_NO_CONTEXT) throw new RuntimeException("eglCreateContext failed " + EGL14.eglGetError());
      texture.setDefaultBufferSize(Math.max(1, width), Math.max(1, height));
      windowSurface = new Surface(texture);
      surface = EGL14.eglCreateWindowSurface(display, configs[0], windowSurface, new int[]{EGL14.EGL_NONE}, 0);
      if (surface == EGL14.EGL_NO_SURFACE) throw new RuntimeException("eglCreateWindowSurface failed " + EGL14.eglGetError());
      if (!EGL14.eglMakeCurrent(display, surface, surface, context)) throw new RuntimeException("eglMakeCurrent failed " + EGL14.eglGetError());
      GLES20.glViewport(0, 0, Math.max(1, width), Math.max(1, height));
      Log.d("Farm3D", "EGL ready " + width + "x" + height + " error=" + GLES20.glGetError());
    }

    void swap() { EGL14.eglSwapBuffers(display, surface); }

    void release() {
      if (display != EGL14.EGL_NO_DISPLAY) {
        EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT);
        if (surface != EGL14.EGL_NO_SURFACE) EGL14.eglDestroySurface(display, surface);
        if (context != EGL14.EGL_NO_CONTEXT) EGL14.eglDestroyContext(display, context);
        EGL14.eglReleaseThread();
        EGL14.eglTerminate(display);
      }
      if (windowSurface != null) { windowSurface.release(); windowSurface = null; }
      display = EGL14.EGL_NO_DISPLAY;
      context = EGL14.EGL_NO_CONTEXT;
      surface = EGL14.EGL_NO_SURFACE;
    }
  }

  void setOnPlotTapListener(PlotTapListener value) { listener = value; }

  void setFarm(JSONObject state) {
    PlotData[] data = new PlotData[6];
    for (int i = 0; i < data.length; i++) data[i] = PlotData.empty(i);
    if (state == null) { scene.setPlots(data); return; }
    JSONArray plots = state.optJSONArray("plots");
    JSONArray crops = state.optJSONArray("crops");
    long now = SystemClock.uptimeMillis();
    if (plots == null) { scene.setPlots(data); return; }
    for (int i = 0; i < plots.length(); i++) {
      JSONObject plot = plots.optJSONObject(i);
      if (plot == null) continue;
      int slot = plot.optInt("slot", i);
      if (slot < 0 || slot >= 6) continue;
      String cropId = plot.optString("cropId");
      if (cropId.isEmpty()) { data[slot] = PlotData.empty(slot); continue; }
      int color = 0xfff4a261;
      float grow = 600f;
      if (crops != null) for (int c = 0; c < crops.length(); c++) {
        JSONObject crop = crops.optJSONObject(c);
        if (crop == null || !cropId.equals(crop.optString("id"))) continue;
        try { color = Color.parseColor(crop.optString("color")); } catch (RuntimeException ignored) { }
        grow = Math.max(1f, crop.optInt("grow", 600));
        break;
      }
      data[slot] = new PlotData(slot, cropId, color, grow, plot.optLong("remaining", 0), now,
        plot.optBoolean("watered"), plot.optBoolean("fertilized"), plot.optBoolean("pest"));
    }
    scene.setPlots(data);
    Log.d("Farm3D", "setFarm plots=" + plots.length());
  }

  static float plotX(int slot) { return (slot % 3 - 1) * PLOT_GAP; }
  static float plotZ(int slot) { return slot < 3 ? -PLOT_ROW : PLOT_ROW; }

  @Override public boolean onTouchEvent(MotionEvent e) {
    switch (e.getActionMasked()) {
      case MotionEvent.ACTION_DOWN:
        if (getParent() != null) getParent().requestDisallowInterceptTouchEvent(true);
        downX = lastX = e.getX();
        downY = lastY = e.getY();
        downAt = SystemClock.uptimeMillis();
        dragging = true;
        moved = false;
        break;
      case MotionEvent.ACTION_POINTER_DOWN:
        if (e.getPointerCount() >= 2) {
          moved = true;
          pinchStart = spacing(e);
          pinchDistance = distance;
        }
        break;
      case MotionEvent.ACTION_MOVE:
        if (e.getPointerCount() >= 2) {
          float d = spacing(e);
          if (d > 20f && pinchStart > 20f) distance = clamp(pinchDistance * pinchStart / d, 9f, 23f);
        } else if (dragging) {
          float x = e.getX(), y = e.getY();
          if (Math.abs(x - downX) + Math.abs(y - downY) > touchSlop) moved = true;
          if (moved) {
            yaw += (x - lastX) * 0.006f;
            pitch = clamp(pitch + (y - lastY) * 0.004f, 0.42f, 1.15f);
          }
          lastX = x;
          lastY = y;
        }
        break;
      case MotionEvent.ACTION_POINTER_UP:
        if (e.getPointerCount() == 2) {
          int remain = e.getActionIndex() == 0 ? 1 : 0;
          lastX = e.getX(remain);
          lastY = e.getY(remain);
        }
        break;
      case MotionEvent.ACTION_UP:
        if (!moved && SystemClock.uptimeMillis() - downAt < 500) pick(e.getX(), e.getY());
        dragging = false;
        if (getParent() != null) getParent().requestDisallowInterceptTouchEvent(false);
        break;
      case MotionEvent.ACTION_CANCEL:
        dragging = false;
        if (getParent() != null) getParent().requestDisallowInterceptTouchEvent(false);
        break;
    }
    return true;
  }

  private static float spacing(MotionEvent e) {
    if (e.getPointerCount() < 2) return 0f;
    float dx = e.getX(0) - e.getX(1), dy = e.getY(0) - e.getY(1);
    return (float) Math.sqrt(dx * dx + dy * dy);
  }

  private static float clamp(float value, float min, float max) {
    return Math.max(min, Math.min(max, value));
  }

  private void pick(float x, float y) {
    float[] vp = lastViewProj;
    if (vp == null || getWidth() == 0 || getHeight() == 0) return;
    float[] inv = new float[16];
    if (!Matrix.invertM(inv, 0, vp, 0)) return;
    float nx = x / getWidth() * 2f - 1f;
    float ny = 1f - y / getHeight() * 2f;
    float[] near = new float[4], far = new float[4];
    Matrix.multiplyMV(near, 0, inv, 0, new float[]{nx, ny, -1f, 1f}, 0);
    Matrix.multiplyMV(far, 0, inv, 0, new float[]{nx, ny, 1f, 1f}, 0);
    if (near[3] == 0f || far[3] == 0f) return;
    for (int i = 0; i < 4; i++) { near[i] /= near[3]; far[i] /= far[3]; }
    float dx = far[0] - near[0], dy = far[1] - near[1], dz = far[2] - near[2];
    if (Math.abs(dy) < 0.00001f) return;
    float t = (0.42f - near[1]) / dy;
    if (t < 0f) return;
    float hx = near[0] + dx * t, hz = near[2] + dz * t;
    for (int slot = 0; slot < 6; slot++) {
      if (Math.abs(hx - plotX(slot)) <= PICK_HALF && Math.abs(hz - plotZ(slot)) <= PICK_HALF) {
        selectedSlot = slot;
        if (listener != null) listener.onPlotTap(slot);
        return;
      }
    }
  }

  private static final class PlotData {
    final int slot;
    final String cropId;
    final int color;
    final float growSec;
    final float progressAtFetch;
    final long fetchedAt;
    final boolean watered, fertilized, pest;

    PlotData(int slot, String cropId, int color, float growSec, long remainingMs, long fetchedAt,
             boolean watered, boolean fertilized, boolean pest) {
      this.slot = slot;
      this.cropId = cropId;
      this.color = color;
      this.growSec = growSec;
      this.fetchedAt = fetchedAt;
      this.watered = watered;
      this.fertilized = fertilized;
      this.pest = pest;
      this.progressAtFetch = clamp(1f - remainingMs / (growSec * 1000f), 0f, 1f);
    }

    static PlotData empty(int slot) { return new PlotData(slot, "", 0xff7a5136, 1f, 0L, 0L, false, false, false); }

    boolean isEmpty() { return cropId.isEmpty(); }

    boolean isReady(long now) { return !isEmpty() && progress(now) >= 0.999f; }

    float progress(long now) {
      if (isEmpty()) return 0f;
      if (fetchedAt == 0L) return 1f;
      float progress = progressAtFetch + (now - fetchedAt) / 1000f / Math.max(1f, growSec);
      return clamp(progress, 0f, 1f);
    }
  }

  private static final class Mesh {
    final FloatBuffer positions;
    final FloatBuffer normals;
    final int count;

    Mesh(float[] p, float[] n) {
      positions = buffer(p);
      normals = buffer(n);
      count = p.length / 3;
    }

    static FloatBuffer buffer(float[] data) {
      FloatBuffer b = ByteBuffer.allocateDirect(data.length * 4).order(ByteOrder.nativeOrder()).asFloatBuffer();
      b.put(data).position(0);
      return b;
    }
  }

  private static final class SceneRenderer implements GLSurfaceView.Renderer {
    private static final int GRASS = 0xff6fa95c;
    private static final int GRASS_LIGHT = 0xff7fb96a;
    private static final int GRASS_DARK = 0xff5b8f4d;
    private static final int DIRT_PALE = 0xff8d7653;
    private static final int SOIL = 0xff7a5136;
    private static final int SOIL_WET = 0xff5b3d2b;
    private static final int SOIL_DARK = 0xff4b3122;
    private static final int WOOD = 0xffb07a4a;
    private static final int SAND = 0xffd9c38d;
    private static final int WATER = 0xff4aa9d8;
    private static final int WATER_LIGHT = 0xff74c9eb;
    private static final int TRUNK = 0xff6b4b2e;
    private static final int LEAF = 0xff4f9a4a;
    private static final int LEAF_DARK = 0xff3f833f;
    private static final int LEAF_LIGHT = 0xff66b15b;
    private static final int BARN = 0xffc2563f;
    private static final int BARN_DARK = 0xff763326;
    private static final int ROOF = 0xff6b3d2b;
    private static final int GOLD = 0xffffd166;
    private static final int STEM = 0xff4f9a45;
    private static final int LEAVES = 0xff63b05a;

    private static final String SCENE_VS =
      "uniform mat4 uViewProj;\nuniform mat4 uModel;\n" +
      "attribute vec3 aPos;\nattribute vec3 aNormal;\nvarying vec3 vNormal;\n" +
      "void main(){ gl_Position = uViewProj * uModel * vec4(aPos, 1.0);" +
      " vNormal = normalize(mat3(uModel) * aNormal); }\n";
    private static final String SCENE_FS =
      "precision mediump float;\nuniform vec3 uColor;\nuniform float uAlpha;\nuniform vec3 uLight;\n" +
      "varying vec3 vNormal;\n" +
      "void main(){ float d = max(dot(normalize(vNormal), normalize(uLight)), 0.0);" +
      " gl_FragColor = vec4(uColor * (0.48 + 0.52 * d), uAlpha); }\n";
    private static final String SKY_VS =
      "attribute vec2 aPos;\nvarying float vY;\n" +
      "void main(){ vY = aPos.y * 0.5 + 0.5; gl_Position = vec4(aPos, 0.0, 1.0); }\n";
    private static final String SKY_FS =
      "precision mediump float;\nuniform vec3 uTop;\nuniform vec3 uBottom;\nvarying float vY;\n" +
      "void main(){ gl_FragColor = vec4(mix(uBottom, uTop, smoothstep(0.0, 1.0, vY)), 1.0); }\n";

    private volatile PlotData[] plots = new PlotData[6];
    private int sceneProgram, skyProgram;
    private int aPos, aNormal, uViewProj, uModel, uColor, uAlpha, uLight;
    private int skyPos, skyTop, skyBottom;
    private Mesh cube, sphere, cylinder, cone, disk;
    private FloatBuffer skyBuffer;
    private final float[] proj = new float[16], view = new float[16], vp = new float[16];
    private final float[] model = new float[16], local = new float[16], combined = new float[16], base = new float[16];
    private long startTime;
    private boolean loggedFrame;

    private final Farm3DView host;

    SceneRenderer(Farm3DView host) {
      this.host = host;
      for (int i = 0; i < plots.length; i++) plots[i] = PlotData.empty(i);
    }

    void setPlots(PlotData[] data) { plots = data; }

    @Override public void onSurfaceCreated(GL10 gl, EGLConfig config) {
      GLES20.glClearColor(0.65f, 0.85f, 1f, 1f);
      GLES20.glDisable(GLES20.GL_CULL_FACE);
      sceneProgram = program(SCENE_VS, SCENE_FS);
      aPos = GLES20.glGetAttribLocation(sceneProgram, "aPos");
      aNormal = GLES20.glGetAttribLocation(sceneProgram, "aNormal");
      uViewProj = GLES20.glGetUniformLocation(sceneProgram, "uViewProj");
      uModel = GLES20.glGetUniformLocation(sceneProgram, "uModel");
      uColor = GLES20.glGetUniformLocation(sceneProgram, "uColor");
      uAlpha = GLES20.glGetUniformLocation(sceneProgram, "uAlpha");
      uLight = GLES20.glGetUniformLocation(sceneProgram, "uLight");
      skyProgram = program(SKY_VS, SKY_FS);
      skyPos = GLES20.glGetAttribLocation(skyProgram, "aPos");
      skyTop = GLES20.glGetUniformLocation(skyProgram, "uTop");
      skyBottom = GLES20.glGetUniformLocation(skyProgram, "uBottom");
      skyBuffer = Mesh.buffer(new float[]{-1,-1, 1,-1, 1,1, -1,-1, 1,1, -1,1});
      cube = cubeMesh();
      sphere = sphereMesh();
      cylinder = cylinderMesh();
      cone = coneMesh();
      disk = diskMesh();
      startTime = SystemClock.uptimeMillis();
      Log.d("Farm3D", "surface created programs=" + sceneProgram + "/" + skyProgram + " error=" + GLES20.glGetError());
    }

    @Override public void onSurfaceChanged(GL10 gl, int width, int height) {
      GLES20.glViewport(0, 0, Math.max(1, width), Math.max(1, height));
      Matrix.perspectiveM(proj, 0, 50f, (float) Math.max(1, width) / Math.max(1, height), 0.1f, 110f);
      Log.d("Farm3D", "surface " + width + "x" + height);
    }

    @Override public void onDrawFrame(GL10 gl) {
      long now = SystemClock.uptimeMillis();
      float time = (now - startTime) / 1000f;
      GLES20.glClearColor(0.65f, 0.85f, 1f, 1f);
      GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT | GLES20.GL_DEPTH_BUFFER_BIT);
      float cameraPitch = host.pitch, cameraDistance = host.distance, cameraYaw = host.yaw;
      float horizontal = (float) (Math.cos(cameraPitch) * cameraDistance);
      float cx = (float) (Math.sin(cameraYaw) * horizontal);
      float cz = (float) (Math.cos(cameraYaw) * horizontal);
      float cy = 0.5f + (float) (Math.sin(cameraPitch) * cameraDistance);
      Matrix.setLookAtM(view, 0, cx, cy, cz, 0f, 0.5f, 0f, 0f, 1f, 0f);
      Matrix.multiplyMM(vp, 0, proj, 0, view, 0);
      host.lastViewProj = vp.clone();
      drawSky();
      GLES20.glEnable(GLES20.GL_DEPTH_TEST);
      GLES20.glDepthMask(true);
      GLES20.glClear(GLES20.GL_DEPTH_BUFFER_BIT);
      GLES20.glUseProgram(sceneProgram);
      GLES20.glUniformMatrix4fv(uViewProj, 1, false, vp, 0);
      GLES20.glUniform3f(uLight, 0.35f, 0.9f, 0.5f);
      GLES20.glEnableVertexAttribArray(aPos);
      GLES20.glEnableVertexAttribArray(aNormal);
      drawWorld(now, time);
      GLES20.glEnable(GLES20.GL_BLEND);
      GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE_MINUS_SRC_ALPHA);
      GLES20.glDepthMask(false);
      drawTransparent(now, time);
      GLES20.glDepthMask(true);
      GLES20.glDisable(GLES20.GL_BLEND);
      GLES20.glDisableVertexAttribArray(aPos);
      GLES20.glDisableVertexAttribArray(aNormal);
      if (!loggedFrame) {
        loggedFrame = true;
        Log.d("Farm3D", "first frame error=" + GLES20.glGetError());
      }
    }

    private void drawSky() {
      GLES20.glDisable(GLES20.GL_DEPTH_TEST);
      GLES20.glDepthMask(false);
      GLES20.glUseProgram(skyProgram);
      GLES20.glUniform3f(skyTop, 0.35f, 0.62f, 0.92f);
      GLES20.glUniform3f(skyBottom, 0.86f, 0.95f, 1f);
      GLES20.glEnableVertexAttribArray(skyPos);
      skyBuffer.position(0);
      GLES20.glVertexAttribPointer(skyPos, 2, GLES20.GL_FLOAT, false, 0, skyBuffer);
      GLES20.glDrawArrays(GLES20.GL_TRIANGLES, 0, 6);
      GLES20.glDisableVertexAttribArray(skyPos);
      GLES20.glDepthMask(true);
    }

    private void drawWorld(long now, float time) {
      box(0f, -0.3f, 0f, 32f, 0.6f, 26f, GRASS);
      box(-6.5f, 0.01f, 3.5f, 3.4f, 0.04f, 2.0f, GRASS_LIGHT);
      box(6.5f, 0.01f, 5.0f, 4.0f, 0.04f, 1.8f, GRASS_DARK);
      box(0f, 0.01f, 6.2f, 2.8f, 0.06f, 6.2f, SAND);
      box(0f, 0.035f, 3.3f, 4.4f, 0.03f, 0.9f, SAND);
      diskAt(-8.6f, 0.06f, -2.8f, 4.4f, 3.2f, WATER);
      diskAt(-8.6f, 0.075f, -2.8f, 3.5f, 2.4f, WATER_LIGHT);
      box(0f, 0.02f, 0f, 10.9f, 0.04f, 7.8f, DIRT_PALE);
      drawFence();
      drawBarn();
      tree(-11.8f, -5.2f, 1.15f);
      tree(11.4f, -5.8f, 1.0f);
      tree(-12.4f, 4.6f, 0.9f);
      tree(12.2f, 4.0f, 1.1f);
      for (int slot = 0; slot < 6; slot++) drawPlot(slot, now, time);
      sphere(-7f, 9.5f, -18f, 3.2f, 0.8f, 1.4f, 0xffffffff);
      sphere(-2f, 10.4f, -20f, 2.4f, 0.7f, 1.2f, 0xffffffff);
      sphere(6f, 9.8f, -19f, 3.6f, 0.8f, 1.3f, 0xffffffff);
    }

    private void drawTransparent(long now, float time) {
      for (int slot = 0; slot < 6; slot++) {
        float x = plotX(slot), z = plotZ(slot);
        diskAt(x, 0.028f, z, 3.2f, 3.2f, 0x101010, 0.09f);
        PlotData p = plots[slot];
        if (p != null && p.isReady(now)) {
          float pulse = 0.16f + 0.06f * (float) Math.sin(time * 3.0 + slot);
          diskAt(x, 0.405f, z, 2.55f, 2.55f, GOLD, pulse);
        }
      }
      int selected = host.selectedSlot;
      if (selected >= 0) diskAt(plotX(selected), 0.415f, plotZ(selected), 2.7f, 2.7f, 0xffffe08a, 0.22f);
      diskAt(-11.8f, 0.03f, -5.2f, 3.2f, 3.2f, 0x101010, 0.12f);
      diskAt(11.4f, 0.03f, -5.8f, 2.8f, 2.8f, 0x101010, 0.12f);
      diskAt(-12.4f, 0.03f, 4.6f, 2.6f, 2.6f, 0x101010, 0.1f);
      diskAt(12.2f, 0.03f, 4.0f, 3.0f, 3.0f, 0x101010, 0.1f);
    }

    private void drawPlot(int slot, long now, float time) {
      float x = plotX(slot), z = plotZ(slot);
      PlotData p = plots[slot];
      box(x, 0.16f, z, 2.8f, 0.32f, 2.8f, WOOD);
      box(x, 0.335f, z, 2.45f, 0.1f, 2.45f, p != null && p.watered ? SOIL_WET : SOIL);
      if (p == null || p.isEmpty()) {
        for (int f = -1; f <= 1; f++) box(x, 0.39f, z + f * 0.65f, 1.9f, 0.03f, 0.12f, SOIL_DARK);
        return;
      }
      float progress = p.progress(now);
      drawCrop(p, x, z, progress, time);
      if (p.fertilized) {
        drawPart(cone, base, -0.85f, 0f, -0.85f, 0.2f, 0.38f, 0.2f, 0f, LEAF_LIGHT, 1f);
        drawPart(cone, base, 0.85f, 0f, 0.8f, 0.18f, 0.32f, 0.18f, 0f, LEAF_LIGHT, 1f);
        drawPart(cone, base, 0.7f, 0f, -0.9f, 0.16f, 0.28f, 0.16f, 0f, LEAF_LIGHT, 1f);
      }
      if (p.pest) {
        for (int i = 0; i < 3; i++) {
          float angle = time * 2.6f + i * 2.1f + slot;
          sphere(x + (float) Math.cos(angle) * 0.55f, 0.8f + (float) Math.sin(time * 3f + i) * 0.12f,
            z + (float) Math.sin(angle) * 0.55f, 0.1f, 0.1f, 0.1f, 0xff2d2d2d);
        }
      }
      if (p.isReady(now)) {
        for (int i = 0; i < 3; i++) {
          float angle = time * 2f + i * 2.1f;
          box(x + (float) Math.cos(angle) * 0.65f, 1.25f + (float) Math.sin(time * 3f + i) * 0.14f,
            z + (float) Math.sin(angle) * 0.65f, 0.11f, 0.11f, 0.11f, 0xfff9d65c);
        }
      }
    }

    private void drawCrop(PlotData p, float x, float z, float progress, float time) {
      Matrix.setIdentityM(base, 0);
      Matrix.translateM(base, 0, x, 0.38f, z);
      Matrix.rotateM(base, 0, (float) Math.sin(time * 1.15f + p.slot) * 2.4f, 0f, 1f, 0f);
      float height = 0.5f + progress * 1.5f;
      drawPart(cylinder, base, 0f, 0f, 0f, 0.13f, height, 0.13f, 0f, STEM, 1f);
      drawPart(sphere, base, 0.23f, height * 0.4f, 0.03f, 0.64f, 0.12f, 0.32f, 24f, LEAVES, 1f);
      drawPart(sphere, base, -0.22f, height * 0.55f, -0.02f, 0.58f, 0.1f, 0.3f, -24f, LEAVES, 1f);
      if (progress < 0.16f) return;
      float fruit = 0.24f + progress * 0.34f;
      switch (p.cropId) {
        case "sunflower":
          drawPart(sphere, base, 0f, height + 0.08f, 0f, 0.78f, 0.2f, 0.78f, 0f, 0xffffd54f, 1f);
          drawPart(sphere, base, 0f, height + 0.08f, 0.13f, 0.34f, 0.12f, 0.34f, 0f, 0xff6d4c41, 1f);
          break;
        case "rose":
          drawPart(sphere, base, 0f, height, 0f, fruit * 1.25f, fruit, fruit * 1.25f, 0f, p.color, 1f);
          drawPart(sphere, base, 0.18f, height * 0.92f, 0.08f, fruit * 0.7f, fruit * 0.55f, fruit * 0.7f, 20f, p.color, 1f);
          drawPart(sphere, base, -0.17f, height * 0.96f, -0.05f, fruit * 0.65f, fruit * 0.5f, fruit * 0.65f, -18f, p.color, 1f);
          break;
        case "tomato":
          drawPart(sphere, base, 0.18f, height * 0.63f, 0.08f, fruit, fruit * 0.9f, fruit, 0f, p.color, 1f);
          drawPart(sphere, base, -0.2f, height * 0.72f, -0.07f, fruit * 0.85f, fruit * 0.8f, fruit * 0.85f, 0f, p.color, 1f);
          break;
        case "pumpkin":
          drawPart(sphere, base, 0f, 0.22f + progress * 0.12f, 0f, 0.85f + progress * 0.3f, 0.45f + progress * 0.2f, 0.85f + progress * 0.3f, 0f, p.color, 1f);
          break;
        case "watermelon":
          drawPart(sphere, base, 0.08f, 0.28f, -0.05f, 0.95f + progress * 0.25f, 0.78f + progress * 0.2f, 0.95f + progress * 0.25f, 0f, p.color, 1f);
          break;
        case "grape":
          for (int i = 0; i < 6; i++) {
            float angle = i * 1.05f;
            drawPart(sphere, base, (float) Math.cos(angle) * 0.18f, height * 0.72f + (i % 3) * 0.13f,
              (float) Math.sin(angle) * 0.18f, fruit * 0.62f, fruit * 0.62f, fruit * 0.62f, 0f, p.color, 1f);
          }
          break;
        case "crystal":
          drawPart(sphere, base, 0f, height * 0.72f, 0f, fruit * 0.75f, fruit * 1.8f, fruit * 0.75f, 45f, p.color, 1f);
          drawPart(sphere, base, 0.22f, height * 0.5f, 0.12f, fruit * 0.4f, fruit * 0.9f, fruit * 0.4f, -35f, p.color, 1f);
          break;
        case "strawberry":
          drawPart(sphere, base, 0f, height * 0.58f, 0f, fruit * 0.9f, fruit * 1.1f, fruit * 0.9f, 0f, p.color, 1f);
          drawPart(sphere, base, 0f, height * 0.72f, 0f, fruit * 0.75f, 0.08f, fruit * 0.75f, 0f, LEAVES, 1f);
          break;
        default:
          drawPart(sphere, base, 0f, height * 0.7f, 0f, fruit, fruit, fruit, 0f, p.color, 1f);
      }
    }

    private void drawFence() {
      for (int i = -3; i <= 3; i++) {
        float x = i * 3f;
        box(x, 0.5f, -8.3f, 0.2f, 1f, 0.2f, WOOD);
        if (i < 3) {
          box(x + 1.5f, 0.6f, -8.3f, 2.9f, 0.12f, 0.1f, WOOD);
          box(x + 1.5f, 0.9f, -8.3f, 2.9f, 0.12f, 0.1f, WOOD);
        }
      }
      for (int i = 0; i < 4; i++) {
        float z = -7.5f + i * 3.2f;
        box(-9.6f, 0.5f, z, 0.2f, 1f, 0.2f, WOOD);
        box(9.6f, 0.5f, z, 0.2f, 1f, 0.2f, WOOD);
        if (i < 3) {
          box(-9.6f, 0.7f, z + 1.6f, 0.1f, 0.12f, 3.1f, WOOD);
          box(9.6f, 0.7f, z + 1.6f, 0.1f, 0.12f, 3.1f, WOOD);
        }
      }
    }

    private void drawBarn() {
      box(7.4f, 1.2f, -6.6f, 3.6f, 2.4f, 3f, BARN);
      Matrix.setIdentityM(base, 0);
      Matrix.translateM(base, 0, 7.4f, 2.4f, -6.6f);
      Matrix.scaleM(base, 0, 4.3f, 1.5f, 3.6f);
      drawMesh(cone, base, ROOF, 1f);
      box(7.4f, 0.8f, -5.03f, 1.1f, 1.6f, 0.12f, BARN_DARK);
      box(6.35f, 1.75f, -5.02f, 0.6f, 0.6f, 0.1f, 0xfff2d27a);
      box(8.45f, 1.75f, -5.02f, 0.6f, 0.6f, 0.1f, 0xfff2d27a);
    }

    private void tree(float x, float z, float scale) {
      Matrix.setIdentityM(model, 0);
      Matrix.translateM(model, 0, x, 0f, z);
      Matrix.scaleM(model, 0, 0.34f * scale, 1.4f * scale, 0.34f * scale);
      drawMesh(cylinder, model, TRUNK, 1f);
      sphere(x, 1.55f * scale, z, 1.75f * scale, 1.3f * scale, 1.75f * scale, LEAF_DARK);
      sphere(x + 0.4f * scale, 2.1f * scale, z + 0.1f * scale, 1.3f * scale, 1.05f * scale, 1.3f * scale, LEAF);
      sphere(x - 0.45f * scale, 1.95f * scale, z - 0.15f * scale, 1.05f * scale, 0.9f * scale, 1.05f * scale, LEAF_LIGHT);
    }

    private void box(float x, float y, float z, float sx, float sy, float sz, int color) {
      Matrix.setIdentityM(model, 0);
      Matrix.translateM(model, 0, x, y, z);
      Matrix.scaleM(model, 0, sx, sy, sz);
      drawMesh(cube, model, color, 1f);
    }

    private void sphere(float x, float y, float z, float sx, float sy, float sz, int color) {
      Matrix.setIdentityM(model, 0);
      Matrix.translateM(model, 0, x, y, z);
      Matrix.scaleM(model, 0, sx, sy, sz);
      drawMesh(sphere, model, color, 1f);
    }

    private void diskAt(float x, float y, float z, float sx, float sz, int color) { diskAt(x, y, z, sx, sz, color, 1f); }

    private void diskAt(float x, float y, float z, float sx, float sz, int color, float alpha) {
      Matrix.setIdentityM(model, 0);
      Matrix.translateM(model, 0, x, y, z);
      Matrix.scaleM(model, 0, sx, 1f, sz);
      drawMesh(disk, model, color, alpha);
    }

    private void drawPart(Mesh mesh, float[] parent, float x, float y, float z, float sx, float sy, float sz,
                          float rotateZ, int color, float alpha) {
      Matrix.setIdentityM(local, 0);
      Matrix.translateM(local, 0, x, y, z);
      if (rotateZ != 0f) Matrix.rotateM(local, 0, rotateZ, 0f, 0f, 1f);
      Matrix.scaleM(local, 0, sx, sy, sz);
      Matrix.multiplyMM(combined, 0, parent, 0, local, 0);
      drawMesh(mesh, combined, color, alpha);
    }

    private void drawMesh(Mesh mesh, float[] matrix, int color, float alpha) {
      if (mesh == null) return;
      GLES20.glUniformMatrix4fv(uModel, 1, false, matrix, 0);
      GLES20.glUniform3f(uColor, ((color >> 16) & 0xff) / 255f, ((color >> 8) & 0xff) / 255f, (color & 0xff) / 255f);
      GLES20.glUniform1f(uAlpha, alpha);
      mesh.positions.position(0);
      mesh.normals.position(0);
      GLES20.glVertexAttribPointer(aPos, 3, GLES20.GL_FLOAT, false, 0, mesh.positions);
      GLES20.glVertexAttribPointer(aNormal, 3, GLES20.GL_FLOAT, false, 0, mesh.normals);
      GLES20.glDrawArrays(GLES20.GL_TRIANGLES, 0, mesh.count);
    }

    private static int program(String vertexSource, String fragmentSource) {
      int vs = shader(GLES20.GL_VERTEX_SHADER, vertexSource);
      int fs = shader(GLES20.GL_FRAGMENT_SHADER, fragmentSource);
      int p = GLES20.glCreateProgram();
      GLES20.glAttachShader(p, vs);
      GLES20.glAttachShader(p, fs);
      GLES20.glLinkProgram(p);
      int[] status = new int[1];
      GLES20.glGetProgramiv(p, GLES20.GL_LINK_STATUS, status, 0);
      if (status[0] == 0) Log.e("Farm3D", "Program link: " + GLES20.glGetProgramInfoLog(p));
      GLES20.glDeleteShader(vs);
      GLES20.glDeleteShader(fs);
      return p;
    }

    private static int shader(int type, String source) {
      int shader = GLES20.glCreateShader(type);
      GLES20.glShaderSource(shader, source);
      GLES20.glCompileShader(shader);
      int[] status = new int[1];
      GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, status, 0);
      if (status[0] == 0) Log.e("Farm3D", "Shader: " + GLES20.glGetShaderInfoLog(shader));
      return shader;
    }

    private static Mesh cubeMesh() {
      float[] p = {
        -.5f,-.5f,.5f, .5f,-.5f,.5f, .5f,.5f,.5f, -.5f,-.5f,.5f, .5f,.5f,.5f, -.5f,.5f,.5f,
        .5f,-.5f,-.5f, -.5f,-.5f,-.5f, -.5f,.5f,-.5f, .5f,-.5f,-.5f, -.5f,.5f,-.5f, .5f,.5f,-.5f,
        .5f,-.5f,.5f, .5f,-.5f,-.5f, .5f,.5f,-.5f, .5f,-.5f,.5f, .5f,.5f,-.5f, .5f,.5f,.5f,
        -.5f,-.5f,-.5f, -.5f,-.5f,.5f, -.5f,.5f,.5f, -.5f,-.5f,-.5f, -.5f,.5f,.5f, -.5f,.5f,-.5f,
        -.5f,.5f,.5f, .5f,.5f,.5f, .5f,.5f,-.5f, -.5f,.5f,.5f, .5f,.5f,-.5f, -.5f,.5f,-.5f,
        -.5f,-.5f,-.5f, .5f,-.5f,-.5f, .5f,-.5f,.5f, -.5f,-.5f,-.5f, .5f,-.5f,.5f, -.5f,-.5f,.5f
      };
      float[] n = new float[36 * 3];
      float[][] normals = {{0,0,1},{0,0,-1},{1,0,0},{-1,0,0},{0,1,0},{0,-1,0}};
      for (int face = 0; face < 6; face++) for (int v = 0; v < 6; v++) {
        int i = (face * 6 + v) * 3;
        n[i] = normals[face][0];
        n[i + 1] = normals[face][1];
        n[i + 2] = normals[face][2];
      }
      return new Mesh(p, n);
    }

    private static Mesh sphereMesh() {
      int stacks = 7, slices = 12;
      float[] p = new float[stacks * slices * 6 * 3];
      float[] n = new float[p.length];
      int k = 0;
      for (int i = 0; i < stacks; i++) {
        double a0 = -Math.PI / 2 + Math.PI * i / (double) stacks;
        double a1 = -Math.PI / 2 + Math.PI * (i + 1) / (double) stacks;
        for (int j = 0; j < slices; j++) {
          double b0 = 2 * Math.PI * j / (double) slices;
          double b1 = 2 * Math.PI * (j + 1) / (double) slices;
          float[] v = {
            sx(a0, b0), sy(a0), sz(a0, b0), sx(a0, b1), sy(a0), sz(a0, b1), sx(a1, b1), sy(a1), sz(a1, b1),
            sx(a0, b0), sy(a0), sz(a0, b0), sx(a1, b1), sy(a1), sz(a1, b1), sx(a1, b0), sy(a1), sz(a1, b0)
          };
          for (int q = 0; q < v.length; q += 3) {
            p[k] = v[q]; n[k] = v[q];
            p[k + 1] = v[q + 1]; n[k + 1] = v[q + 1];
            p[k + 2] = v[q + 2]; n[k + 2] = v[q + 2];
            k += 3;
          }
        }
      }
      return new Mesh(p, n);
    }

    private static float sx(double lat, double lon) { return (float) (Math.cos(lat) * Math.cos(lon) * 0.5); }
    private static float sz(double lat, double lon) { return (float) (Math.cos(lat) * Math.sin(lon) * 0.5); }
    private static float sy(double lat) { return (float) (Math.sin(lat) * 0.5); }

    private static Mesh cylinderMesh() {
      int slices = 12;
      float[] p = new float[slices * 6 * 3 * 2 + slices * 3 * 3 * 2];
      float[] n = new float[p.length];
      int k = 0;
      for (int j = 0; j < slices; j++) {
        double a0 = 2 * Math.PI * j / slices, a1 = 2 * Math.PI * (j + 1) / slices;
        float x0 = (float) Math.cos(a0) * 0.5f, z0 = (float) Math.sin(a0) * 0.5f;
        float x1 = (float) Math.cos(a1) * 0.5f, z1 = (float) Math.sin(a1) * 0.5f;
        float nx0 = (float) Math.cos(a0), nz0 = (float) Math.sin(a0), nx1 = (float) Math.cos(a1), nz1 = (float) Math.sin(a1);
        k = vertex(p, n, k, x0, 0, z0, nx0, 0, nz0);
        k = vertex(p, n, k, x1, 0, z1, nx1, 0, nz1);
        k = vertex(p, n, k, x1, 1, z1, nx1, 0, nz1);
        k = vertex(p, n, k, x0, 0, z0, nx0, 0, nz0);
        k = vertex(p, n, k, x1, 1, z1, nx1, 0, nz1);
        k = vertex(p, n, k, x0, 1, z0, nx0, 0, nz0);
        k = vertex(p, n, k, 0, 1, 0, 0, 1, 0);
        k = vertex(p, n, k, x0, 1, z0, 0, 1, 0);
        k = vertex(p, n, k, x1, 1, z1, 0, 1, 0);
        k = vertex(p, n, k, 0, 0, 0, 0, -1, 0);
        k = vertex(p, n, k, x1, 0, z1, 0, -1, 0);
        k = vertex(p, n, k, x0, 0, z0, 0, -1, 0);
      }
      return new Mesh(Arrays.copyOf(p, k), Arrays.copyOf(n, k));
    }

    private static Mesh coneMesh() {
      int slices = 12;
      float[] p = new float[slices * 6 * 3];
      float[] n = new float[p.length];
      int k = 0;
      for (int j = 0; j < slices; j++) {
        double a0 = 2 * Math.PI * j / slices, a1 = 2 * Math.PI * (j + 1) / slices;
        float x0 = (float) Math.cos(a0) * 0.5f, z0 = (float) Math.sin(a0) * 0.5f;
        float x1 = (float) Math.cos(a1) * 0.5f, z1 = (float) Math.sin(a1) * 0.5f;
        k = vertex(p, n, k, 0, 1, 0, 0.5f, 0.5f, 0f);
        k = vertex(p, n, k, x0, 0, z0, 0.5f, 0.5f, 0f);
        k = vertex(p, n, k, x1, 0, z1, 0.5f, 0.5f, 0f);
        k = vertex(p, n, k, 0, 0, 0, 0, -1, 0);
        k = vertex(p, n, k, x1, 0, z1, 0, -1, 0);
        k = vertex(p, n, k, x0, 0, z0, 0, -1, 0);
      }
      return new Mesh(p, n);
    }

    private static Mesh diskMesh() {
      int slices = 28;
      float[] p = new float[slices * 3 * 3];
      float[] n = new float[p.length];
      int k = 0;
      for (int j = 0; j < slices; j++) {
        double a0 = 2 * Math.PI * j / slices, a1 = 2 * Math.PI * (j + 1) / slices;
        k = vertex(p, n, k, 0, 0, 0, 0, 1, 0);
        k = vertex(p, n, k, (float) Math.cos(a0) * 0.5f, 0, (float) Math.sin(a0) * 0.5f, 0, 1, 0);
        k = vertex(p, n, k, (float) Math.cos(a1) * 0.5f, 0, (float) Math.sin(a1) * 0.5f, 0, 1, 0);
      }
      return new Mesh(p, n);
    }

    private static int vertex(float[] p, float[] n, int k, float x, float y, float z, float nx, float ny, float nz) {
      p[k] = x; p[k + 1] = y; p[k + 2] = z;
      n[k] = nx; n[k + 1] = ny; n[k + 2] = nz;
      return k + 3;
    }
  }

}
