// Nút ✨ Hiệu ứng trong màn hình Live (ẩn/hiện khay bộ lọc và sticker).
(() => {
  const live = document.getElementById("live"), controls = live?.querySelector(".controls");
  if (!controls) return;
  const fx = document.createElement("button");
  fx.type = "button";
  fx.className = "fx-toggle";
  fx.textContent = "Hiệu ứng";
  fx.setAttribute("aria-pressed", "false");
  fx.onclick = () => {
    const open = live.classList.toggle("fx-open");
    fx.setAttribute("aria-pressed", String(open));
  };
  controls.prepend(fx);
  // Nút ✕: người phát → hỏi rồi kết thúc live; người xem → rời phòng. Sau đó về trang Video.
  document.getElementById("live-browse")?.addEventListener("click", (e) => {
    if (live.hidden) return;
    const leave = document.getElementById("leave");
    if (/Kết thúc/.test(leave?.textContent || "")) {
      if (!confirm("Kết thúc buổi livestream?")) { e.preventDefault(); e.stopImmediatePropagation(); return; }
      leave.click();
    }
  }, true);
  // Video ngang (camera máy tính, luồng 16:9) thì hiện đủ khung thay vì cắt sát mặt.
  const video = document.getElementById("video");
  const fit = () => video.parentElement.classList.toggle("landscape", video.videoWidth > video.videoHeight);
  video?.addEventListener("loadedmetadata", fit);
  video?.addEventListener("resize", fit);
  new MutationObserver(() => { if (live.hidden) { live.classList.remove("fx-open"); fx.setAttribute("aria-pressed", "false"); } }).observe(live, { attributes: true, attributeFilter: ["hidden"] });
  // Bỏ trang danh sách "Trực tiếp": khi không ở trong phòng nào thì chuyển sang Video (đã có tab Trực tiếp).
  const panel = document.getElementById("live-panel"), lobby = document.getElementById("lobby");
  let timer = 0, busyUntil = 0;
  // Đang mở camera để lên sóng / đang vào phòng: chờ, không chuyển trang.
  document.getElementById("create")?.addEventListener("submit", () => { busyUntil = Date.now() + 20000; });
  const check = () => {
    clearTimeout(timer);
    if (panel.hidden || !live.hidden) return;
    const go = () => {
      if (panel.hidden || !live.hidden) return;
      if (Date.now() < busyUntil || document.getElementById("start")?.disabled) return void (timer = setTimeout(go, 1000));
      document.getElementById("live-browse")?.click();
    };
    timer = setTimeout(go, 2500);
  };
  new MutationObserver(check).observe(panel, { attributes: true, attributeFilter: ["hidden"] });
  new MutationObserver(() => { if (!live.hidden) busyUntil = 0; check(); }).observe(live, { attributes: true, attributeFilter: ["hidden"] });
  if (lobby) lobby.classList.add("lobby-gone");
  // Chẩn đoán tạm thời (chỉ người phát thấy): kích thước khung camera thật trên máy.
  const diag = document.createElement("small");
  diag.className = "live-diag";
  live.append(diag);
  const probe = document.createElement("video");
  probe.muted = true; probe.playsInline = true;
  setInterval(() => {
    const cam = window.kinnectLiveCamera, track = cam?.getVideoTracks?.()[0];
    if (live.hidden || !track || track.readyState !== "live") { diag.hidden = true; return; }
    if (probe.srcObject !== cam) { probe.srcObject = cam; probe.play().catch(() => {}); }
    const s = track.getSettings();
    diag.hidden = false;
    diag.textContent = (cam.kinnectVariant ? "cách " + cam.kinnectVariant + " · " : "") + "cam " + s.width + "×" + s.height + " · khung " + probe.videoWidth + "×" + probe.videoHeight + " · màn " + innerWidth + "×" + innerHeight;
  }, 1000);
})();
