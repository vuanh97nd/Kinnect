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

// Studio quay video kiểu TikTok. onDone(blob, caption) khi bấm Đăng; onLive() khi chọn tab LIVE.
const ICON = {
  flip: '<svg viewBox="0 0 24 24"><path d="M4 12a8 8 0 0113.7-5.6L20 8.5M20 4v4.5h-4.5M20 12a8 8 0 01-13.7 5.6L4 15.5M4 20v-4.5h4.5"/></svg>',
  timer: '<svg viewBox="0 0 24 24"><circle cx="12" cy="13" r="8"/><path d="M12 9v4l2.5 2.5M9 2h6"/></svg>',
  filter: '<svg viewBox="0 0 24 24"><circle cx="9" cy="9" r="5.5"/><circle cx="15" cy="9" r="5.5"/><circle cx="12" cy="15" r="5.5"/></svg>',
  beauty: '<svg viewBox="0 0 24 24"><circle cx="10" cy="8" r="4"/><path d="M3 21a7 7 0 0114 0M18 3l.8 1.7L20.5 5.5l-1.7.8L18 8l-.8-1.7-1.7-.8 1.7-.8z"/></svg>',
};
// Hiệu ứng trên vòng quanh nút chụp: sticker bám mặt + một số bộ lọc nhanh
const CAROUSEL = [
  ["none", "none", "Gốc", "🙂"],
  ["sticker", "glasses", "Kính", "😎"],
  ["sticker", "hearts", "Tim", "😍"],
  ["sticker", "cat", "Mèo", "🐱"],
  ["sticker", "crown", "Vương miện", "👑"],
  ["sticker", "sparkle", "Lấp lánh", "✨"],
  ["filter", "vivid", "Rực rỡ", "🌈"],
  ["filter", "mono", "Đen trắng", "🖤"],
  ["filter", "vintage", "Cổ điển", "📷"],
];

export async function openStudio({ onDone, onLive, notify = () => {}, mode: startMode = "camera" }) {
  if (!navigator.mediaDevices?.getUserMedia) {
    notify("Trình duyệt không cho dùng camera. Hãy mở Kinnect bằng HTTPS (app.kinnect.io.vn).");
    return;
  }
  const mime = pickMime();
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
  let maxSec = 60;
  let delay = 0;
  const root = document.createElement("div");
  root.className = "studio tt";
  root.setAttribute("role", "dialog");
  root.setAttribute("aria-modal", "true");
  root.setAttribute("aria-label", "Quay video");
  const rail = (key, label) =>
    `<button type="button" class="tt-tool" data-tool="${key}" aria-label="${label}">${ICON[key]}<small>${label}</small></button>`;
  root.innerHTML =
    '<div class="tt-card">' +
    '<div class="tt-stage"></div>' +
    '<div class="tt-progress"><i></i></div>' +
    '<button type="button" class="tt-x" aria-label="Đóng">✕</button>' +
    '<span class="tt-time" aria-live="polite"></span>' +
    '<button type="button" class="tt-sound" aria-label="Thêm âm thanh">♪ <span>Thêm âm thanh</span></button>' +
    '<div class="tt-rail">' + rail("flip", "Lật") + rail("timer", "Hẹn giờ") + rail("filter", "Bộ lọc") + rail("beauty", "Làm đẹp") + "</div>" +
    '<div class="tt-sheet" hidden></div>' +
    '<div class="tt-count" hidden></div>' +
    '<div class="tt-modes" role="group" aria-label="Thời lượng"><button type="button" data-sec="60" class="on">60s</button><button type="button" data-sec="15">15s</button></div>' +
    '<form class="tt-golive" hidden><input class="tt-title" maxlength="100" placeholder="Thêm tiêu đề…" aria-label="Tiêu đề buổi live" required><button type="submit" class="tt-golive-btn">Phát LIVE</button></form>' +
    '<div class="tt-shutter-row"><div class="tt-carousel" role="group" aria-label="Hiệu ứng"></div><button type="button" class="tt-shutter" aria-label="Bắt đầu quay"><span></span></button></div>' +
    "</div>" +
    '<div class="tt-bottom"><label class="tt-gallery" aria-label="Tải video từ máy"><input type="file" accept="video/mp4,video/quicktime"><span>🖼️</span><small>Tải lên</small></label>' +
    '<div class="tt-tabs" role="group" aria-label="Chế độ"><button type="button" class="tt-mode on" data-mode="camera">CAMERA</button><button type="button" class="tt-mode" data-mode="live">LIVE</button></div><span class="tt-spacer"></span></div>' +
    '<form class="tt-post" hidden><div class="tt-post-head"><button type="button" class="tt-back" aria-label="Quay lại">‹</button><b>Đăng</b><span></span></div>' +
    '<div class="tt-post-body"><textarea class="tt-caption" maxlength="500" rows="4" placeholder="Thêm mô tả… #hashtag" aria-label="Chú thích video"></textarea><video class="tt-preview" playsinline loop muted autoplay></video></div>' +
    '<div class="tt-post-actions"><button type="button" class="tt-retake">Quay lại</button><button type="submit" class="tt-publish">Đăng</button></div></form>';
  document.body.append(root);
  document.body.classList.add("studio-open");
  const $ = (s) => root.querySelector(s);
  const mount = () => $(".tt-stage").replaceChildren(fx.canvas);
  mount();
  // Vòng hiệu ứng quanh nút chụp
  const carousel = $(".tt-carousel");
  let picked = "none";
  for (const [kind, id, label, emoji] of CAROUSEL) {
    const b = document.createElement("button");
    b.type = "button";
    b.className = "tt-fx" + (id === picked ? " on" : "");
    b.setAttribute("aria-label", label);
    b.setAttribute("aria-pressed", String(id === picked));
    b.innerHTML = "<span>" + emoji + "</span>";
    b.onclick = () => {
      picked = id;
      if (kind === "none") fx.set({ sticker: "none", filter: "none" });
      else fx.set({ [kind]: id });
      for (const c of carousel.children) {
        c.classList.toggle("on", c === b);
        c.setAttribute("aria-pressed", String(c === b));
      }
    };
    carousel.append(b);
  }
  // Âm nhạc: thư viện chung trên máy chủ hoặc nhạc của chính người dùng (trộn ngay trên máy)
  const music = new Audio();
  music.loop = true;
  music.preload = "auto";
  let musicUrl = "";
  let musicOwnUrl = "";
  const soundLabel = $(".tt-sound span");
  function setMusic(url, title) {
    music.pause();
    musicUrl = url || "";
    soundLabel.textContent = title || "Thêm âm thanh";
    $(".tt-sound").classList.toggle("on", !!url);
    if (url) {
      music.src = url;
      music.currentTime = 0;
      music.play().catch(() => {});
    } else music.removeAttribute("src");
  }
  // Bảng chọn từ cột công cụ
  const sheet = $(".tt-sheet");
  async function openSound() {
    if (!sheet.hidden && sheet.dataset.kind === "sound") {
      music.pause();
      return (sheet.hidden = true);
    }
    sheet.dataset.kind = "sound";
    sheet.replaceChildren();
    const list = document.createElement("div");
    list.className = "tt-tracks";
    const item = (label, on, fn) => {
      const b = document.createElement("button");
      b.type = "button";
      b.className = "tt-track" + (on ? " on" : "");
      b.textContent = label;
      b.onclick = () => {
        fn();
        for (const c of list.querySelectorAll(".tt-track")) c.classList.toggle("on", c === b);
      };
      list.append(b);
    };
    const own = document.createElement("label");
    own.className = "tt-track own";
    own.innerHTML = '<input type="file" accept="audio/*" aria-label="Chọn nhạc của bạn"><span>📁 Nhạc của bạn</span>';
    own.querySelector("input").onchange = (e) => {
      const f = e.target.files[0];
      if (!f) return;
      if (f.size > 20 * 1024 * 1024) return notify("File nhạc tối đa 20 MB.");
      if (musicOwnUrl) URL.revokeObjectURL(musicOwnUrl);
      musicOwnUrl = URL.createObjectURL(f);
      setMusic(musicOwnUrl, f.name.replace(/\.[^.]+$/, ""));
      sheet.hidden = true;
    };
    list.append(own);
    item("🔇 Không dùng nhạc", !musicUrl, () => setMusic("", ""));
    sheet.append(list);
    sheet.hidden = false;
    try {
      const r = await fetch("/api/music", { credentials: "same-origin" });
      const { tracks = [] } = r.ok ? await r.json() : {};
      for (const t of tracks) item("♪ " + t.title, musicUrl === t.url, () => setMusic(t.url, t.title));
      if (!tracks.length) {
        const n = document.createElement("p");
        n.className = "fx-note";
        n.textContent = "Thư viện chung chưa có bài nào. Bạn có thể chọn nhạc của mình.";
        sheet.append(n);
      }
    } catch {}
  }
  $(".tt-sound").onclick = openSound;
  function openSheet(kind) {
    if (!sheet.hidden && sheet.dataset.kind === kind) return (sheet.hidden = true);
    sheet.dataset.kind = kind;
    sheet.replaceChildren();
    const row = document.createElement("div");
    row.className = "fx-row";
    const add = (label, on, fn) => {
      const b = document.createElement("button");
      b.type = "button";
      b.className = "fx-chip" + (on ? " on" : "");
      b.textContent = label;
      b.setAttribute("aria-pressed", String(on));
      b.onclick = () => {
        fn();
        for (const c of row.children) {
          c.classList.toggle("on", c === b);
          c.setAttribute("aria-pressed", String(c === b));
        }
      };
      row.append(b);
    };
    if (kind === "filter") for (const [id, label] of FILTERS) add(label, fx.state.filter === id, () => fx.set({ filter: id }));
    if (kind === "beauty") {
      add("Tắt", !fx.state.soft, () => fx.set({ soft: false }));
      add("✨ Làm mịn da", fx.state.soft, () => fx.set({ soft: true }));
    }
    if (kind === "timer")
      for (const s of [0, 3, 10]) add(s ? s + " giây" : "Tắt", delay === s, () => {
        delay = s;
        $('[data-tool="timer"]').classList.toggle("on", !!s);
      });
    sheet.append(row);
    if (kind === "beauty" && !fx.faceSupported) {
      const n = document.createElement("p");
      n.className = "fx-note";
      n.textContent = "Sticker bám mặt cần trình duyệt hỗ trợ nhận diện khuôn mặt; nếu không sẽ hiện giữa khung.";
      sheet.append(n);
    }
    sheet.hidden = false;
  }
  for (const b of root.querySelectorAll(".tt-tool")) {
    if (b.dataset.tool === "flip") continue;
    b.onclick = () => openSheet(b.dataset.tool);
  }
  // Thời lượng
  for (const b of root.querySelectorAll(".tt-modes button"))
    b.onclick = () => {
      if (recorder?.state === "recording") return;
      maxSec = Number(b.dataset.sec);
      for (const c of root.querySelectorAll(".tt-modes button")) c.classList.toggle("on", c === b);
    };
  let recorder = null;
  let chunks = [];
  let started = 0;
  let tick = 0;
  let blobUrl = "";
  let pendingBlob = null;
  let counting = 0;
  let audioCtx = null;
  let musicNode = null;
  function close() {
    try {
      recorder?.state === "recording" && recorder.stop();
    } catch {}
    clearInterval(tick);
    clearInterval(counting);
    music.pause();
    music.removeAttribute("src");
    if (musicOwnUrl) URL.revokeObjectURL(musicOwnUrl);
    audioCtx?.close?.();
    fx.stop();
    raw.getTracks().forEach((t) => t.stop());
    if (blobUrl) URL.revokeObjectURL(blobUrl);
    root.remove();
    document.body.classList.remove("studio-open");
    document.removeEventListener("keydown", onKey);
  }
  const onKey = (e) => e.key === "Escape" && close();
  document.addEventListener("keydown", onKey);
  $(".tt-x").onclick = close;
  function setMode(m) {
    root.dataset.mode = m;
    for (const b of root.querySelectorAll(".tt-mode")) b.classList.toggle("on", b.dataset.mode === m);
    $(".tt-golive").hidden = m !== "live";
    sheet.hidden = true;
    if (m === "live") music.pause();
  }
  for (const b of root.querySelectorAll(".tt-mode")) b.onclick = () => recorder?.state !== "recording" && setMode(b.dataset.mode);
  $(".tt-golive").onsubmit = (e) => {
    e.preventDefault();
    const title = $(".tt-title").value.trim();
    if (!title) return $(".tt-title").focus();
    const state = { ...fx.state };
    close();
    onLive?.({ title, state });
  };
  setMode(startMode);
  $('[data-tool="flip"]').onclick = async () => {
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
  function review(blob) {
    pendingBlob = blob;
    if (blobUrl) URL.revokeObjectURL(blobUrl);
    blobUrl = URL.createObjectURL(blob);
    $(".tt-preview").src = blobUrl;
    $(".tt-post").hidden = false;
    $(".tt-preview").play().catch(() => {});
  }
  function stopRec() {
    if (recorder?.state === "recording") recorder.stop();
  }
  function startRec() {
    if (!mime) return notify("Trình duyệt này chưa quay được MP4. Hãy chọn video có sẵn bằng nút Tải lên.");
    sheet.hidden = true;
    chunks = [];
    let recStream = fx.stream;
    if (musicUrl) {
      // Trộn micro + nhạc vào một đường âm thanh
      audioCtx ||= new AudioContext();
      audioCtx.resume?.();
      const dest = audioCtx.createMediaStreamDestination();
      const mic = raw.getAudioTracks();
      if (mic.length) {
        const g = audioCtx.createGain();
        g.gain.value = 0.8;
        audioCtx.createMediaStreamSource(new MediaStream(mic)).connect(g).connect(dest);
      }
      musicNode ||= audioCtx.createMediaElementSource(music);
      musicNode.disconnect();
      musicNode.connect(dest);
      musicNode.connect(audioCtx.destination);
      music.currentTime = 0;
      music.play().catch(() => {});
      recStream = new MediaStream([...fx.stream.getVideoTracks(), ...dest.stream.getAudioTracks()]);
    }
    recorder = new MediaRecorder(recStream, { mimeType: mime, videoBitsPerSecond: 1_200_000, audioBitsPerSecond: 96_000 });
    recorder.ondataavailable = (e) => e.data.size && chunks.push(e.data);
    recorder.onstop = () => {
      clearInterval(tick);
      music.pause();
      root.classList.remove("recording");
      $(".tt-shutter").setAttribute("aria-label", "Bắt đầu quay");
      $(".tt-progress i").style.width = "0";
      $(".tt-time").textContent = "";
      if ((performance.now() - started) / 1000 < 1) return notify("Video quá ngắn. Quay ít nhất 1 giây.");
      review(new Blob(chunks, { type: "video/mp4" }));
    };
    recorder.start(1000);
    started = performance.now();
    root.classList.add("recording");
    $(".tt-shutter").setAttribute("aria-label", "Dừng quay");
    tick = setInterval(() => {
      const s = (performance.now() - started) / 1000;
      $(".tt-progress i").style.width = Math.min(100, (s / maxSec) * 100) + "%";
      $(".tt-time").textContent = Math.floor(s) + "s";
      if (s >= maxSec - 0.3) stopRec();
    }, 100);
  }
  $(".tt-shutter").onclick = () => {
    if (recorder?.state === "recording") return stopRec();
    if (counting) return;
    if (!delay) return startRec();
    let n = delay;
    const box = $(".tt-count");
    box.hidden = false;
    box.textContent = n;
    counting = setInterval(() => {
      n--;
      if (n > 0) return (box.textContent = n);
      clearInterval(counting);
      counting = 0;
      box.hidden = true;
      startRec();
    }, 1000);
  };
  // Tải video có sẵn từ máy
  $(".tt-gallery input").onchange = (e) => {
    const f = e.target.files[0];
    e.target.value = "";
    if (!f) return;
    if (f.size > 12 * 1024 * 1024) return notify("Video tối đa 12 MB.");
    review(f);
  };
  const back = () => {
    $(".tt-post").hidden = true;
    $(".tt-preview").pause();
  };
  $(".tt-back").onclick = back;
  $(".tt-retake").onclick = back;
  $(".tt-post").onsubmit = async (e) => {
    e.preventDefault();
    if (pendingBlob.size > 12 * 1024 * 1024) return notify("Video vượt 12 MB. Hãy quay ngắn hơn.");
    const btn = $(".tt-publish");
    btn.disabled = true;
    btn.textContent = "Đang đăng…";
    try {
      await onDone(pendingBlob, $(".tt-caption").value);
      close();
    } catch (err) {
      notify(err.message);
      btn.disabled = false;
      btn.textContent = "Đăng";
    }
  };
}
