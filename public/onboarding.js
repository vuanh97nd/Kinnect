const slides = [
  {
    art: "welcome",
    eyebrow: "CHÀO MỪNG ĐẾN KINNECT",
    title: "Kết nối đúng gu. Sống đúng mình.",
    text: "Bảng tin, video ngắn, khám phá bạn mới và live — tất cả trong một nơi an toàn dành cho bạn.",
  },
  {
    art: "feed",
    eyebrow: "BẢNG TIN",
    title: "Chia sẻ chuyện mỗi ngày",
    text: "Đăng suy nghĩ, khoảnh khắc và theo dõi những người bạn quan tâm. Bạn chọn ai được xem bài viết.",
  },
  {
    art: "video",
    eyebrow: "VIDEO NGẮN",
    title: "Lướt video, thả tim",
    text: "Video dọc toàn màn hình, vuốt để xem tiếp. Đăng video của bạn chỉ trong vài giây.",
  },
  {
    art: "discover",
    eyebrow: "KHÁM PHÁ",
    title: "Gặp người cùng tần số",
    text: "Gợi ý theo sở thích chung. Bật “Quanh đây” nếu muốn — vị trí luôn được làm tròn, không lộ chính xác.",
  },
  {
    art: "chat",
    eyebrow: "LIVE & TIN NHẮN",
    title: "Trò chuyện an toàn",
    text: "Nhắn tin riêng, xem và phát live. Chặn hoặc báo cáo bất kỳ lúc nào chỉ với một chạm.",
  },
];
// Minh họa giao diện mẫu (tên và nội dung chỉ để trình diễn)
const av = (letter, hue) =>
  '<span class="mk-av mk-h' + hue + '">' + letter + "</span>";
const art = {
  welcome:
    '<div class="ob-hero"><div class="ob-ring r1"></div><div class="ob-ring r2"></div>' +
    '<img class="ob-hero-logo" src="/kinnect-logo-v106.svg" alt="" />' +
    '<div class="ob-orbit o1">' + av("M", 260) + "</div>" +
    '<div class="ob-orbit o2">' + av("T", 330) + "</div>" +
    '<div class="ob-orbit o3">' + av("Q", 200) + "</div>" +
    '<div class="ob-orbit o4">' + av("H", 20) + "</div>" +
    '<div class="ob-orbit o5">' + av("L", 290) + "</div>" +
    '<div class="ob-hero-chip c1">👋 Xin chào!</div><div class="ob-hero-chip c2">♥ Cùng gu</div><div class="ob-hero-chip c3">● 2,1K đang online</div></div>',
  feed:
    '<div class="ob-phone"><div class="mk-bar"><b>Kinnect</b><i>♡</i><i>✉</i></div>' +
    '<div class="mk-stories">' + av("M", 260) + av("T", 330) + av("Q", 200) + av("H", 20) + "</div>" +
    '<div class="mk-post"><div class="mk-head">' + av("M", 260) + "<p><b>Minh Anh</b><small>2 phút · Thành viên</small></p></div>" +
    '<p class="mk-text">Sáng nay ghé quán cà phê mới ở phố cổ, view đẹp lắm ☕</p><div class="mk-photo"></div>' +
    '<div class="mk-actions"><span>♥ 128</span><span>💬 24</span><span>↗ Chia sẻ</span></div></div></div>' +
    '<div class="ob-float f1">♥ +128 lượt thích</div><div class="ob-float f2">' + av("T", 330) + " Tuấn đã theo dõi bạn</div>",
  video:
    '<div class="ob-phone ob-dark"><div class="mk-tabs"><span>Đang theo dõi</span><b>Dành cho bạn</b></div>' +
    '<div class="mk-glow"></div><div class="mk-play">▶</div>' +
    '<div class="mk-side">' + av("Q", 200) + '<i class="on">♥<small>2,4K</small></i><i>💬<small>186</small></i><i>↗<small>Chia sẻ</small></i></div>' +
    '<div class="mk-cap"><b>@quang.dance</b><p>Thử thách nhảy cuối tuần 🔥 #kinnect</p><span class="mk-sound">♪ Nhạc gốc · quang.dance</span></div>' +
    '<div class="mk-progress"><i></i></div></div>' +
    '<div class="ob-float f1">🔥 Xu hướng hôm nay</div><div class="ob-float f2">▶ 12,8K lượt xem</div>',
  discover:
    '<div class="ob-phone"><div class="mk-bar"><b>Khám phá</b></div><div class="mk-chips"><b>Cùng sở thích</b><span>Quanh đây</span></div>' +
    '<div class="mk-grid">' +
    '<div class="mk-tile mk-h260"><em>● Online</em><p><b>Hải, 26</b><small>Du lịch · Nhạc</small></p></div>' +
    '<div class="mk-tile mk-h330"><em>&lt; 5 km</em><p><b>Linh, 24</b><small>Cà phê · Phim</small></p></div>' +
    '<div class="mk-tile mk-h200"><p><b>Đức, 29</b><small>Gym · Ẩm thực</small></p></div>' +
    '<div class="mk-tile mk-h20"><em>● Online</em><p><b>Vy, 22</b><small>Sách · Vẽ</small></p></div></div></div>' +
    '<div class="ob-float f1">✨ 3 sở thích chung</div><div class="ob-float f2">📍 Vị trí được làm tròn</div>',
  chat:
    '<div class="ob-phone"><div class="mk-chat-head">' + av("H", 20) + '<p><b>Hà My</b><small>● Đang hoạt động</small></p></div>' +
    '<div class="mk-msgs"><p class="in">Chào bạn! Thấy bạn cũng thích leo núi 🏔️</p><p class="out">Đúng rồi! Cuối tuần này mình định đi Ba Vì</p><p class="in">Cho mình đi cùng với nhé 😄</p>' +
    '<p class="typing"><i></i><i></i><i></i></p></div><div class="mk-input"><span>Nhắn tin…</span><b>➤</b></div></div>' +
    '<div class="ob-float f1"><span class="mk-live">● LIVE</span> 1,2K người đang xem</div><div class="ob-float f2">🛡️ Chặn & báo cáo 1 chạm</div>',
};

// Hiện mỗi khi màn hình đăng nhập xuất hiện: lần đầu mở app khi chưa đăng nhập và sau mỗi lần đăng xuất.
function openOnboarding() {
  if (document.querySelector(".onboarding")) return;
  const params = new URL(location.href).searchParams;
  // Không che màn hoàn tất đăng ký / thông báo lỗi khi vừa quay về từ Google hoặc Facebook.
  if (params.get("view") === "live" || params.get("oauth") || params.get("oauth_error")) return;
  const root = document.createElement("div");
  root.className = "onboarding";
  root.setAttribute("role", "dialog");
  root.setAttribute("aria-modal", "true");
  root.setAttribute("aria-label", "Giới thiệu Kinnect");
  root.innerHTML =
    '<div class="ob-blob b1"></div><div class="ob-blob b2"></div>' +
    '<header class="ob-top"><a class="ob-home" href="https://kinnect.io.vn/" aria-label="Về trang chủ Kinnect">←</a><img src="/kinnect-logo-v106.svg" alt="" /><strong>Kinnect</strong><a class="ob-site ob-get" href="' + (/iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1) ? '/install-ios' : '/download/android') + '" target="_blank" rel="noopener">⬇ Tải app</a></header>' +
    '<div class="ob-track" tabindex="0" aria-roledescription="carousel"></div>' +
    '<div class="ob-dots" role="tablist" aria-label="Chọn trang giới thiệu"></div>' +
    '<div class="ob-actions"><button type="button" class="ob-start">Bắt đầu ngay</button><button type="button" class="ob-login">Tôi đã có tài khoản</button></div>';
  const track = root.querySelector(".ob-track");
  const dots = root.querySelector(".ob-dots");
  slides.forEach((s, i) => {
    const slide = document.createElement("article");
    slide.className = "ob-slide";
    slide.setAttribute("aria-roledescription", "slide");
    slide.setAttribute("aria-label", i + 1 + " / " + slides.length);
    slide.innerHTML = '<div class="ob-art">' + art[s.art] + "</div>";
    const eyebrow = document.createElement("p");
    eyebrow.className = "ob-eyebrow";
    eyebrow.textContent = s.eyebrow;
    const h = document.createElement("h2");
    h.textContent = s.title;
    const p = document.createElement("p");
    p.className = "ob-text";
    p.textContent = s.text;
    const copy = document.createElement("div");
    copy.className = "ob-copy";
    copy.append(eyebrow, h, p);
    slide.append(copy);
    track.append(slide);
    const dot = document.createElement("button");
    dot.type = "button";
    dot.setAttribute("role", "tab");
    dot.setAttribute("aria-label", "Trang " + (i + 1));
    dot.onclick = () => track.scrollTo({ left: i * track.clientWidth, behavior: "smooth" });
    dots.append(dot);
  });
  const current = () => Math.round(track.scrollLeft / Math.max(1, track.clientWidth));
  const paint = () => {
    const n = current();
    [...track.children].forEach((s, i) => s.classList.toggle("is-active", i === n));
    [...dots.children].forEach((d, i) => d.setAttribute("aria-selected", String(i === n)));
    root.querySelector(".ob-start").textContent = n === slides.length - 1 ? "Tạo tài khoản miễn phí" : "Tiếp tục";
    root.querySelector(".ob-start").dataset.last = String(n === slides.length - 1);
  };
  track.addEventListener("scroll", () => requestAnimationFrame(paint), { passive: true });
  track.addEventListener("keydown", (e) => {
    if (e.key === "ArrowRight") track.scrollBy({ left: track.clientWidth, behavior: "smooth" });
    if (e.key === "ArrowLeft") track.scrollBy({ left: -track.clientWidth, behavior: "smooth" });
  });
  const close = (modeButton) => {
    root.remove();
    document.body.classList.remove("ob-open");
    if (modeButton === "register-mode")
      document.getElementById("auth").classList.remove("has-recent");
    if (modeButton) document.getElementById(modeButton)?.click();
    document.getElementById("username")?.focus();
  };
  root.querySelector(".ob-skip") && (root.querySelector(".ob-skip").onclick = () => close("login-mode"));
  root.querySelector(".ob-login").onclick = () => close("login-mode");
  root.querySelector(".ob-start").onclick = (e) => {
    if (e.currentTarget.dataset.last === "true") close("register-mode");
    else track.scrollBy({ left: track.clientWidth, behavior: "smooth" });
  };
  document.body.classList.add("ob-open");
  document.body.append(root);
  paint();
}
// Giống Facebook: máy đã từng đăng nhập thì hiện "Đăng nhập gần đây" thay vì màn giới thiệu.
// Chỉ lưu tên đăng nhập và tên hiển thị trên máy này, không lưu mật khẩu.
const ACCOUNTS_KEY = "kinnect-recent-accounts";
function recentAccounts() {
  try {
    const list = JSON.parse(localStorage.getItem(ACCOUNTS_KEY) || "[]");
    return Array.isArray(list) ? list.slice(0, 5) : [];
  } catch {
    return [];
  }
}
function saveAccounts(list) {
  try {
    localStorage.setItem(ACCOUNTS_KEY, JSON.stringify(list.slice(0, 5)));
  } catch {}
}
function rememberAccount(user) {
  if (!user?.username) return;
  const rest = recentAccounts().filter((a) => a.username !== user.username);
  saveAccounts([{ username: user.username, name: user.name || user.username }, ...rest]);
}
let quickAccounts=[];
function showRecent() {
  const auth = document.getElementById("auth");
  auth.querySelector(".recent-accounts")?.remove();
  const stored=recentAccounts();
  const accounts=[...quickAccounts,...stored.filter(item=>!quickAccounts.some(q=>q.username===item.username))].slice(0,5);
  if (!accounts.length) {
    auth.classList.remove("has-recent");
    return false;
  }
  const box = document.createElement("div");
  box.className = "recent-accounts";
  const title = document.createElement("h2");
  title.textContent = "Đăng nhập gần đây";
  const hint = document.createElement("p");
  hint.className = "muted";
  hint.textContent = "Chạm vào tài khoản để đăng nhập.";
  const list = document.createElement("div");
  list.className = "recent-list";
  for (const a of accounts) {
    const item = document.createElement("div");
    item.className = "recent-item";
    const pick = document.createElement("button");
    pick.type = "button";
    pick.className = "recent-pick";
    pick.setAttribute("aria-label", "Đăng nhập với " + a.name);
    const letter = document.createElement("span");
    letter.className = "recent-avatar";
    letter.textContent = (a.name || "?").slice(0, 1).toUpperCase();
    const label = document.createElement("span");
    label.className = "recent-name";
    const strong = document.createElement("b");
    strong.textContent = a.name;
    const small = document.createElement("small");
    small.textContent = "@" + a.username;
    label.append(strong, small);
    pick.append(letter, label);
    if(a.id){const quick=document.createElement("small");quick.textContent="Chạm để đăng nhập";quick.className="recent-quick-hint";label.append(quick);}
    pick.onclick = () => {
      if(a.id){pick.disabled=true;window.dispatchEvent(new CustomEvent("kinnect-quick-login",{detail:a.id}));setTimeout(()=>{pick.disabled=false;},2000);return;}
      auth.classList.remove("has-recent");
      document.getElementById("login-mode")?.click();
      document.getElementById("username").value = a.username;
      document.getElementById("password").focus();
    };
    const remove = document.createElement("button");
    remove.type = "button";
    remove.className = "recent-remove";
    remove.textContent = "×";
    remove.setAttribute("aria-label", "Gỡ " + a.name + " khỏi thiết bị này");
    remove.onclick = async () => {
      if(a.id){try{const r=await fetch("/api/remembered/"+a.id,{method:"DELETE",credentials:"same-origin",headers:{"Content-Type":"application/json"},body:"{}"});if(!r.ok)return;quickAccounts=quickAccounts.filter(q=>q.id!==a.id);}catch{return;}}
      saveAccounts(recentAccounts().filter((x) => x.username !== a.username));
      if (!showRecent()) document.getElementById("username").focus();
    };
    item.append(pick, remove);
    list.append(item);
  }
  const other = document.createElement("button");
  other.type = "button";
  other.className = "recent-other";
  other.textContent = "Đăng nhập tài khoản khác";
  other.onclick = () => {
    auth.classList.remove("has-recent");
    document.getElementById("login-mode")?.click();
    document.getElementById("username").value = "";
    document.getElementById("username").focus();
  };
  const create = document.createElement("button");
  create.type = "button";
  create.className = "recent-create";
  create.textContent = "Tạo tài khoản mới";
  create.onclick = () => {
    auth.classList.remove("has-recent");
    document.getElementById("register-mode")?.click();
    document.getElementById("username").value = "";
    document.getElementById("username").focus();
  };
  box.append(title, hint, list, other, create);
  (auth.querySelector(".auth-top") || auth.querySelector(".auth-logo")).after(box);
  auth.classList.add("has-recent");
  return true;
}
// Bắt buộc: mỗi lần vào trang khi chưa đăng nhập (kể cả sau khi đăng xuất) đều hiện giới thiệu trước,
// đóng giới thiệu xong mới tới "Đăng nhập gần đây" hoặc form đăng nhập.
function onAuthShown() {
  showRecent();
  fetch("/api/remembered",{credentials:"same-origin",cache:"no-store"}).then(r=>r.ok?r.json():{accounts:[]}).then(({accounts})=>{quickAccounts=accounts||[];showRecent();if(quickAccounts.length){document.querySelector(".onboarding")?.remove();document.body.classList.remove("ob-open");}}).catch(()=>{});
  openOnboarding();
}
window.addEventListener("kinnect-auth-shown", onAuthShown);
window.addEventListener("kinnect-logged-in", (e) => rememberAccount(e.detail));
if (window.kinnectAuthShown) onAuthShown();

window.addEventListener("kinnect-quick-login-failed",()=>{document.getElementById("auth").classList.remove("has-recent");document.getElementById("login-mode")?.click();document.getElementById("password")?.focus();});

// Nút ← trên màn đăng nhập/đăng ký: quay lại màn chào mừng (trang trước).
document.querySelector(".auth-back")?.addEventListener("click", () => openOnboarding());
