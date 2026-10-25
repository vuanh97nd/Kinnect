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
  new MutationObserver(() => { if (live.hidden) { live.classList.remove("fx-open"); fx.setAttribute("aria-pressed", "false"); } }).observe(live, { attributes: true, attributeFilter: ["hidden"] });
})();
