// Nút ✨ Hiệu ứng trong màn hình Live (ẩn/hiện khay bộ lọc và sticker).
(() => {
  const live = document.getElementById("live"), controls = live?.querySelector(".controls");
  if (!controls) return;
  const fx = document.createElement("button");
  fx.type = "button";
  fx.className = "fx-toggle";
  fx.textContent = "✨ Hiệu ứng";
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
})();
