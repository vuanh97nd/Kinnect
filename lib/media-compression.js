import { createHash } from 'node:crypto';
import { existsSync } from 'node:fs';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { execFile } from 'node:child_process';
import { mp4Duration } from './shorts.js';

const IMAGE_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp']);
const VIDEO_TYPES = new Set(['video/mp4', 'video/webm']);

const IMAGE_EXT = {
  'image/jpeg': '.jpg',
  'image/png': '.png',
  'image/webp': '.webp',
};

const VIDEO_EXT = {
  'video/mp4': '.mp4',
  'video/webm': '.webm',
};

function parsePositiveInt(value, fallback, min = 1, max = 100000) {
  const n = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(n) || n < min || n > max) return fallback;
  return n;
}

function parseBitrate(value, fallback) {
  const s = String(value ?? '').trim();
  return /^\d+[kKmM]$/.test(s) ? s : fallback;
}

function doubleBitrate(rate) {
  const m = /^(\d+)([kKmM])$/.exec(rate);
  if (!m) return '3600k';
  return `${Number(m[1]) * 2}${m[2]}`;
}

function sha256(buf) {
  return createHash('sha256').update(buf).digest('hex');
}

function isValidJpeg(buf) {
  return buf.length >= 16 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff;
}

export function resolveFfmpegPath(env = process.env, explicitPath = null) {
  const candidates = [
    explicitPath,
    env.KINNECT_MEDIA_FFMPEG,
    env.KINNECT_FFMPEG,
    resolve('work/ai-ffmpeg/ffmpeg.exe'),
    'D:/Codex/Kinnect/work/ai-ffmpeg/ffmpeg.exe',
  ].filter(Boolean);
  for (const candidate of candidates) {
    if (typeof candidate === 'string' && candidate.trim() && existsSync(candidate.trim())) {
      return candidate.trim();
    }
  }
  return null;
}

/**
 * Balanced (Option B) server-side image & video compressor using FFmpeg.
 * - Images: synchronous resize + EXIF strip + JPEG optimization (~50-150 ms).
 * - Videos: asynchronous background queue (avoids iOS 18s request timeout) using H.264/AAC +faststart.
 * - Strictly non-destructive: keeps original media on any error or when compressed size is not smaller.
 */
export function createMediaCompressor({ db, env = process.env, options = {}, logger = console } = {}) {
  const enabledByEnv = env.KINNECT_MEDIA_COMPRESS !== '0';
  const enabled = options.enabled !== undefined ? Boolean(options.enabled) : enabledByEnv;
  const ffmpegPath = enabled ? resolveFfmpegPath(env, options.ffmpegPath || null) : null;

  const threads = parsePositiveInt(options.threads ?? env.KINNECT_MEDIA_FFMPEG_THREADS, 4, 1, 16);
  const maxConcurrent = parsePositiveInt(options.maxConcurrent ?? env.KINNECT_MEDIA_CONCURRENCY, 1, 1, 4);
  const maxQueue = parsePositiveInt(options.maxQueue, 100, 1, 1000);
  const imageTimeoutMs = parsePositiveInt(options.imageTimeoutMs ?? env.KINNECT_IMAGE_TIMEOUT_MS, 10000, 1000, 60000);
  const videoTimeoutMs = parsePositiveInt(options.videoTimeoutMs ?? env.KINNECT_VIDEO_TIMEOUT_MS, 180000, 5000, 600000);
  const minVideoBytes = parsePositiveInt(options.minVideoBytes ?? env.KINNECT_VIDEO_MIN_BYTES, 256 * 1024, 1, 50 * 1024 * 1024);
  const minVideoSavingsRatio = typeof options.minVideoSavingsRatio === 'number'
    ? Math.max(0, Math.min(0.9, options.minVideoSavingsRatio))
    : 0.10;

  // Option B (Balanced) image profiles
  const imageProfiles = {
    avatar: {
      maxDim: parsePositiveInt(options.avatarMaxDim ?? env.KINNECT_IMAGE_AVATAR_MAX_DIM, 512, 128, 2048),
      qscale: parsePositiveInt(options.avatarQscale ?? env.KINNECT_IMAGE_QSCALE, 4, 2, 12),
      minBytes: parsePositiveInt(options.minImageBytes, 12 * 1024, 0, 10 * 1024 * 1024),
    },
    cover: {
      maxDim: parsePositiveInt(options.coverMaxDim ?? env.KINNECT_IMAGE_COVER_MAX_DIM, 1440, 320, 4096),
      qscale: parsePositiveInt(options.coverQscale ?? env.KINNECT_IMAGE_QSCALE, 4, 2, 12),
      minBytes: parsePositiveInt(options.minImageBytes, 24 * 1024, 0, 10 * 1024 * 1024),
    },
    post: {
      maxDim: parsePositiveInt(options.postMaxDim ?? env.KINNECT_IMAGE_MAX_DIM, 1600, 320, 4096),
      qscale: parsePositiveInt(options.postQscale ?? env.KINNECT_IMAGE_QSCALE, 4, 2, 12),
      minBytes: parsePositiveInt(options.minImageBytes, 32 * 1024, 0, 10 * 1024 * 1024),
    },
    chat: {
      maxDim: parsePositiveInt(options.chatMaxDim ?? env.KINNECT_IMAGE_CHAT_MAX_DIM, 1440, 320, 4096),
      qscale: parsePositiveInt(options.chatQscale ?? env.KINNECT_IMAGE_CHAT_QSCALE, 5, 2, 12),
      minBytes: parsePositiveInt(options.minImageBytes, 24 * 1024, 0, 10 * 1024 * 1024),
    },
  };

  // Option B (Balanced) video profiles
  const videoShortSide = parsePositiveInt(options.videoMaxHeight ?? env.KINNECT_VIDEO_MAX_HEIGHT, 720, 240, 2160);
  const videoLongSide = Math.round((videoShortSide * 16) / 9 / 2) * 2; // 720 -> 1280, 1080 -> 1920
  const videoMaxFps = parsePositiveInt(options.videoMaxFps ?? env.KINNECT_VIDEO_MAX_FPS, 30, 15, 60);
  const videoAudioBitrate = parseBitrate(options.videoAudioBitrate ?? env.KINNECT_VIDEO_AUDIO_BITRATE, '96k');
  const videoPreset = String(options.videoPreset ?? env.KINNECT_VIDEO_PRESET ?? 'veryfast').trim() || 'veryfast';

  const postMaxrate = parseBitrate(options.videoMaxrate ?? env.KINNECT_VIDEO_MAXRATE, '1800k');
  const chatMaxrate = parseBitrate(options.videoChatMaxrate ?? env.KINNECT_VIDEO_CHAT_MAXRATE, '1200k');

  const videoProfiles = {
    post: {
      shortSide: videoShortSide,
      longSide: videoLongSide,
      maxFps: videoMaxFps,
      crf: parsePositiveInt(options.videoCrf ?? env.KINNECT_VIDEO_CRF, 26, 18, 36),
      maxrate: postMaxrate,
      bufsize: doubleBitrate(postMaxrate),
      audioBitrate: videoAudioBitrate,
    },
    short: {
      shortSide: videoShortSide,
      longSide: videoLongSide,
      maxFps: videoMaxFps,
      crf: parsePositiveInt(options.videoCrf ?? env.KINNECT_VIDEO_CRF, 26, 18, 36),
      maxrate: postMaxrate,
      bufsize: doubleBitrate(postMaxrate),
      audioBitrate: videoAudioBitrate,
    },
    chat: {
      shortSide: videoShortSide,
      longSide: videoLongSide,
      maxFps: videoMaxFps,
      crf: parsePositiveInt(options.videoChatCrf ?? env.KINNECT_VIDEO_CHAT_CRF, 28, 18, 36),
      maxrate: chatMaxrate,
      bufsize: doubleBitrate(chatMaxrate),
      audioBitrate: videoAudioBitrate,
    },
  };

  let closed = false;
  let active = 0;
  const queue = [];
  const activeChildren = new Set();
  const drainWaiters = new Set();

  const stats = {
    enabled: Boolean(enabled && ffmpegPath),
    configured: enabled,
    ffmpegAvailable: Boolean(ffmpegPath),
    preset: 'balanced',
    imagesCompressed: 0,
    imagesSkipped: 0,
    videosCompressed: 0,
    videosSkipped: 0,
    videoErrors: 0,
    thumbnailsGenerated: 0,
    bytesSaved: 0,
  };

  function notifyDrained() {
    if (active === 0 && queue.length === 0) {
      for (const resolveWaiter of drainWaiters) resolveWaiter();
      drainWaiters.clear();
    }
  }

  function runFfmpeg(args, timeoutMs) {
    return new Promise((resolveRun, rejectRun) => {
      if (closed || !ffmpegPath) return rejectRun(new Error('compressor_unavailable'));
      const child = execFile(
        ffmpegPath,
        args,
        { timeout: timeoutMs, maxBuffer: 2 * 1024 * 1024, windowsHide: true },
        (err, stdout, stderr) => {
          activeChildren.delete(child);
          if (err) return rejectRun(Object.assign(err, { stderr }));
          resolveRun({ stdout, stderr });
        },
      );
      activeChildren.add(child);
    });
  }

  async function compressImage(bytes, type, profileName = 'post') {
    const buffer = Buffer.isBuffer(bytes) ? bytes : Buffer.from(bytes);
    const profile = imageProfiles[profileName] || imageProfiles.post;
    if (!enabled || closed || !ffmpegPath || !IMAGE_TYPES.has(type) || buffer.length < profile.minBytes) {
      stats.imagesSkipped++;
      return { type, bytes: buffer, compressed: false, originalBytes: buffer.length, savedBytes: 0 };
    }
    const dir = await mkdtemp(join(tmpdir(), 'kinnect-img-'));
    try {
      const inputFile = join(dir, 'in' + (IMAGE_EXT[type] || '.bin'));
      const outputFile = join(dir, 'out.jpg');
      await writeFile(inputFile, buffer);
      const vf = `scale='min(${profile.maxDim},iw)':'min(${profile.maxDim},ih)':force_original_aspect_ratio=decrease:flags=lanczos`;
      await runFfmpeg([
        '-v', 'error',
        '-nostdin',
        '-y',
        '-threads', '2',
        '-i', inputFile,
        '-map_metadata', '-1',
        '-vf', vf,
        '-frames:v', '1',
        '-c:v', 'mjpeg',
        '-q:v', String(profile.qscale),
        '-pix_fmt', 'yuvj420p',
        '-f', 'image2',
        outputFile,
      ], imageTimeoutMs);
      const out = await readFile(outputFile);
      if (!isValidJpeg(out) || out.length >= buffer.length) {
        stats.imagesSkipped++;
        return { type, bytes: buffer, compressed: false, originalBytes: buffer.length, savedBytes: 0 };
      }
      const saved = buffer.length - out.length;
      stats.imagesCompressed++;
      stats.bytesSaved += saved;
      return {
        type: 'image/jpeg',
        bytes: out,
        compressed: true,
        originalBytes: buffer.length,
        savedBytes: saved,
      };
    } catch {
      stats.imagesSkipped++;
      return { type, bytes: buffer, compressed: false, originalBytes: buffer.length, savedBytes: 0 };
    } finally {
      await rm(dir, { recursive: true, force: true }).catch(() => {});
    }
  }

  async function extractThumbnailFromFile(sourceFile, dir) {
    const thumbFile = join(dir, 'thumb.jpg');
    const vf = "scale='min(640,iw)':'min(640,ih)':force_original_aspect_ratio=decrease:flags=lanczos";
    for (const seek of ['0.5', '0']) {
      try {
        await runFfmpeg([
          '-v', 'error',
          '-nostdin',
          '-y',
          '-threads', '2',
          '-ss', seek,
          '-i', sourceFile,
          '-map', '0:v:0',
          '-map_metadata', '-1',
          '-vf', vf,
          '-frames:v', '1',
          '-c:v', 'mjpeg',
          '-q:v', '5',
          '-pix_fmt', 'yuvj420p',
          '-f', 'image2',
          thumbFile,
        ], imageTimeoutMs);
        const bytes = await readFile(thumbFile);
        if (isValidJpeg(bytes)) return bytes;
      } catch {}
    }
    return null;
  }

  function saveThumbnail(table, id, thumbBytes) {
    if (!thumbBytes || !db || closed) return false;
    const kind = table === 'shorts' ? 'short' : table === 'post_media' ? 'post' : null;
    if (!kind) return false;
    try {
      db.prepare(
        'INSERT INTO media_thumbnails(kind,target_id,type,data,created) VALUES(?,?,?,?,?) ON CONFLICT(kind,target_id) DO UPDATE SET type=excluded.type,data=excluded.data,created=excluded.created',
      ).run(kind, id, 'image/jpeg', thumbBytes, Date.now());
      stats.thumbnailsGenerated++;
      return true;
    } catch {
      return false;
    }
  }

  function readTargetRow(table, id) {
    if (table === 'shorts') {
      return db.prepare('SELECT data FROM shorts WHERE id=?').get(id);
    }
    if (table === 'post_media') {
      return db.prepare('SELECT type, data FROM post_media WHERE post_id=?').get(id);
    }
    if (table === 'chat_attachments') {
      return db.prepare('SELECT type, data FROM chat_attachments WHERE id=?').get(id);
    }
    return null;
  }

  function updateTargetRow(table, id, bytes) {
    if (table === 'shorts') {
      db.prepare('UPDATE shorts SET data=? WHERE id=?').run(bytes, id);
      return;
    }
    if (table === 'post_media') {
      db.prepare("UPDATE post_media SET type='video/mp4', data=? WHERE post_id=?").run(bytes, id);
      try {
        db.prepare("UPDATE post_media_items SET type='video/mp4', data=? WHERE post_id=? AND position=0").run(bytes, id);
      } catch {}
      return;
    }
    if (table === 'chat_attachments') {
      db.prepare("UPDATE chat_attachments SET type='video/mp4', data=? WHERE id=?").run(bytes, id);
    }
  }

  async function processVideoJob(job) {
    if (closed || !db) return;
    let row;
    try {
      row = readTargetRow(job.table, job.id);
    } catch {
      return;
    }
    if (!row || !row.data) {
      stats.videosSkipped++;
      return;
    }
    const currentBytes = Buffer.from(row.data);
    if (currentBytes.length !== job.originalLength || sha256(currentBytes) !== job.originalHash) {
      stats.videosSkipped++;
      return;
    }

    const dir = await mkdtemp(join(tmpdir(), 'kinnect-vid-'));
    try {
      const inputFile = join(dir, 'in' + (VIDEO_EXT[job.type] || '.mp4'));
      await writeFile(inputFile, currentBytes);

      const wantsThumb = job.table === 'shorts' || job.table === 'post_media';
      let compressed = null;

      if (!job.skipTranscode) {
        const profile = videoProfiles[job.profile] || videoProfiles.post;
        const outputFile = join(dir, 'out.mp4');
        const s = profile.shortSide;
        const l = profile.longSide;
        const ratioExpr = `min(1,min(if(gte(iw,ih),${l},${s})/iw,if(gte(iw,ih),${s},${l})/ih))`;
        const scaleFilter = `scale='max(2,trunc(iw*${ratioExpr}/2)*2)':'max(2,trunc(ih*${ratioExpr}/2)*2)':flags=lanczos`;

        try {
          await runFfmpeg([
            '-v', 'error',
            '-nostdin',
            '-y',
            '-threads', String(threads),
            '-i', inputFile,
            '-map', '0:v:0',
            '-map', '0:a:0?',
            '-map_metadata', '-1',
            '-vf', scaleFilter,
            '-fpsmax', String(profile.maxFps),
            '-c:v', 'libx264',
            '-preset', videoPreset,
            '-profile:v', 'main',
            '-pix_fmt', 'yuv420p',
            '-crf', String(profile.crf),
            '-maxrate', profile.maxrate,
            '-bufsize', profile.bufsize,
            '-c:a', 'aac',
            '-b:a', profile.audioBitrate,
            '-ac', '2',
            '-ar', '44100',
            '-movflags', '+faststart',
            '-f', 'mp4',
            outputFile,
          ], videoTimeoutMs);
          const out = await readFile(outputFile);
          if (out.length && Number.isFinite(mp4Duration(out)) && mp4Duration(out) > 0) {
            compressed = out;
          }
        } catch (err) {
          if (!closed) {
            stats.videoErrors++;
            logger?.warn?.(`[media-compress] transcode skipped ${job.table}:${job.id}:`, err?.message || err);
          }
        }
      }

      if (closed) return;

      const thumbBytes = wantsThumb ? await extractThumbnailFromFile(inputFile, dir) : null;
      if (closed) return;

      // Re-verify row wasn't deleted or edited while ffmpeg was running.
      let latest;
      try {
        latest = readTargetRow(job.table, job.id);
      } catch {
        return;
      }
      if (!latest || !latest.data) {
        stats.videosSkipped++;
        return;
      }
      const latestBytes = Buffer.from(latest.data);
      if (latestBytes.length !== job.originalLength || sha256(latestBytes) !== job.originalHash) {
        stats.videosSkipped++;
        return;
      }

      if (thumbBytes) saveThumbnail(job.table, job.id, thumbBytes);

      const minAllowedSize = job.type === 'video/webm'
        ? job.originalLength - 1
        : Math.floor(job.originalLength * (1 - minVideoSavingsRatio));

      if (!compressed || compressed.length > minAllowedSize) {
        stats.videosSkipped++;
        return;
      }

      updateTargetRow(job.table, job.id, compressed);
      const saved = job.originalLength - compressed.length;
      stats.videosCompressed++;
      stats.bytesSaved += saved;

      const pct = Math.round((saved / job.originalLength) * 100);
      const beforeMb = (job.originalLength / 1048576).toFixed(2);
      const afterMb = (compressed.length / 1048576).toFixed(2);
      logger?.log?.(`[media-compress] ${job.table}:${job.id} (${job.profile}) ${beforeMb} MB -> ${afterMb} MB (-${pct}%)`);
    } finally {
      await rm(dir, { recursive: true, force: true }).catch(() => {});
    }
  }

  function pump() {
    while (!closed && active < maxConcurrent && queue.length > 0) {
      const job = queue.shift();
      active++;
      void processVideoJob(job)
        .catch((err) => {
          if (!closed) {
            stats.videoErrors++;
            logger?.warn?.(`[media-compress] skipped ${job.table}:${job.id}:`, err?.message || err);
          }
        })
        .finally(() => {
          active--;
          if (!closed) pump();
          notifyDrained();
        });
    }
    notifyDrained();
  }

  function enqueueVideo({ table, id, bytes, type = 'video/mp4', profile = 'post' }) {
    if (!enabled || closed || !ffmpegPath || !db) return { queued: false, reason: 'disabled' };
    if (!VIDEO_TYPES.has(type)) return { queued: false, reason: 'unsupported_type' };
    const buffer = Buffer.isBuffer(bytes) ? bytes : Buffer.from(bytes);
    const wantsThumb = table === 'shorts' || table === 'post_media';
    const skipTranscode = buffer.length < minVideoBytes;
    if (skipTranscode && !wantsThumb) {
      stats.videosSkipped++;
      return { queued: false, reason: 'below_threshold' };
    }
    const key = `${table}:${id}`;
    const existingIndex = queue.findIndex((item) => item.key === key);
    if (existingIndex === -1 && queue.length >= maxQueue) {
      stats.videosSkipped++;
      return { queued: false, reason: 'queue_full' };
    }
    const job = {
      key,
      table,
      id,
      type,
      profile,
      skipTranscode,
      originalLength: buffer.length,
      originalHash: sha256(buffer),
    };
    if (existingIndex >= 0) queue[existingIndex] = job;
    else queue.push(job);
    queueMicrotask(pump);
    return { queued: true };
  }

  function drain() {
    if (active === 0 && queue.length === 0) return Promise.resolve();
    return new Promise((resolveDrain) => {
      drainWaiters.add(resolveDrain);
    });
  }

  function status() {
    return {
      ...stats,
      pending: queue.length,
      active,
    };
  }

  function close() {
    closed = true;
    queue.length = 0;
    for (const child of activeChildren) {
      try { child.kill('SIGKILL'); } catch {}
    }
    activeChildren.clear();
    notifyDrained();
  }

  return {
    compressImage,
    enqueueVideo,
    drain,
    status,
    close,
  };
}
