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
      int outVideo = muxer.addTrack(vFormat);

      decoder = MediaCodec.createDecoderByType(aFormat.getString(MediaFormat.KEY_MIME));
      decoder.configure(aFormat, null, null, 0);
      decoder.start();
      int rate = aFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE), channels = Math.min(2, aFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT));
      MediaFormat aac = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, rate, channels);
      aac.setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC);
      aac.setInteger(MediaFormat.KEY_BIT_RATE, 128000);
      aac.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 1 << 16);
      encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC);
      encoder.configure(aac, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);
      encoder.start();

      // Chuyển mã âm thanh; bắt đầu muxer khi encoder báo định dạng đầu ra.
      MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
      List<byte[]> pendingData = new ArrayList<>();
      List<MediaCodec.BufferInfo> pendingInfo = new ArrayList<>();
      int outAudio = -1;
      boolean inputDone = false, decodeDone = false, encodeDone = false, eosSent = false;
      ArrayDeque<byte[]> pcm = new ArrayDeque<>();
      ArrayDeque<Long> pcmTime = new ArrayDeque<>();
      while (!encodeDone) {
        if (!inputDone) {
          int i = decoder.dequeueInputBuffer(5000);
          if (i >= 0) {
            ByteBuffer buf = decoder.getInputBuffer(i);
            int size = a.readSampleData(buf, 0);
            long t = a.getSampleTime();
            if (size < 0 || t > duration) {
              decoder.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
              inputDone = true;
            } else {
              decoder.queueInputBuffer(i, 0, size, t, 0);
              a.advance();
            }
          }
        }
        if (!decodeDone) {
          int o = decoder.dequeueOutputBuffer(info, 5000);
          if (o >= 0) {
            if (info.size > 0 && info.presentationTimeUs <= duration) {
              ByteBuffer buf = decoder.getOutputBuffer(o);
              byte[] chunk = new byte[info.size];
              buf.position(info.offset);
              buf.get(chunk);
              pcm.add(chunk);
              pcmTime.add(info.presentationTimeUs);
            }
            if ((info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) decodeDone = true;
            decoder.releaseOutputBuffer(o, false);
          }
        }
        // Đưa PCM vào encoder
        while (!pcm.isEmpty()) {
          int i = encoder.dequeueInputBuffer(0);
          if (i < 0) break;
          ByteBuffer buf = encoder.getInputBuffer(i);
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
          if (i >= 0) { encoder.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM); eosSent = true; }
        }
        int e = encoder.dequeueOutputBuffer(info, 5000);
        if (e == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
          outAudio = muxer.addTrack(encoder.getOutputFormat());
          muxer.start();
          started = true;
          for (int k = 0; k < pendingData.size(); k++) muxer.writeSampleData(outAudio, ByteBuffer.wrap(pendingData.get(k)), pendingInfo.get(k));
          pendingData.clear();
          pendingInfo.clear();
        } else if (e >= 0) {
          ByteBuffer buf = encoder.getOutputBuffer(e);
          if ((info.flags & MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0 && info.size > 0) {
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
      }
      if (!started) throw new Exception("encoder never started");

      // Chép nguyên luồng hình
      ByteBuffer frame = ByteBuffer.allocate(4 * 1024 * 1024);
      MediaCodec.BufferInfo vi = new MediaCodec.BufferInfo();
      while (true) {
        int size = v.readSampleData(frame, 0);
        if (size < 0) break;
        vi.set(0, size, v.getSampleTime(), (v.getSampleFlags() & MediaExtractor.SAMPLE_FLAG_SYNC) != 0 ? MediaCodec.BUFFER_FLAG_KEY_FRAME : 0);
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

  private static int track(MediaExtractor e, String prefix) {
    for (int i = 0; i < e.getTrackCount(); i++)
      if (e.getTrackFormat(i).getString(MediaFormat.KEY_MIME).startsWith(prefix)) return i;
    return -1;
  }
}
