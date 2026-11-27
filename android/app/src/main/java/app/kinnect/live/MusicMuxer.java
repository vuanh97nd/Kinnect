package app.kinnect.live;

import android.content.Context;
import android.media.*;
import android.net.Uri;
import java.io.File;
import java.nio.ByteBuffer;
import java.util.*;

/** Ghép nhạc nền vào video vừa quay: giữ nguyên hình, chuyển nhạc (MP3/M4A…) sang AAC và cắt theo độ dài video. */
final class MusicMuxer {
  private MusicMuxer() {}

  static void mux(Context context, File video, String url, Uri local, String cookie, File out) throws Exception {
    MediaExtractor v = new MediaExtractor();
    MediaExtractor a = new MediaExtractor();
    MediaMuxer muxer = null;
    MediaCodec decoder = null, encoder = null;
    boolean started = false;
    try {
      v.setDataSource(video.getAbsolutePath());
      int vTrack = track(v, "video/");
      if (vTrack < 0) throw new Exception("no video");
      v.selectTrack(vTrack);
      MediaFormat vFormat = v.getTrackFormat(vTrack);
      long duration = vFormat.containsKey(MediaFormat.KEY_DURATION) ? vFormat.getLong(MediaFormat.KEY_DURATION) : 60_000_000L;

      if (url != null) {
        Map<String, String> headers = new HashMap<>();
        headers.put("Cookie", cookie);
        a.setDataSource(url, headers);
      } else a.setDataSource(context, local, null);
      int aTrack = track(a, "audio/");
      if (aTrack < 0) throw new Exception("no audio");
      a.selectTrack(aTrack);
      MediaFormat aFormat = a.getTrackFormat(aTrack);

      muxer = new MediaMuxer(out.getAbsolutePath(), MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4);
      if (vFormat.containsKey(MediaFormat.KEY_ROTATION)) {
        try { muxer.setOrientationHint(vFormat.getInteger(MediaFormat.KEY_ROTATION)); } catch (Exception ignored) {}
      }
      int outVideo = muxer.addTrack(vFormat);

      String aMime = aFormat.getString(MediaFormat.KEY_MIME);
      if (aMime == null) throw new Exception("no audio mime");
      decoder = MediaCodec.createDecoderByType(aMime);
      decoder.configure(aFormat, null, null, 0);
      decoder.start();
      int rate = aFormat.containsKey(MediaFormat.KEY_SAMPLE_RATE) ? aFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE) : 44100;
      int srcChannels = aFormat.containsKey(MediaFormat.KEY_CHANNEL_COUNT) ? Math.max(1, aFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)) : 1;
      int channels = Math.min(2, srcChannels);
      boolean floating = aFormat.containsKey(MediaFormat.KEY_PCM_ENCODING)
          && aFormat.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT;

      // Chuyển mã âm thanh; cấu hình encoder sau khi decoder báo định dạng thực tế.
      MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
      List<byte[]> pendingData = new ArrayList<>();
      List<MediaCodec.BufferInfo> pendingInfo = new ArrayList<>();
      int outAudio = -1;
      boolean inputDone = false, decodeDone = false, encodeDone = false, eosSent = false;
      ArrayDeque<byte[]> pcm = new ArrayDeque<>();
      ArrayDeque<Long> pcmTime = new ArrayDeque<>();
      long lastProgress = android.os.SystemClock.elapsedRealtime();
      while (!encodeDone) {
        if (Thread.currentThread().isInterrupted()) {
          throw new java.io.InterruptedIOException("mux interrupted");
        }
        if (!inputDone) {
          int i = decoder.dequeueInputBuffer(5000);
          if (i >= 0) {
            lastProgress = android.os.SystemClock.elapsedRealtime();
            ByteBuffer buf = decoder.getInputBuffer(i);
            if (buf == null) {
              decoder.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
              inputDone = true;
            } else {
              buf.clear();
              int size;
              try {
                size = a.readSampleData(buf, 0);
              } catch (IllegalArgumentException tooLarge) {
                a.advance();
                decoder.queueInputBuffer(i, 0, 0, 0, 0);
                size = -2;
              }
              if (size != -2) {
                long t = a.getSampleTime();
                if (size < 0 || t < 0 || t > duration) {
                  decoder.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                  inputDone = true;
                } else {
                  decoder.queueInputBuffer(i, 0, size, t, 0);
                  a.advance();
                }
              }
            }
          }
        }
        if (!decodeDone) {
          int o = decoder.dequeueOutputBuffer(info, 5000);
          if (o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
            lastProgress = android.os.SystemClock.elapsedRealtime();
            MediaFormat outFmt = decoder.getOutputFormat();
            if (outFmt != null) {
              if (outFmt.containsKey(MediaFormat.KEY_SAMPLE_RATE)) {
                int r = outFmt.getInteger(MediaFormat.KEY_SAMPLE_RATE);
                if (r > 0) rate = r;
              }
              if (outFmt.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
                srcChannels = Math.max(1, outFmt.getInteger(MediaFormat.KEY_CHANNEL_COUNT));
              }
              if (outFmt.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
                floating = outFmt.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT;
              }
            }
            if (encoder == null) {
              channels = Math.min(2, srcChannels);
              encoder = createAacEncoder(rate, channels);
            }
          } else if (o >= 0) {
            lastProgress = android.os.SystemClock.elapsedRealtime();
            if (info.size > 0 && info.presentationTimeUs <= duration) {
              if (encoder == null) {
                MediaFormat outFmt = decoder.getOutputFormat();
                if (outFmt != null) {
                  if (outFmt.containsKey(MediaFormat.KEY_SAMPLE_RATE)) {
                    int r = outFmt.getInteger(MediaFormat.KEY_SAMPLE_RATE);
                    if (r > 0) rate = r;
                  }
                  if (outFmt.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
                    srcChannels = Math.max(1, outFmt.getInteger(MediaFormat.KEY_CHANNEL_COUNT));
                  }
                  if (outFmt.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
                    floating = outFmt.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT;
                  }
                }
                channels = Math.min(2, srcChannels);
                encoder = createAacEncoder(rate, channels);
              }
              ByteBuffer buf = decoder.getOutputBuffer(o);
              if (buf != null) {
                byte[] chunk = new byte[info.size];
                buf.position(info.offset);
                buf.get(chunk);
                if (floating) {
                  int sampleCount = chunk.length / 4;
                  ByteBuffer fb = ByteBuffer.wrap(chunk).order(java.nio.ByteOrder.LITTLE_ENDIAN);
                  byte[] pcm16 = new byte[sampleCount * 2];
                  for (int s = 0; s < sampleCount; s++) {
                    float vf = fb.getFloat(s * 4);
                    if (Float.isNaN(vf)) vf = 0f;
                    else if (vf > 1f) vf = 1f;
                    else if (vf < -1f) vf = -1f;
                    int sample = Math.round(vf * 32767f);
                    pcm16[s * 2] = (byte) (sample & 0xff);
                    pcm16[s * 2 + 1] = (byte) ((sample >> 8) & 0xff);
                  }
                  chunk = pcm16;
                }
                if (channels == 1 && srcChannels >= 2) {
                  int frameBytes = srcChannels * 2;
                  int frames = chunk.length / frameBytes;
                  byte[] mono = new byte[frames * 2];
                  for (int f = 0; f < frames; f++) {
                    int base = f * frameBytes;
                    int l = (short) ((chunk[base] & 0xff) | (chunk[base + 1] << 8));
                    int r = (short) ((chunk[base + 2] & 0xff) | (chunk[base + 3] << 8));
                    int avg = (l + r) >> 1;
                    mono[f * 2] = (byte) (avg & 0xff);
                    mono[f * 2 + 1] = (byte) ((avg >> 8) & 0xff);
                  }
                  chunk = mono;
                } else if (srcChannels > 2 && channels == 2) {
                  int frameBytes = srcChannels * 2;
                  int frames = chunk.length / frameBytes;
                  byte[] stereo = new byte[frames * 4];
                  for (int f = 0; f < frames; f++) {
                    int base = f * frameBytes;
                    int outBase = f * 4;
                    stereo[outBase] = chunk[base];
                    stereo[outBase + 1] = chunk[base + 1];
                    stereo[outBase + 2] = chunk[base + 2];
                    stereo[outBase + 3] = chunk[base + 3];
                  }
                  chunk = stereo;
                } else if (channels == 2 && srcChannels == 1) {
                  int frames = chunk.length / 2;
                  byte[] stereo = new byte[frames * 4];
                  for (int f = 0; f < frames; f++) {
                    byte lo = chunk[f * 2], hi = chunk[f * 2 + 1];
                    int outBase = f * 4;
                    stereo[outBase] = lo;
                    stereo[outBase + 1] = hi;
                    stereo[outBase + 2] = lo;
                    stereo[outBase + 3] = hi;
                  }
                  chunk = stereo;
                }
                pcm.add(chunk);
                pcmTime.add(info.presentationTimeUs);
              }
            }
            if ((info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) decodeDone = true;
            decoder.releaseOutputBuffer(o, false);
          }
        }
        if (encoder == null) {
          if (decodeDone) throw new Exception("no decoded audio");
          if (android.os.SystemClock.elapsedRealtime() - lastProgress > 15000L) {
            throw new java.io.IOException("audio mux timeout");
          }
          continue;
        }
        // Đưa PCM vào encoder
        while (!pcm.isEmpty()) {
          int i = encoder.dequeueInputBuffer(0);
          if (i < 0) break;
          lastProgress = android.os.SystemClock.elapsedRealtime();
          ByteBuffer buf = encoder.getInputBuffer(i);
          if (buf == null) break;
          byte[] chunk = pcm.peek();
          int n = Math.min(chunk.length, buf.remaining());
          buf.put(chunk, 0, n);
          long t = pcmTime.peek();
          encoder.queueInputBuffer(i, 0, n, t, 0);
          if (n == chunk.length) { pcm.poll(); pcmTime.poll(); }
          else {
            pcm.poll();
            pcm.addFirst(Arrays.copyOfRange(chunk, n, chunk.length));
            pcmTime.poll();
            pcmTime.addFirst(t + (long) (n / (2.0 * channels) * 1_000_000 / rate));
          }
        }
        if (decodeDone && pcm.isEmpty() && !eosSent) {
          int i = encoder.dequeueInputBuffer(0);
          if (i >= 0) {
            lastProgress = android.os.SystemClock.elapsedRealtime();
            encoder.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
            eosSent = true;
          }
        }
        int e = encoder.dequeueOutputBuffer(info, 5000);
        if (e == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
          lastProgress = android.os.SystemClock.elapsedRealtime();
          outAudio = muxer.addTrack(encoder.getOutputFormat());
          muxer.start();
          started = true;
          for (int k = 0; k < pendingData.size(); k++) muxer.writeSampleData(outAudio, ByteBuffer.wrap(pendingData.get(k)), pendingInfo.get(k));
          pendingData.clear();
          pendingInfo.clear();
        } else if (e >= 0) {
          lastProgress = android.os.SystemClock.elapsedRealtime();
          ByteBuffer buf = encoder.getOutputBuffer(e);
          if (buf != null && (info.flags & MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0 && info.size > 0) {
            MediaCodec.BufferInfo copy = new MediaCodec.BufferInfo();
            copy.set(0, info.size, info.presentationTimeUs, info.flags);
            byte[] bytes = new byte[info.size];
            buf.position(info.offset);
            buf.get(bytes);
            if (started) muxer.writeSampleData(outAudio, ByteBuffer.wrap(bytes), copy);
            else { pendingData.add(bytes); pendingInfo.add(copy); }
          }
          if ((info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) encodeDone = true;
          encoder.releaseOutputBuffer(e, false);
        }
        if (android.os.SystemClock.elapsedRealtime() - lastProgress > 15000L) {
          throw new java.io.IOException("audio mux timeout");
        }
      }
      if (!started) throw new Exception("encoder never started");

      // Chép nguyên luồng hình
      int initCap = 4 * 1024 * 1024;
      if (vFormat.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
        initCap = Math.max(initCap, vFormat.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE));
      }
      ByteBuffer frame = ByteBuffer.allocate(initCap);
      MediaCodec.BufferInfo vi = new MediaCodec.BufferInfo();
      while (true) {
        if (Thread.currentThread().isInterrupted()) {
          throw new java.io.InterruptedIOException("mux interrupted");
        }
        if (android.os.Build.VERSION.SDK_INT >= 28) {
          long sampleSize = v.getSampleSize();
          if (sampleSize > frame.capacity() && sampleSize <= 64L * 1024 * 1024) {
            frame = ByteBuffer.allocate((int) sampleSize);
          }
        }
        frame.clear();
        int size;
        while (true) {
          try {
            size = v.readSampleData(frame, 0);
            break;
          } catch (IllegalArgumentException tooSmall) {
            if (frame.capacity() >= 32 * 1024 * 1024) throw tooSmall;
            frame = ByteBuffer.allocate(frame.capacity() * 2);
          }
        }
        if (size < 0) break;
        long vt = v.getSampleTime();
        if (vt < 0) {
          v.advance();
          continue;
        }
        vi.set(0, size, vt, (v.getSampleFlags() & MediaExtractor.SAMPLE_FLAG_SYNC) != 0 ? MediaCodec.BUFFER_FLAG_KEY_FRAME : 0);
        muxer.writeSampleData(outVideo, frame, vi);
        v.advance();
      }
    } finally {
      try { if (decoder != null) { decoder.stop(); decoder.release(); } } catch (Exception ignored) {}
      try { if (encoder != null) { encoder.stop(); encoder.release(); } } catch (Exception ignored) {}
      try { if (muxer != null) { if (started) muxer.stop(); muxer.release(); } } catch (Exception ignored) {}
      v.release();
      a.release();
    }
  }

  private static MediaCodec createAacEncoder(int rate, int channels) throws Exception {
    MediaFormat aac = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, rate, channels);
    aac.setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC);
    aac.setInteger(MediaFormat.KEY_BIT_RATE, 128000);
    aac.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 1 << 16);
    MediaCodec enc = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC);
    enc.configure(aac, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);
    enc.start();
    return enc;
  }

  private static int track(MediaExtractor e, String prefix) {
    for (int i = 0; i < e.getTrackCount(); i++) {
      String mime = e.getTrackFormat(i).getString(MediaFormat.KEY_MIME);
      if (mime != null && mime.startsWith(prefix)) return i;
    }
    return -1;
  }
}
