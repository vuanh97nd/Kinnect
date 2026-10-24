// Kinnect Studio: camera trực tiếp + bộ lọc màu, làm mịn da và sticker bám khuôn mặt.
// Dùng chung cho quay video ngắn và livestream. Camera chỉ bật khi người dùng mở Studio/Live
// và luôn được tắt khi đóng.

export const FILTERS = [
  ["none", "Gốc", "none"],
  ["warm", "Ấm", "saturate(1.15) sepia(0.18) brightness(1.04)"],
  ["cool", "Mát", "saturate(1.1) hue-rotate(-12deg) brightness(1.03)"],
  ["vivid", "Rực", "saturate(1.55) contrast(1.08)"],
  ["mono", "Đen trắng", "grayscale(1) contrast(1.12)"],
  ["vintage", "Cổ điển", "sepia(0.45) contrast(0.95) brightness(1.05) saturate(0.9)"],
  ["dream", "Mơ màng", "saturate(1.2) brightness(1.08) hue-rotate(8deg)"],
];
export const STICKERS = [
  ["none", "Không", ""],
  ["glasses", "Kính", "😎"],
  ["hearts", "Tim", "😍"],
  ["crown", "Vương miện", "👑"],
  ["cat", "Mèo", "🐱"],
  ["sparkle", "Lấp lánh", "✨"],
];

// Bộ xử lý: video gốc → canvas có hiệu ứng → MediaStream mới (giữ nguyên âm thanh).
export function createEffects(rawStream, { width = 540, height = 960 } = {}) {
  const video = document.createElement("video");
  video.muted = true;
  video.playsInline = true;
  video.srcObject = rawStream;
  const canvas = document.createElement("canvas");
  const settings = rawStream.getVideoTracks()[0]?.getSettings?.() || {};
  // Giữ đúng hướng camera: dọc trên điện thoại, ngang trên máy tính.
  const landscape = (settings.width || 0) > (settings.height || 0);
  canvas.width = landscape ? height : width;
  canvas.height = landscape ? width : height;
  const ctx = canvas.getContext("2d");
  const state = { filter: "none", soft: false, sticker: "none", mirror: true };
  let face = null;
  let detector = null;
  let detecting = false;
  let raf = 0;
  let stopped = false;
  if ("FaceDetector" in window) {
    try {
      detector = new window.FaceDetector({ fastMode: true, maxDetectedFaces: 1 });
    } catch {
      detector = null;
    }
  }
  const faceSupported = !!detector;
  async function detect() {
    if (!detector || detecting || state.sticker === "none") return;
    detecting = true;
    try {
      const faces = await detector.detect(canvas);
      face = faces[0]?.boundingBox || null;
    } catch {
      face = null;
    } finally {
      detecting = false;
    }
  }
  function cover() {
    const vw = video.videoWidth || canvas.width;
    const vh = video.videoHeight || canvas.height;
    const scale = Math.max(canvas.width / vw, canvas.height / vh);
    const w = vw * scale;
    const h = vh * scale;
    return [(canvas.width - w) / 2, (canvas.height - h) / 2, w, h];
  }
  function drawSticker() {
    const emoji = STICKERS.find((s) => s[0] === state.sticker)?.[2];
    if (!emoji) return;
    // Có nhận diện khuôn mặt: bám theo mặt. Không có: đặt ở vị trí mặc định phía trên giữa khung.
    const box = face || {
      x: canvas.width * 0.3,
      y: canvas.height * 0.22,
      width: canvas.width * 0.4,
      height: canvas.width * 0.4,
    };
    const cx = box.x + box.width / 2;
    ctx.save();
    ctx.filter = "none";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    if (state.sticker === "glasses") {
      ctx.font = Math.round(box.width * 0.9) + "px serif";
      ctx.fillText("🕶️", cx, box.y + box.height * 0.42);
    } else if (state.sticker === "crown") {
      ctx.font = Math.round(box.width * 0.75) + "px serif";
      ctx.fillText("👑", cx, box.y - box.height * 0.18);
    } else if (state.sticker === "cat") {
      ctx.font = Math.round(box.width * 0.38) + "px serif";
      ctx.fillText("🐱", box.x + box.width * 0.12, box.y - box.height * 0.1);
      ctx.fillText("🐱", box.x + box.width * 0.88, box.y - box.height * 0.1);
    } else if (state.sticker === "hearts") {
      const t = performance.now() / 600;
      ctx.font = Math.round(box.width * 0.28) + "px serif";
      for (let i = 0; i < 5; i++) {
        const a = t + (i * Math.PI * 2) / 5;
        ctx.fillText("❤️", cx + Math.cos(a) * box.width * 0.75, box.y + box.height * 0.5 + Math.sin(a) * box.height * 0.75);
      }
    } else if (state.sticker === "sparkle") {
      const t = performance.now() / 400;
      ctx.font = Math.round(box.width * 0.22) + "px serif";
      for (let i = 0; i < 7; i++) {
        ctx.globalAlpha = 0.5 + 0.5 * Math.sin(t + i * 1.7);
        ctx.fillText("✨", box.x + ((i * 37) % 100) / 100 * box.width * 1.6 - box.width * 0.3, box.y - box.height * 0.2 + ((i * 53) % 100) / 100 * box.height * 1.4);
      }
    }
    ctx.restore();
  }
  let frame = 0;
  function draw() {
    if (stopped) return;
    if (video.readyState >= 2) {
      const [x, y, w, h] = cover();
      const base = FILTERS.find((f) => f[0] === state.filter)?.[2] || "none";
      ctx.save();
      if (state.mirror) {
        ctx.translate(canvas.width, 0);
        ctx.scale(-1, 1);
      }
      ctx.filter = base;
      ctx.drawImage(video, x, y, w, h);
      if (state.soft) {
        // Làm mịn da nhẹ: phủ một lớp mờ trong suốt lên ảnh gốc.
        ctx.globalAlpha = 0.35;
        ctx.filter = (base === "none" ? "" : base + " ") + "blur(3px) brightness(1.06)";
        ctx.drawImage(video, x, y, w, h);
        ctx.globalAlpha = 1;
      }
      ctx.restore();
      if (++frame % 6 === 0) detect();
      drawSticker();
    }
    raf = requestAnimationFrame(draw);
  }
  video.play().catch(() => {});
  draw();
  // requestAnimationFrame dừng khi tab ẩn; dùng thêm hẹn giờ để livestream không bị đứng hình.
  const keepAlive = setInterval(() => {
    if (document.hidden && !stopped) {
      cancelAnimationFrame(raf);
      draw();
    }
  }, 66);
  const output = canvas.captureStream(30);
  for (const track of rawStream.getAudioTracks()) output.addTrack(track);
  return {
    stream: output,
    canvas,
    state,
    faceSupported,
    set(patch) {
      Object.assign(state, patch);
      if (patch.sticker === "none") face = null;
    },
    stop() {
      stopped = true;
      cancelAnimationFrame(raf);
      clearInterval(keepAlive);
      output.getVideoTracks().forEach((t) => t.stop());
      video.srcObject = null;
    },
  };
}

// Thanh chọn hiệu ứng dùng chung (bộ lọc, làm mịn, sticker).
export function effectPicker(fx, { dark = true } = {}) {
  const box = document.createElement("div");
  box.className = "fx-picker" + (dark ? " dark" : "");
  const row = (items, key) => {
    const r = document.createElement("div");
    r.className = "fx-row";
    r.setAttribute("role", "group");
    r.setAttribute("aria-label", key === "filter" ? "Bộ lọc màu" : "Sticker khuôn mặt");
    for (const [id, label, sample] of items) {
      const b = document.createElement("button");
      b.type = "button";
      b.className = "fx-chip" + (fx.state[key] === id ? " on" : "");
      b.setAttribute("aria-pressed", String(fx.state[key] === id));
      b.textContent = key === "sticker" && sample ? sample + " " + label : label;
      b.onclick = () => {
        fx.set({ [key]: id });
        for (const c of r.children) {
          c.classList.toggle("on", c === b);
          c.setAttribute("aria-pressed", String(c === b));
        }
      };
      r.append(b);
    }
    return r;
  };
  const soft = document.createElement("button");
  soft.type = "button";
  soft.className = "fx-chip" + (fx.state.soft ? " on" : "");
  soft.textContent = "✨ Làm mịn da";
  soft.setAttribute("aria-pressed", String(fx.state.soft));
  soft.onclick = () => {
    fx.set({ soft: !fx.state.soft });
    soft.classList.toggle("on", fx.state.soft);
    soft.setAttribute("aria-pressed", String(fx.state.soft));
  };
  const filters = row(FILTERS, "filter");
  filters.prepend(soft);
  box.append(filters, row(STICKERS, "sticker"));
  if (!fx.faceSupported) {
    const note = document.createElement("p");
    note.className = "fx-note";
    note.textContent = "Trình duyệt này chưa hỗ trợ nhận diện khuôn mặt: sticker hiển thị ở giữa khung hình.";
    box.append(note);
  }
  return box;
}

function pickMime() {
  for (const t of ["video/mp4;codecs=avc1.42E01E,mp4a.40.2", "video/mp4;codecs=avc1", "video/mp4"])
    if (window.MediaRecorder?.isTypeSupported?.(t)) return t;
  return null;
}

// Studio quay video toàn màn hình. onDone(blob, caption) được gọi khi người dùng bấm Đăng.
export async function openStudio({ onDone, notify = () => {} }) {
  if (!navigator.mediaDevices?.getUserMedia) {
    notify("Trình duyệt không cho dùng camera. Hãy mở Kinnect bằng HTTPS (app.kinnect.io.vn).");
    return;
  }
  const mime = pickMime();
  if (!mime) {
    notify("Trình duyệt này chưa quay được video MP4. Hãy dùng Chrome, Edge hoặc Safari bản mới, hoặc chọn video có sẵn.");
    return;
  }
  let facing = "user";
  let raw;
  try {
    raw = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: facing, width: { ideal: 720 }, height: { ideal: 1280 } },
      audio: true,
    });
  } catch (e) {
    notify("Không mở được camera/micro: " + e.message);
    return;
  }
  let fx = createEffects(raw);
  const root = document.createElement("div");
  root.className = "studio";
  root.setAttribute("role", "dialog");
  root.setAttribute("aria-modal", "true");
  root.setAttribute("aria-label", "Quay video");
  root.innerHTML =
    '<div class="studio-top"><button type="button" class="studio-x" aria-label="Đóng">✕</button><span class="studio-time" aria-live="polite">0:00 / 1:00</span><button type="button" class="studio-flip" aria-label="Đổi camera trước/sau">⟲</button></div>' +
    '<div class="studio-stage"></div>' +
    '<div class="studio-fx"></div>' +
    '<div class="studio-bottom"><button type="button" class="studio-rec" aria-label="Bắt đầu quay"><span></span></button></div>' +
    '<form class="studio-review" hidden><video class="studio-preview" playsinline loop controls></video><input class="studio-caption" maxlength="500" placeholder="Viết chú thích…" aria-label="Chú thích video"><div class="studio-actions"><button type="button" class="studio-retake">Quay lại</button><button type="submit" class="studio-post">Đăng video</button></div></form>';
  document.body.append(root);
  document.body.classList.add("studio-open");
  const $ = (s) => root.querySelector(s);
  const mount = () => {
    $(".studio-stage").replaceChildren(fx.canvas);
    $(".studio-fx").replaceChildren(effectPicker(fx));
  };
  mount();
  let recorder = null;
  let chunks = [];
  let started = 0;
  let tick = 0;
  let blobUrl = "";
  const fmt = (s) => Math.floor(s / 60) + ":" + String(Math.floor(s % 60)).padStart(2, "0");
  function close() {
    try {
      recorder?.state === "recording" && recorder.stop();
    } catch {}
    clearInterval(tick);
    fx.stop();
    raw.getTracks().forEach((t) => t.stop());
    if (blobUrl) URL.revokeObjectURL(blobUrl);
    root.remove();
    document.body.classList.remove("studio-open");
    document.removeEventListener("keydown", onKey);
  }
  const onKey = (e) => e.key === "Escape" && close();
  document.addEventListener("keydown", onKey);
  $(".studio-x").onclick = close;
  $(".studio-flip").onclick = async () => {
    if (recorder?.state === "recording") return;
    facing = facing === "user" ? "environment" : "user";
    try {
      const next = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: facing, width: { ideal: 720 }, height: { ideal: 1280 } },
        audio: true,
      });
      const keep = { ...fx.state, mirror: facing === "user" };
      fx.stop();
      raw.getTracks().forEach((t) => t.stop());
      raw = next;
      fx = createEffects(raw);
      fx.set(keep);
      mount();
    } catch (e) {
      facing = facing === "user" ? "environment" : "user";
      notify("Không đổi được camera: " + e.message);
    }
  };
  function stopRec() {
    if (recorder?.state === "recording") recorder.stop();
  }
  $(".studio-rec").onclick = () => {
    if (recorder?.state === "recording") return stopRec();
    chunks = [];
    recorder = new MediaRecorder(fx.stream, { mimeType: mime, videoBitsPerSecond: 1_200_000, audioBitsPerSecond: 96_000 });
    recorder.ondataavailable = (e) => e.data.size && chunks.push(e.data);
    recorder.onstop = () => {
      clearInterval(tick);
      root.classList.remove("recording");
      $(".studio-rec").setAttribute("aria-label", "Bắt đầu quay");
      const blob = new Blob(chunks, { type: "video/mp4" });
      if ((performance.now() - started) / 1000 < 1) return notify("Video quá ngắn. Giữ quay ít nhất 1 giây.");
      blobUrl = URL.createObjectURL(blob);
      $(".studio-preview").src = blobUrl;
      $(".studio-review").hidden = false;
      $(".studio-review").blob = blob;
      $(".studio-preview").play().catch(() => {});
      $(".studio-caption").focus();
    };
    recorder.start(1000);
    started = performance.now();
    root.classList.add("recording");
    $(".studio-rec").setAttribute("aria-label", "Dừng quay");
    tick = setInterval(() => {
      const s = (performance.now() - started) / 1000;
      $(".studio-time").textContent = fmt(s) + " / 1:00";
      if (s >= 59.5) stopRec();
    }, 250);
  };
  $(".studio-retake").onclick = () => {
    $(".studio-review").hidden = true;
    $(".studio-preview").pause();
    if (blobUrl) URL.revokeObjectURL(blobUrl);
    blobUrl = "";
    $(".studio-time").textContent = "0:00 / 1:00";
  };
  $(".studio-review").onsubmit = async (e) => {
    e.preventDefault();
    const blob = $(".studio-review").blob;
    if (blob.size > 12 * 1024 * 1024) return notify("Video vượt 12 MB. Hãy quay ngắn hơn.");
    const btn = $(".studio-post");
    btn.disabled = true;
    btn.textContent = "Đang đăng…";
    try {
      await onDone(blob, $(".studio-caption").value);
      close();
    } catch (err) {
      notify(err.message);
      btn.disabled = false;
      btn.textContent = "Đăng video";
    }
  };
}
