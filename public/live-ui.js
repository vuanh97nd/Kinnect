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
})();
