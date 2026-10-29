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
  // A readable identity and an explicit playback recovery action.
  const heading = document.getElementById('room-title');
  const identity = () => heading.dataset.initial = (heading.textContent.trim() || 'K').slice(0,1).toUpperCase();
  new MutationObserver(identity).observe(heading, {childList:true,subtree:true,characterData:true});identity();
  const play = document.createElement('button');play.type='button';play.className='live-play';play.hidden=true;
  play.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true"><path d="m9 5 11 7-11 7V5Z"/></svg><span>Chạm để phát</span>';
  video.parentElement.append(play);
  function playback(){
    if(live.hidden){play.hidden=true;return;}
    const waiting=!video.srcObject || video.readyState<2;
    play.disabled=waiting;play.querySelector('span').textContent=waiting?'Đang nhận hình ảnh…':'Chạm để phát';
    play.hidden=!waiting&&!video.paused;
  }
  play.onclick=async()=>{try{await video.play();}catch{play.querySelector('span').textContent='Chạm để thử lại';}playback();};
  for(const event of ['loadedmetadata','loadeddata','playing','pause','emptied','waiting'])video.addEventListener(event,playback);
  new MutationObserver(playback).observe(live,{attributes:true,attributeFilter:['hidden']});
  // Keep accessible names and muted states in step with existing media controls.
  for(const id of ['mic','camera','gift','leave','report-live']){
    const button=document.getElementById(id);
    const sync=()=>{button.title=button.textContent.trim();button.setAttribute('aria-label',button.textContent.trim());if(id==='mic'||id==='camera')button.setAttribute('aria-pressed',String(button.textContent.trim().startsWith('Bật')));};
    new MutationObserver(sync).observe(button,{childList:true,characterData:true,subtree:true});sync();
  }
})();
