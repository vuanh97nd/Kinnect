package app.kinnect.live;

import android.content.Context;
import android.content.Intent;
import android.media.AudioFormat;
import android.os.*;
import android.speech.*;
import java.io.*;
import java.util.*;

/**
 * Captions made entirely on the phone: speech segments are found with a simple energy detector,
 * then each segment is fed to Android's on-device recognizer (Android 13+). No audio leaves the device.
 */
final class AutoCaptions {
  static final int RATE = 16000;

  interface Listener { void progress(int done, int total); void finished(List<float[]> times, List<String> lines, String error); }

  static boolean supported(Context c) {
    return Build.VERSION.SDK_INT >= 33 && SpeechRecognizer.isOnDeviceRecognitionAvailable(c);
  }

  /** Speech regions as {startSample, endSample}, split so no caption runs longer than about 6 s. */
  static List<int[]> segments(short[] pcm) {
    int frame = RATE / 50, frames = pcm.length / frame; List<int[]> out = new ArrayList<>();
    if (frames == 0) return out;
    float[] energy = new float[frames];
    for (int f = 0; f < frames; f++) { double sum = 0; for (int i = f * frame; i < (f + 1) * frame; i++) sum += pcm[i] * (double) pcm[i]; energy[f] = (float) Math.sqrt(sum / frame); }
    float[] sorted = energy.clone(); Arrays.sort(sorted);
    float floor = sorted[frames / 5], threshold = Math.max(350, floor * 2.8f);
    int start = -1, quiet = 0;
    for (int f = 0; f <= frames; f++) {
      boolean loud = f < frames && energy[f] > threshold;
      if (loud) { if (start < 0) start = f; quiet = 0; }
      else if (start >= 0 && (++quiet > 18 || f == frames)) { add(out, start, f - quiet + 1, frame); start = -1; quiet = 0; }
      if (start >= 0 && f - start >= 300) {
        // Cut long speech at the quietest frame of its last second.
        int cut = f; float min = Float.MAX_VALUE; for (int k = f - 50; k < f; k++) if (energy[k] < min) { min = energy[k]; cut = k; }
        add(out, start, cut, frame); start = cut;
      }
    }
    return out;
  }

  private static void add(List<int[]> out, int from, int to, int frame) {
    if (to - from < 15) return;  // under 0.3 s: a click, not speech
    out.add(new int[] { Math.max(0, from - 8) * frame, (to + 10) * frame });
  }

  private final Handler main = new Handler(Looper.getMainLooper());
  private SpeechRecognizer recognizer; private boolean cancelled;

  void cancel() { cancelled = true; main.removeCallbacksAndMessages(null); if (recognizer != null) { recognizer.cancel(); recognizer.destroy(); recognizer = null; } }

  /** Must be called on the main thread. */
  void run(Context context, short[] pcm, String language, Listener listener) {
    final List<int[]> parts = segments(pcm);
    final List<float[]> times = new ArrayList<>(); final List<String> lines = new ArrayList<>();
    if (parts.isEmpty()) { listener.finished(times, lines, "Không tìm thấy giọng nói trong video."); return; }
    recognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(context);
    final int[] index = { 0 };
    final Runnable[] next = new Runnable[1];
    next[0] = () -> {
      if (cancelled) return;
      if (index[0] >= parts.size()) { finish(listener, times, lines, null); return; }
      listener.progress(index[0], parts.size());
      final int[] part = parts.get(index[0]);
      final boolean[] answered = { false };
      final Intent intent = new Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
        .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
        .putExtra(RecognizerIntent.EXTRA_LANGUAGE, language)
        .putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
        .putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, 1)
        .putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
        .putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, RATE);
      ParcelFileDescriptor[] pipe;
      try { pipe = ParcelFileDescriptor.createPipe(); } catch (IOException e) { finish(listener, times, lines, "Không mở được luồng âm thanh."); return; }
      intent.putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, pipe[0]);
      final ParcelFileDescriptor writeEnd = pipe[1];
      new Thread(() -> {
        try (OutputStream out = new ParcelFileDescriptor.AutoCloseOutputStream(writeEnd)) {
          int to = Math.min(pcm.length, part[1]); byte[] buffer = new byte[4096]; int fill = 0;
          for (int i = part[0]; i < to + RATE; i++) {  // one extra second of silence ends the utterance
            short v = i < to ? pcm[i] : 0; buffer[fill++] = (byte) v; buffer[fill++] = (byte) (v >> 8);
            if (fill == buffer.length) { out.write(buffer); fill = 0; }
          }
          if (fill > 0) out.write(buffer, 0, fill);
        } catch (IOException ignored) {}
      }, "kinnect-captions").start();
      final Runnable advance = () -> { if (answered[0]) return; answered[0] = true; try { pipe[0].close(); } catch (IOException ignored) {} index[0]++; main.post(next[0]); };
      main.postDelayed(() -> { if (!answered[0] && recognizer != null) recognizer.cancel(); advance.run(); }, 25000);
      recognizer.setRecognitionListener(new RecognitionListener() {
        public void onReadyForSpeech(Bundle b) {} public void onBeginningOfSpeech() {} public void onRmsChanged(float v) {}
        public void onBufferReceived(byte[] b) {} public void onEndOfSpeech() {} public void onPartialResults(Bundle b) {} public void onEvent(int t, Bundle b) {}
        public void onResults(Bundle b) {
          ArrayList<String> found = b.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);
          if (found != null && !found.isEmpty() && !found.get(0).trim().isEmpty()) place(found.get(0).trim(), part[0] / (float) RATE, part[1] / (float) RATE, times, lines);
          advance.run();
        }
        public void onError(int error) {
          if (answered[0]) return;
          if (error == SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE || error == SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED) {
            answered[0] = true;
            try { recognizer.triggerModelDownload(intent); } catch (Exception ignored) {}
            finish(listener, times, lines, "Máy chưa có gói nhận dạng giọng nói ngoại tuyến cho ngôn ngữ này. Android đang tải gói (cần Wi-Fi); hãy thử lại sau vài phút.");
            return;
          }
          if (error == SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS || error == SpeechRecognizer.ERROR_RECOGNIZER_BUSY && index[0] == 0) {
            answered[0] = true; finish(listener, times, lines, "Bộ nhận dạng giọng nói trên máy đang bận hoặc chưa được cấp quyền."); return;
          }
          advance.run();  // no speech in this part: move on
        }
      });
      recognizer.startListening(intent);
    };
    next[0].run();
  }

  private void finish(Listener listener, List<float[]> times, List<String> lines, String error) {
    if (recognizer != null) { recognizer.destroy(); recognizer = null; }
    if (!cancelled) listener.finished(times, lines, error != null ? error : lines.isEmpty() ? "Không nhận ra lời nói nào. Hãy thử video có giọng nói rõ hơn." : null);
  }

  /** Splits a recognised sentence into short caption lines spread over the segment by word count. */
  static void place(String text, float start, float end, List<float[]> times, List<String> lines) {
    String[] words = text.split("\\s+"); int per = 7, chunks = (words.length + per - 1) / per; float span = Math.max(.4f, end - start);
    int done = 0;
    for (int c = 0; c < chunks; c++) {
      int from = c * per, to = Math.min(words.length, from + per);
      StringBuilder line = new StringBuilder(); for (int i = from; i < to; i++) { if (line.length() > 0) line.append(' '); line.append(words[i]); }
      float a = start + span * done / words.length; done = to; float b = start + span * done / words.length;
      times.add(new float[] { a, b }); lines.add(line.toString());
    }
  }
}
