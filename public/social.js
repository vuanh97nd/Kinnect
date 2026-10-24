import { connectLive, disconnectLive } from "./app.js";
const $ = (id) => document.getElementById(id);
let me = null,
  mode = "login",
  tab = "feed",
  timer = null,
  notificationTimer = null;
const node = (tag, text, cls) => {
  const e = document.createElement(tag);
  if (text !== undefined) e.textContent = text;
  if (cls) e.className = cls;
  return e;
};
// Thông báo nhỏ tự ẩn sau vài giây
let noticeTimer = null;
const status = (text) => {
  const n = $("notice");
  n.textContent = text;
  n.classList.toggle("show", !!text);
  clearTimeout(noticeTimer);
  if (text) noticeTimer = setTimeout(() => n.classList.remove("show"), 4500);
};
const action = (text, fn, cls = "secondary") => {
  const b = node("button", text, cls);
  b.type = "button";
  b.onclick = async () => {
    b.disabled = true;
    try {
      await fn();
    } catch (e) {
      status(e.message);
    } finally {
      b.disabled = false;
    }
  };
  return b;
};
async function api(path, method = "GET", data) {
  const r = await fetch("/api" + path, {
    method,
    credentials: "same-origin",
    headers: data === undefined ? {} : { "Content-Type": "application/json" },
    body: data === undefined ? undefined : JSON.stringify(data),
  });
  const result = await r.json();
  if (!r.ok) {
    if (r.status === 401 && me) {
      me = null;
      disconnectLive();
      showAuth();
    }
    throw Error(result.error || "Không thể thực hiện yêu cầu.");
  }
  return result;
}
function showAuth() {
  clearInterval(timer);
  clearInterval(notificationTimer);
  $("auth").hidden = false;
  $("app").hidden = true;
  $("password").value = "";
  window.kinnectAuthShown = true;
  setupSocialLogin();
  handleOAuthReturn();
  window.dispatchEvent(new Event("kinnect-auth-shown"));
}
function authMode(value) {
  mode = value;
  const register = mode === "register";
  $("register-fields").hidden = !register;
  $("register-fields").disabled = !register;
  $("auth-submit").textContent = register ? "Tạo tài khoản" : "Đăng nhập";
  $("password").autocomplete = register ? "new-password" : "current-password";
  $("auth-title").textContent = register ? "Tạo tài khoản Kinnect" : "Chào mừng trở lại";
  $("auth-sub").textContent = register
    ? "Miễn phí, chỉ mất chưa tới một phút."
    : "Đăng nhập để tiếp tục với Kinnect.";
  for (const [id, on] of [["login-mode", !register], ["register-mode", register]]) {
    $(id).classList.toggle("active", on);
    $(id).setAttribute("aria-pressed", String(on));
  }
  const sw = $("auth-switch");
  sw.firstChild.textContent = register ? "Đã có tài khoản? " : "Chưa có tài khoản? ";
  sw.querySelector("button").textContent = register ? "Đăng nhập" : "Tạo tài khoản mới";
  sw.querySelector("button").dataset.mode = register ? "login" : "register";
  $("forgot-link").hidden = register;
  $("auth-status").textContent = "";
}
$("login-mode").onclick = () => authMode("login");
$("register-mode").onclick = () => authMode("register");
$("auth-switch").querySelector("button").onclick = (e) =>
  authMode(e.currentTarget.dataset.mode);
// ---- Quên mật khẩu ----
function forgotView(open) {
  $("forgot-view").hidden = !open;
  $("auth-form").hidden = open;
  document.querySelector("#auth .auth-tabs").hidden = open;
  $("auth-switch").hidden = open;
  if (open) $("social-login").hidden = true;
  else setupSocialLogin();
  $("auth-title").textContent = open ? "Quên mật khẩu?" : "Chào mừng trở lại";
  $("auth-sub").textContent = open
    ? "Gửi yêu cầu, quản trị viên sẽ giúp bạn lấy lại tài khoản."
    : "Đăng nhập để tiếp tục với Kinnect.";
  $("forgot-form").hidden = false;
  $("forgot-done").hidden = true;
  $("forgot-status").textContent = "";
  if (open) {
    $("forgot-username").value = $("username").value;
    ($("forgot-username").value ? $("forgot-contact") : $("forgot-username")).focus();
  } else authMode("login");
}
$("forgot-link").onclick = () => forgotView(true);
$("forgot-back").onclick = () => forgotView(false);
$("forgot-done-back").onclick = () => forgotView(false);
$("forgot-form").onsubmit = async (e) => {
  e.preventDefault();
  $("forgot-submit").disabled = true;
  $("forgot-status").textContent = "";
  try {
    await api("/password-reset", "POST", {
      username: $("forgot-username").value,
      contact: $("forgot-contact").value,
      note: $("forgot-note").value,
    });
    $("forgot-form").hidden = true;
    $("forgot-done").hidden = false;
  } catch (error) {
    $("forgot-status").textContent = error.message;
  } finally {
    $("forgot-submit").disabled = false;
  }
};
// ---- Đăng nhập bằng Google / Facebook ----
const OAUTH_ERRORS = {
  cancelled: "Bạn đã huỷ đăng nhập.",
  state: "Phiên đăng nhập không hợp lệ. Hãy thử lại.",
  provider: "Không kết nối được với Google/Facebook. Hãy thử lại sau.",
  suspended: "Tài khoản này đang bị tạm khoá.",
};
async function setupSocialLogin() {
  try {
    const { providers } = await api("/oauth/providers");
    $("google-login").hidden = !providers.includes("google");
    $("facebook-login").hidden = !providers.includes("facebook");
    $("social-login").hidden = !providers.length;
  } catch {
    $("social-login").hidden = true;
  }
}
function oauthView(open) {
  $("oauth-form").hidden = !open;
  for (const id of ["auth-form", "auth-switch"]) $(id).hidden = open;
  document.querySelector("#auth .auth-tabs").hidden = open;
  if (open) $("social-login").hidden = true;
}
async function handleOAuthReturn() {
  const params = new URL(location.href).searchParams;
  const error = params.get("oauth_error");
  const ticket = params.get("ticket");
  if (error || params.get("oauth")) history.replaceState(null, "", "/");
  if (error) $("auth-status").textContent = OAUTH_ERRORS[error] || OAUTH_ERRORS.provider;
  if (params.get("oauth") !== "complete" || !ticket) return;
  try {
    const p = await api("/oauth/pending?ticket=" + encodeURIComponent(ticket));
    oauthView(true);
    $("auth-title").textContent = "Chỉ còn một bước";
    $("auth-sub").textContent = "Xác nhận thông tin để tạo tài khoản Kinnect.";
    $("oauth-hello").textContent =
      "Đã xác thực qua " + (p.provider === "google" ? "Google" : "Facebook") + (p.name ? " · " + p.name : "");
    $("oauth-name").value = p.name;
    $("oauth-username").value = p.suggestedUsername;
    $("oauth-form").onsubmit = async (e) => {
      e.preventDefault();
      $("oauth-submit").disabled = true;
      $("oauth-status").textContent = "";
      try {
        await api("/oauth/complete", "POST", {
          ticket,
          username: $("oauth-username").value,
          name: $("oauth-name").value,
          agree18: $("oauth-agree").checked,
        });
        me = (await api("/me")).user;
        oauthView(false);
        await enter();
      } catch (err) {
        $("oauth-status").textContent = err.message;
      } finally {
        $("oauth-submit").disabled = false;
      }
    };
  } catch (err) {
    $("auth-status").textContent = err.message;
  }
}
$("oauth-cancel").onclick = () => {
  oauthView(false);
  authMode("login");
  setupSocialLogin();
};
$("pw-toggle").onclick = () => {
  const show = $("password").type === "password";
  $("password").type = show ? "text" : "password";
  $("pw-toggle").textContent = show ? "Ẩn" : "Hiện";
  $("pw-toggle").setAttribute("aria-label", show ? "Ẩn mật khẩu" : "Hiện mật khẩu");
  $("pw-toggle").setAttribute("aria-pressed", String(show));
};
$("auth-form").onsubmit = async (e) => {
  e.preventDefault();
  $("auth-submit").disabled = true;
  try {
    const result = await api("/" + mode, "POST", {
      username: $("username").value,
      password: $("password").value,
      name: $("display-name").value,
      agree18: $("agree").checked,
    });
    me = result.user;
    $("password").value = "";
    await enter();
  } catch (error) {
    $("auth-status").textContent = error.message;
  } finally {
    $("auth-submit").disabled = false;
  }
};
async function enter() {
  $("admin-tab").hidden = me.role !== "admin";
  $("auth").hidden = true;
  $("app").hidden = false;
  $("name").value = me.name;
  paintMe();
  window.dispatchEvent(new CustomEvent("kinnect-logged-in", { detail: me }));
  connectLive();
  status("Chào " + me.name + "! 👋");
  await navigate(
    new URL(location.href).searchParams.get("view") === "live"
      ? "live"
      : "feed",
  );
  if (new URL(location.href).searchParams.get("view") === "live")
    document.body.classList.add("live-only");
  rail().catch(() => {});
  clearInterval(notificationTimer);
  notificationTimer = setInterval(() => refreshUnread().catch(() => {}), 15000);
  await refreshUnread();
}
// Ảnh đại diện và tên trên nút tài khoản
function paintMe() {
  const old = $("me-avatar");
  const fresh = avatar(me);
  fresh.id = "me-avatar";
  old.replaceWith(fresh);
  $("me-name").textContent = me.name;
  $("me-username").textContent = "@" + me.username;
}
// ---- Menu tài khoản ----
const meBtn = $("me-btn"),
  mePanel = $("me-panel");
function menu(open) {
  mePanel.hidden = !open;
  meBtn.setAttribute("aria-expanded", String(open));
}
meBtn.onclick = (e) => {
  e.stopPropagation();
  menu(mePanel.hidden);
};
document.addEventListener("click", (e) => {
  if (!mePanel.hidden && !e.target.closest(".me-menu")) menu(false);
});
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape" && !mePanel.hidden) {
    menu(false);
    meBtn.focus();
  }
});
for (const b of mePanel.querySelectorAll("[data-go]"))
  b.onclick = () => {
    menu(false);
    if (b.dataset.go === "settings") navigate("profile", { settings: true });
    else navigate("profile");
  };
$("logout").onclick = async () => {
  menu(false);
  try {
    await api("/logout", "POST", {});
    me = null;
    disconnectLive();
    showAuth();
  } catch (e) {
    status(e.message);
  }
};
// Ô tìm kiếm trên thanh trên cùng → Khám phá
$("top-search").onsubmit = (e) => {
  e.preventDefault();
  navigate("discover", { q: $("top-search-input").value });
};
for (const button of document.querySelectorAll("[data-tab]"))
  button.onclick = () =>
    navigate(button.dataset.tab).catch((e) => status(e.message));
// Khung xám nhấp nháy trong lúc tải
function skeleton(kind) {
  const box = node("div", undefined, "skeleton-list");
  box.setAttribute("aria-hidden", "true");
  for (let i = 0; i < (kind === "grid" ? 4 : 3); i++)
    box.append(node("div", undefined, "skeleton " + (kind === "grid" ? "sk-tile" : "sk-card")));
  if (kind === "grid") box.classList.add("grid");
  return box;
}
async function navigate(value, opts = {}) {
  clearInterval(timer);
  timer = null;
  tab = value;
  menu(false);
  document.body.dataset.view = value;
  for (const b of document.querySelectorAll("[data-tab]"))
    b.classList.toggle("active", b.dataset.tab === value && !opts.user);
  $("social-panel").hidden = value === "live";
  $("live-panel").hidden = value !== "live";
  const panel = $("social-panel");
  if (value === "live") return;
  panel.replaceChildren(skeleton(value === "discover" ? "grid" : "list"));
  const view = node("div", undefined, "view view-" + value);
  try {
    if (value === "feed") await feed(view);
    if (value === "discover") await discover(view, opts.q || "");
    if (value === "shorts") await shorts(view);
    if (value === "profile") await profile(view, opts);
    if (value === "inbox") await inbox(view);
    if (value === "notifications") await notifications(view);
    if (value === "admin") await adminPanel(view);
  } catch (e) {
    status(e.message);
    view.append(empty("⚠️", "Không tải được dữ liệu", "Kiểm tra kết nối rồi thử lại."));
  }
  if (tab === value) panel.replaceChildren(view);
  window.scrollTo(0, 0);
}
function empty(icon, title, text) {
  const box = node("div", undefined, "empty-state");
  box.append(node("div", icon, "empty-ico"), node("h3", title), node("p", text, "muted"));
  return box;
}
// Màu ảnh đại diện mặc định theo từng người (8 tông, không dùng style nội tuyến)
const hue = (id = "") => {
  let h = 0;
  for (const c of id) h = (h * 31 + c.charCodeAt(0)) >>> 0;
  return "hue-" + (h % 8);
};
function avatar(u) {
  if (!u.avatar) {
    const e = node(
      "span",
      (u.name || "?").slice(0, 1).toUpperCase(),
      "avatar fallback " + hue(u.id || u.username),
    );
    e.setAttribute("aria-hidden", "true");
    return e;
  }
  const img = node("img");
  img.src = u.avatar;
  img.alt = "Ảnh của " + u.name;
  img.className = "avatar";
  return img;
}
// Menu "⋯" dùng chung cho thẻ người, bài viết, tin nhắn
function more(items, label = "Tùy chọn khác") {
  const wrap = node("details", undefined, "more");
  const sum = node("summary", "⋯");
  sum.setAttribute("aria-label", label);
  const list = node("div", undefined, "more-list");
  for (const [text, fn, cls] of items) {
    const b = action(text, async () => {
      wrap.open = false;
      await fn();
    }, cls || "");
    list.append(b);
  }
  wrap.append(sum, list);
  return wrap;
}
function personLink(u, extraClass = "") {
  const b = node("button", undefined, "person-link " + extraClass);
  b.type = "button";
  b.setAttribute("aria-label", "Xem trang của " + u.name);
  b.append(avatar(u));
  b.onclick = () => navigate("profile", { user: u.id });
  return b;
}
function userCard(u) {
  const card = node("article", undefined, "social-card person-tile");
  const photo = node("div", undefined, "tile-photo " + hue(u.id));
  photo.append(avatar(u));
  if (u.distanceBand) photo.append(node("span", u.distanceBand, "tile-chip"));
  const head = node("button", undefined, "tile-name");
  head.type = "button";
  head.append(node("h3", u.name), node("p", "@" + u.username, "muted"));
  head.onclick = () => navigate("profile", { user: u.id });
  photo.append(head);
  photo.append(
    more([
      ["Chặn", async () => {
        if (!confirm("Chặn " + u.name + "? Hai bên sẽ không thấy nhau trong khám phá, bảng tin, chat và phòng live.")) return;
        await api("/users/" + u.id + "/block", "POST", {});
        status("Đã chặn " + u.name + ".");
        await navigate(tab);
      }],
      ["Báo cáo", () => report("user", u.id)],
    ]),
  );
  card.append(photo, node("p", u.bio || "Một người bạn mới đang chờ câu chuyện của bạn.", "tile-bio"));
  const tags = node("div", undefined, "tags");
  u.interests.slice(0, 4).forEach((v) => tags.append(node("span", v)));
  card.append(tags);
  if (u.score) card.append(node("p", u.score + " sở thích chung", "match"));
  const buttons = node("div", undefined, "card-actions");
  buttons.append(
    action(u.following ? "Bỏ theo dõi" : "Theo dõi", async () => {
      await api("/users/" + u.id + "/follow", u.following ? "DELETE" : "POST", {});
      await navigate(tab);
    }, u.following ? "secondary" : "follow"),
    action("Nhắn tin", () => openChat(u)),
  );
  card.append(buttons);
  return card;
}
async function report(targetType, targetId) {
  const reason = prompt(
    "Mô tả vấn đề (ít nhất 5 ký tự). Báo cáo sẽ được quản trị viên xem xét.",
  );
  if (!reason) return;
  await api("/reports", "POST", { targetType, targetId, reason });
  status("Đã gửi báo cáo. Nếu cần, hãy chặn người dùng này.");
}
async function discover(panel, q = "") {
  const head = node("div", undefined, "view-head");
  head.append(
    node("h2", "Khám phá"),
    node("p", "Gợi ý theo sở thích chung. Vị trí chính xác không bao giờ được chia sẻ.", "muted"),
  );
  panel.append(head);
  let nearby = false;
  const chips = node("div", undefined, "chips");
  const chip = (label, value) => {
    const b = node("button", label, value === nearby ? "chip active" : "chip");
    b.type = "button";
    b.onclick = () => {
      nearby = value;
      for (const c of chips.children) c.classList.toggle("active", c === b);
      load().catch((e) => {
        list.replaceChildren(empty("📍", "Chưa bật Quanh đây", e.message));
      });
    };
    return b;
  };
  chips.append(chip("Cùng sở thích", false), chip("Quanh đây", true));
  const form = node("form", undefined, "search-bar");
  const search = node("input");
  search.type = "search";
  search.value = q;
  search.placeholder = "Tìm tên hoặc sở thích…";
  search.setAttribute("aria-label", "Tìm bạn");
  const button = node("button", "Tìm");
  form.append(search, button);
  panel.append(chips, form);
  const list = node("div", undefined, "people-grid");
  panel.append(list);
  async function load() {
    const { users } = await api(
      "/discover?q=" + encodeURIComponent(search.value) + (nearby ? "&nearby=1" : ""),
    );
    list.replaceChildren();
    users.forEach((u) => list.append(userCard(u)));
    if (!users.length)
      list.append(empty("🔎", "Chưa tìm thấy ai", "Thử từ khóa khác, bổ sung sở thích hoặc mời bạn bè tham gia."));
  }
  form.onsubmit = (e) => {
    e.preventDefault();
    load().catch((e) => status(e.message));
  };
  await load();
}
function timeAgo(t) {
  const m = Math.round((Date.now() - t) / 60000);
  if (m < 1) return "Vừa xong";
  if (m < 60) return m + " phút";
  if (m < 1440) return Math.round(m / 60) + " giờ";
  if (m < 10080) return Math.round(m / 1440) + " ngày";
  return new Date(t).toLocaleDateString("vi-VN");
}
const clock = (t) =>
  new Date(t).toLocaleTimeString("vi-VN", { hour: "2-digit", minute: "2-digit" });
async function stories(panel) {
  const strip = node("div", undefined, "stories");
  strip.setAttribute("aria-label", "Gợi ý kết nối");
  const mine = node("button", undefined, "story story-me");
  mine.type = "button";
  mine.append(avatar(me), node("span", "Lên sóng"));
  mine.onclick = () => navigate("live");
  strip.append(mine);
  panel.append(strip);
  const { users } = await api("/discover?q=");
  for (const u of users.slice(0, 12)) {
    const b = node("button", undefined, "story");
    b.type = "button";
    b.setAttribute("aria-label", "Xem trang của " + u.name);
    b.append(avatar(u), node("span", u.name));
    b.onclick = () => navigate("profile", { user: u.id });
    strip.append(b);
  }
}
function composer(panel) {
  const form = node("form", undefined, "social-card composer");
  const row = node("div", undefined, "composer-row");
  const input = node("textarea");
  input.placeholder = me.name + " ơi, bạn đang nghĩ gì?";
  input.maxLength = 2000;
  input.required = true;
  input.rows = 2;
  input.setAttribute("aria-label", "Nội dung bài viết");
  row.append(avatar(me), input);
  const visibility = node("select");
  visibility.setAttribute("aria-label", "Ai có thể xem bài viết");
  for (const [value, label] of [
    ["public", "🌐 Mọi thành viên"],
    ["followers", "👥 Người theo dõi"],
  ]) {
    const o = node("option", label);
    o.value = value;
    visibility.append(o);
  }
  const submit = node("button", "Chia sẻ");
  const tools = node("div", undefined, "composer-tools");
  const video = node("button", "🎬 Video", "ghost");
  video.type = "button";
  video.onclick = () => navigate("shorts");
  const live = node("button", "🔴 Live", "ghost");
  live.type = "button";
  live.onclick = () => navigate("live");
  tools.append(video, live, visibility, submit);
  form.append(row, tools);
  form.onsubmit = async (e) => {
    e.preventDefault();
    submit.disabled = true;
    try {
      await api("/posts", "POST", { body: input.value, visibility: visibility.value });
      status("Đã đăng bài.");
      await navigate("feed");
    } catch (e) {
      status(e.message);
      submit.disabled = false;
    }
  };
  panel.append(form);
}
function postCard(p) {
  const card = node("article", undefined, "social-card post");
  const head = node("div", undefined, "post-head");
  const who = node("div", undefined, "post-who");
  const name = node("button", p.author.name, "name-link");
  name.type = "button";
  name.onclick = () => navigate("profile", { user: p.author.id });
  who.append(
    name,
    node("span", timeAgo(p.created) + " · " + (p.visibility === "followers" ? "👥 Người theo dõi" : "🌐 Mọi thành viên"), "meta"),
  );
  const options =
    p.user_id === me.id
      ? [["Xóa bài", async () => {
          if (!confirm("Xóa bài viết này?")) return;
          await api("/posts/" + p.id, "DELETE", {});
          status("Đã xóa bài viết.");
          card.remove();
        }, "danger-item"]]
      : [["Báo cáo bài viết", () => report("post", p.id)]];
  head.append(personLink(p.author), who, more(options, "Tùy chọn bài viết"));
  card.append(head, node("p", p.body, "post-body"));
  let likes = p.likes || 0,
    liked = !!p.liked,
    count = p.comments || 0;
  const stats = node("div", undefined, "post-stats");
  const paintStats = () => {
    stats.textContent = "";
    if (likes) stats.append(node("span", "♥ " + likes, "likes"));
    if (count) stats.append(node("span", count + " bình luận"));
    stats.hidden = !likes && !count;
  };
  paintStats();
  const bar = node("div", undefined, "post-actions");
  const like = node("button", undefined, "act like");
  like.type = "button";
  const paintLike = () => {
    like.textContent = liked ? "♥ Đã thích" : "♡ Thích";
    like.classList.toggle("on", liked);
    like.setAttribute("aria-pressed", String(liked));
  };
  paintLike();
  like.onclick = async () => {
    like.disabled = true;
    try {
      const r = await api("/posts/" + p.id + "/like", liked ? "DELETE" : "POST", {});
      likes = r.likes;
      liked = r.liked;
      paintLike();
      paintStats();
    } catch (e) {
      status(e.message);
    } finally {
      like.disabled = false;
    }
  };
  const comment = node("button", "💬 Bình luận", "act");
  comment.type = "button";
  const thread = node("div", undefined, "comments");
  thread.hidden = true;
  comment.onclick = async () => {
    thread.hidden = !thread.hidden;
    if (!thread.hidden) await loadComments();
  };
  async function loadComments() {
    const { comments } = await api("/posts/" + p.id + "/comments");
    thread.replaceChildren();
    for (const c of comments) {
      const row = node("div", undefined, "comment");
      const bubble = node("div", undefined, "comment-bubble");
      bubble.append(node("b", c.author.name), node("p", c.body));
      row.append(avatar(c.author), bubble, node("small", timeAgo(c.created), "meta"));
      thread.append(row);
    }
    const form = node("form", undefined, "comment-form");
    const input = node("input");
    input.placeholder = "Viết bình luận…";
    input.maxLength = 1000;
    input.required = true;
    input.setAttribute("aria-label", "Viết bình luận");
    const send = node("button", "Gửi bình luận", "ghost");
    form.append(avatar(me), input, send);
    form.onsubmit = async (e) => {
      e.preventDefault();
      send.disabled = true;
      try {
        await api("/posts/" + p.id + "/comments", "POST", { body: input.value });
        count++;
        paintStats();
        await loadComments();
        thread.querySelector(".comment-form input")?.focus();
      } catch (e) {
        status(e.message);
      } finally {
        send.disabled = false;
      }
    };
    thread.append(form);
  }
  bar.append(like, comment);
  if (p.user_id !== me.id) bar.append(action("✉ Nhắn tin", () => openChat(p.author), "act"));
  card.append(stats, bar, thread);
  return card;
}
async function feed(panel) {
  panel.append(node("h2", "Bảng tin", "sr-title"));
  await stories(panel).catch(() => {});
  composer(panel);
  const { posts } = await api("/posts");
  if (!posts.length)
    panel.append(empty("📝", "Bảng tin còn trống", "Chia sẻ lời chào đầu tiên hoặc theo dõi thêm bạn mới."));
  for (const p of posts) panel.append(postCard(p));
}
async function shorts(panel) {
  const upload = node("form", undefined, "short-upload");
  const pick = node("label", undefined, "file-pick");
  const file = node("input");
  file.type = "file";
  file.accept = "video/mp4";
  file.setAttribute("aria-label", "Chọn video MP4, tối đa 12 MB");
  const pickText = node("span", "🎬 Chọn video");
  pick.append(file, pickText);
  file.onchange = () => (pickText.textContent = file.files[0] ? "✓ " + file.files[0].name : "🎬 Chọn video");
  const caption = node("input");
  caption.maxLength = 500;
  caption.placeholder = "Chú thích video…";
  caption.setAttribute("aria-label", "Chú thích video");
  const send = node("button", "Đăng");
  upload.append(pick, caption, send);
  upload.onsubmit = async (e) => {
    e.preventDefault();
    const f = file.files[0];
    if (!f) return status("Chọn một video MP4.");
    if (f.size > 12 * 1024 * 1024) return status("Video tối đa 12 MB.");
    send.disabled = true;
    try {
      const data = await new Promise((resolve, reject) => {
        const r = new FileReader();
        r.onload = () => resolve(r.result);
        r.onerror = reject;
        r.readAsDataURL(f);
      });
      await api("/shorts", "POST", { data, caption: caption.value });
      status("Đã đăng video.");
      await navigate("shorts");
    } catch (e) {
      status(e.message);
      send.disabled = false;
    }
  };
  panel.append(upload);
  const reel = node("div", undefined, "reel");
  panel.append(reel);
  const { shorts: items } = await api("/shorts");
  if (!items.length) reel.append(empty("🎬", "Chưa có video nào", "Hãy là người đăng video đầu tiên!"));
  const watcher = new IntersectionObserver(
    (entries) => {
      for (const e of entries) {
        const v = e.target.querySelector("video");
        if (e.isIntersecting) v.play().catch(() => {});
        else v.pause();
      }
    },
    { threshold: 0.6 },
  );
  for (const s of items) {
    const slide = node("article", undefined, "reel-item");
    const v = node("video");
    v.src = s.video;
    v.loop = true;
    v.muted = true;
    v.playsInline = true;
    v.preload = "metadata";
    v.onclick = () => (v.muted = !v.muted);
    const meta = node("div", undefined, "reel-meta");
    meta.append(node("strong", "@" + s.author.username), node("p", s.caption));
    const side = node("div", undefined, "reel-side");
    side.append(personLink(s.author));
    let liked = s.liked,
      likes = s.likes;
    const like = node("button", undefined, "reel-btn");
    like.type = "button";
    const paint = () => {
      like.textContent = "♥ " + likes;
      like.setAttribute("aria-label", (liked ? "Bỏ thích" : "Thích") + " video");
      like.classList.toggle("on", liked);
    };
    paint();
    like.onclick = async () => {
      try {
        await api("/shorts/" + s.id + "/like", liked ? "DELETE" : "POST", {});
        liked = !liked;
        likes += liked ? 1 : -1;
        paint();
      } catch (e) {
        status(e.message);
      }
    };
    const chat = node("button", "✉", "reel-btn");
    chat.type = "button";
    chat.setAttribute("aria-label", "Nhắn tin cho " + s.author.name);
    chat.onclick = () => openChat(s.author).catch((e) => status(e.message));
    const flag = node("button", "⚑", "reel-btn");
    flag.type = "button";
    flag.setAttribute("aria-label", "Báo cáo video");
    flag.onclick = () => report("short", s.id).catch((e) => status(e.message));
    side.append(like, chat, flag);
    slide.append(v, meta, side);
    reel.append(slide);
    watcher.observe(slide);
  }
}
async function rail() {
  const box = $("rail");
  if (!box) return;
  const { users } = await api("/discover?q=");
  const list = node("section", undefined, "rail-box");
  list.append(node("h3", "Gợi ý kết bạn"));
  for (const u of users.slice(0, 5)) {
    const row = node("div", undefined, "rail-row");
    const who = node("button", undefined, "rail-who");
    who.type = "button";
    who.append(node("strong", u.name), node("small", u.score ? u.score + " sở thích chung" : "@" + u.username));
    who.onclick = () => navigate("profile", { user: u.id });
    const chat = node("button", "Nhắn", "ghost");
    chat.type = "button";
    chat.onclick = () => openChat(u).catch((e) => status(e.message));
    row.append(avatar(u), who, chat);
    list.append(row);
  }
  if (!users.length) list.append(node("p", "Chưa có gợi ý.", "muted"));
  const go = node("button", "Xem tất cả", "ghost wide");
  go.type = "button";
  go.onclick = () => navigate("discover");
  list.append(go);
  const foot = node("nav", undefined, "rail-foot");
  foot.setAttribute("aria-label", "Thông tin Kinnect");
  for (const [label, href] of [
    ["Giới thiệu", "https://kinnect.io.vn/"],
    ["Cộng đồng", "https://kinnect.io.vn/community"],
    ["Quyền riêng tư", "https://kinnect.io.vn/privacy"],
    ["Trợ giúp", "https://kinnect.io.vn/support"],
  ]) {
    const a = node("a", label);
    a.href = href;
    a.target = "_blank";
    a.rel = "noopener";
    foot.append(a);
  }
  foot.append(node("span", "© 2026 Kinnect · Bản thử nghiệm 18+"));
  const keep = box.querySelector(".platforms");
  box.replaceChildren(list);
  if (keep) box.append(keep);
  box.append(foot);
}
function field(form, label, value, type = "text") {
  const wrapper = node("label", label, "form-field");
  const input = node(type === "textarea" ? "textarea" : "input");
  if (type !== "textarea") input.type = type;
  input.value = value;
  wrapper.append(input);
  form.append(wrapper);
  return input;
}
async function profile(panel, opts = {}) {
  const own = !opts.user || opts.user === (me && me.id);
  if (own) {
    me = (await api("/me")).user;
    paintMe();
  }
  const info = await api("/users/" + (own ? me.id : opts.user) + "/stats");
  const u = own ? me : info.user;
  // Phần đầu trang cá nhân
  const head = node("section", undefined, "social-card profile-head");
  const cover = node("div", undefined, "cover " + hue(u.id));
  const big = avatar(u);
  big.classList.add("big");
  const id = node("div", undefined, "profile-id");
  id.append(node("h2", u.name), node("p", "@" + u.username, "muted"));
  const bio = node("p", u.bio || (own ? "Thêm vài dòng giới thiệu để mọi người hiểu bạn hơn." : ""), "profile-bio");
  const nums = node("div", undefined, "profile-stats");
  for (const [n, label] of [[info.posts, "bài viết"], [info.followers, "người theo dõi"], [info.following, "đang theo dõi"]]) {
    const s = node("div");
    s.append(node("b", String(n)), node("span", label));
    nums.append(s);
  }
  const tags = node("div", undefined, "tags");
  (u.interests || []).forEach((v) => tags.append(node("span", v)));
  const acts = node("div", undefined, "profile-actions");
  head.append(cover, big, id, bio, tags, nums, acts);
  panel.append(head);
  const settings = node("div", undefined, "settings");
  if (own) {
    const edit = node("button", "Sửa hồ sơ", "secondary");
    edit.type = "button";
    edit.onclick = () => {
      settings.hidden = !settings.hidden;
      if (!settings.hidden) settings.querySelector("input")?.focus();
    };
    const pick = node("label", undefined, "btn-like secondary");
    const upload = node("input");
    upload.type = "file";
    upload.accept = "image/png,image/jpeg,image/webp";
    upload.setAttribute("aria-label", "Đổi ảnh đại diện, tối đa 1 MB");
    pick.append(upload, node("span", "📷 Đổi ảnh đại diện"));
    upload.onchange = async () => {
      const f = upload.files[0];
      if (!f) return;
      if (f.size > 1024 * 1024) return status("Chọn ảnh nhỏ hơn 1 MB.");
      try {
        const data = await new Promise((resolve, reject) => {
          const r = new FileReader();
          r.onload = () => resolve(r.result);
          r.onerror = reject;
          r.readAsDataURL(f);
        });
        me = (await api("/me/avatar", "POST", { data })).user;
        status("Đã cập nhật ảnh đại diện.");
        await navigate("profile");
      } catch (e) {
        status(e.message);
      }
    };
    acts.append(edit, pick);
  } else {
    acts.append(
      action(u.following ? "Bỏ theo dõi" : "Theo dõi", async () => {
        await api("/users/" + u.id + "/follow", u.following ? "DELETE" : "POST", {});
        await navigate("profile", opts);
      }, u.following ? "secondary" : "follow"),
      action("Nhắn tin", () => openChat(u)),
      more([
        ["Chặn", async () => {
          if (!confirm("Chặn " + u.name + "?")) return;
          await api("/users/" + u.id + "/block", "POST", {});
          status("Đã chặn " + u.name + ".");
          await navigate("feed");
        }],
        ["Báo cáo", () => report("user", u.id)],
      ]),
    );
  }
  if (own) {
    settings.hidden = !opts.settings;
    // Sửa hồ sơ
    const form = node("form", undefined, "social-card");
    form.append(node("h3", "Thông tin hồ sơ"));
    const name = field(form, "Tên hiển thị", me.name);
    name.maxLength = 60;
    name.required = true;
    const bioInput = field(form, "Giới thiệu", me.bio, "textarea");
    bioInput.maxLength = 500;
    const interests = field(form, "Sở thích, phân cách bằng dấu phẩy", me.interests.join(", "));
    interests.maxLength = 350;
    const visibleLabel = node("label", undefined, "switch-row");
    const visible = node("input");
    visible.type = "checkbox";
    visible.checked = me.discoverable;
    visibleLabel.append(node("span", "Cho phép xuất hiện trong Khám phá"), visible);
    form.append(visibleLabel);
    const dmLabel = node("label", "Ai được nhắn tin cho bạn", "form-field");
    const dm = node("select");
    for (const [value, label] of [
      ["mutual", "Chỉ người theo dõi lẫn nhau"],
      ["everyone", "Mọi thành viên"],
    ]) {
      const o = node("option", label);
      o.value = value;
      dm.append(o);
    }
    dm.value = me.dmMode;
    dmLabel.append(dm);
    form.append(dmLabel);
    const save = node("button", "Lưu hồ sơ");
    form.append(save);
    form.onsubmit = async (e) => {
      e.preventDefault();
      save.disabled = true;
      try {
        me = (
          await api("/me", "PATCH", {
            name: name.value,
            bio: bioInput.value,
            interests: interests.value.split(","),
            discoverable: visible.checked,
            dmMode: dm.value,
          })
        ).user;
        $("name").value = me.name;
        paintMe();
        status("Đã lưu hồ sơ.");
      } catch (e) {
        status(e.message);
      } finally {
        save.disabled = false;
      }
    };
    // Đổi mật khẩu
    const pw = node("form", undefined, "social-card");
    pw.append(node("h3", "Đổi mật khẩu"));
    const current = field(pw, "Mật khẩu hiện tại", "", "password");
    current.autocomplete = "current-password";
    current.required = true;
    const next = field(pw, "Mật khẩu mới (tối thiểu 6 ký tự)", "", "password");
    next.autocomplete = "new-password";
    next.minLength = 6;
    next.maxLength = 128;
    next.required = true;
    const pwSave = node("button", "Đổi mật khẩu");
    pw.append(pwSave);
    pw.onsubmit = async (e) => {
      e.preventDefault();
      pwSave.disabled = true;
      try {
        await api("/me/password", "POST", { current: current.value, next: next.value });
        current.value = next.value = "";
        status("Đã đổi mật khẩu. Các thiết bị khác đã được đăng xuất.");
      } catch (e) {
        status(e.message);
      } finally {
        pwSave.disabled = false;
      }
    };
    // Người đã chặn
    const blocks = node("section", undefined, "social-card");
    blocks.append(node("h3", "Người đã chặn"));
    const { users } = await api("/blocks");
    if (!users.length) blocks.append(node("p", "Bạn chưa chặn ai.", "muted"));
    for (const b of users) {
      const line = node("div", undefined, "block-row");
      line.append(avatar(b), node("span", b.name));
      line.append(
        action("Bỏ chặn", async () => {
          await api("/users/" + b.id + "/block", "DELETE", {});
          await navigate("profile", { settings: true });
        }),
      );
      blocks.append(line);
    }
    settings.append(form, pw, blocks);
    panel.append(settings);
  }
  // Bài viết của người này
  panel.append(node("h3", own ? "Bài viết của bạn" : "Bài viết", "section-title"));
  const { posts } = await api("/posts?user=" + encodeURIComponent(u.id));
  if (!posts.length)
    panel.append(empty("📝", "Chưa có bài viết", own ? "Chia sẻ điều đầu tiên trên Bảng tin nhé." : "Người này chưa đăng gì."));
  for (const p of posts) panel.append(postCard(p));
}
async function inbox(panel) {
  const head = node("div", undefined, "view-head");
  head.append(node("h2", "Tin nhắn"), node("p", "Mặc định chỉ người theo dõi lẫn nhau mới nhắn được cho nhau.", "muted"));
  panel.append(head);
  const { users } = await api("/conversations");
  if (!users.length)
    panel.append(empty("💬", "Chưa có cuộc trò chuyện", "Khám phá và theo dõi bạn mới để bắt đầu."));
  const list = node("div", undefined, "social-card list inbox-list");
  for (const u of users) {
    const row = node("button", undefined, "list-row inbox-row");
    row.type = "button";
    const text = node("div", undefined, "row-text");
    text.append(
      node("b", u.name),
      node("span", u.last ? (u.last.mine ? "Bạn: " : "") + u.last.body : "Bắt đầu trò chuyện", "muted"),
    );
    row.append(avatar(u), text, node("small", u.last ? timeAgo(u.last.created) : "", "meta"));
    row.onclick = () => openChat(u);
    list.append(row);
  }
  if (users.length) panel.append(list);
}
async function openChat(u) {
  await navigate("inbox");
  const panel = $("social-panel");
  const head = node("div", undefined, "chat-head");
  const back = node("button", "←", "icon-btn");
  back.type = "button";
  back.setAttribute("aria-label", "Quay lại hộp thư");
  back.onclick = () => navigate("inbox");
  const who = node("button", undefined, "chat-who");
  who.type = "button";
  who.append(avatar(u), node("b", u.name));
  who.onclick = () => navigate("profile", { user: u.id });
  head.append(back, who, more([["Báo cáo người này", () => report("user", u.id)]]));
  const box = node("div", undefined, "social-card chat-box");
  const log = node("div", undefined, "dm-log");
  log.setAttribute("role", "log");
  log.setAttribute("aria-live", "polite");
  const form = node("form", undefined, "dm-compose");
  const input = node("input");
  input.maxLength = 2000;
  input.required = true;
  input.placeholder = "Nhắn tin…";
  input.setAttribute("aria-label", "Tin nhắn riêng");
  const button = node("button", "Gửi");
  form.append(input, button);
  box.append(head, log, form);
  panel.replaceChildren(box);
  let signature = "";
  async function load() {
    const result = await api("/users/" + u.id + "/messages");
    if (tab !== "inbox" || !log.isConnected) return;
    const next = JSON.stringify(result.messages);
    if (signature === next) return;
    signature = next;
    log.replaceChildren();
    let lastDay = "";
    for (const m of result.messages) {
      const day = new Date(m.created).toLocaleDateString("vi-VN");
      if (day !== lastDay) {
        log.append(node("div", day === new Date().toLocaleDateString("vi-VN") ? "Hôm nay" : day, "day-sep"));
        lastDay = day;
      }
      const mine = m.sender === me.id;
      const bubble = node("article", undefined, "bubble " + (mine ? "mine" : ""));
      bubble.append(node("p", m.body), node("small", clock(m.created)));
      if (!mine) {
        const flag = node("button", "⚑", "bubble-flag");
        flag.type = "button";
        flag.setAttribute("aria-label", "Báo cáo tin nhắn");
        flag.onclick = () => report("message", m.id).catch((e) => status(e.message));
        bubble.append(flag);
      }
      log.append(bubble);
    }
    log.scrollTop = log.scrollHeight;
  }
  form.onsubmit = async (e) => {
    e.preventDefault();
    button.disabled = true;
    try {
      await api("/users/" + u.id + "/messages", "POST", { body: input.value });
      input.value = "";
      await load();
    } catch (e) {
      status(e.message);
    } finally {
      button.disabled = false;
      input.focus();
    }
  };
  await load();
  input.focus();
  timer = setInterval(
    () =>
      load().catch((e) => {
        clearInterval(timer);
        status(e.message);
      }),
    4000,
  );
}
async function refreshUnread() {
  if (!me) return;
  const { notifications } = await api("/notifications");
  const count = notifications.filter((n) => !n.seen).length;
  $("unread").textContent = count ? (count > 9 ? "9+" : String(count)) : "";
}
const NOTE_TEXT = {
  follow: "đã theo dõi bạn.",
  message: "đã gửi tin nhắn cho bạn.",
  gift: "đã gửi quà thử nghiệm miễn phí.",
  like: "đã thích bài viết của bạn.",
  comment: "đã bình luận về bài viết của bạn.",
};
async function notifications(panel) {
  const head = node("div", undefined, "view-head");
  head.append(node("h2", "Thông báo"));
  panel.append(head);
  const { notifications } = await api("/notifications");
  if (!notifications.length) panel.append(empty("🔔", "Chưa có thông báo", "Khi có người theo dõi, thích hay nhắn tin cho bạn, thông báo sẽ hiện ở đây."));
  const today = new Date().toDateString();
  let group = "";
  let list;
  for (const n of notifications) {
    const g = new Date(n.created).toDateString() === today ? "Hôm nay" : "Trước đó";
    if (g !== group) {
      group = g;
      panel.append(node("h3", g, "section-title"));
      list = node("div", undefined, "social-card list");
      panel.append(list);
    }
    const row = node("button", undefined, "list-row note-row" + (n.seen ? "" : " unread"));
    row.type = "button";
    const text = node("div", undefined, "row-text");
    const line = node("p");
    line.append(node("b", n.actor.name), " ", node("span", NOTE_TEXT[n.kind] || "có hoạt động mới."));
    text.append(line, node("small", timeAgo(n.created), "meta"));
    row.append(avatar(n.actor), text);
    if (!n.seen) row.append(node("span", undefined, "dot"));
    row.onclick = () => {
      if (n.kind === "message") openChat(n.actor).catch((e) => status(e.message));
      else if (n.kind === "like" || n.kind === "comment") navigate("profile");
      else navigate("profile", { user: n.actor.id });
    };
    list.append(row);
  }
  await api("/notifications", "POST", {});
  await refreshUnread();
}
async function adminPanel(panel) {
  panel.append(
    node("h2", "Quản trị Kinnect"),
    node(
      "p",
      "Báo cáo cần được xem xét thủ công. Chỉ xử lý nội dung có bằng chứng.",
      "muted",
    ),
  );
  const { requests } = await api("/admin/password-resets");
  const open = requests.filter((r) => r.status === "open");
  panel.append(node("h3", "Yêu cầu quên mật khẩu" + (open.length ? " (" + open.length + ")" : "")));
  if (!open.length) panel.append(node("p", "Không có yêu cầu đang chờ.", "muted"));
  for (const r of open) {
    const card = node("article", undefined, "social-card");
    card.append(
      node("h3", "@" + r.username + (r.user_id ? "" : " · không có tài khoản")),
      node("p", "Liên hệ: " + r.contact),
      node("p", r.note ? "Ghi chú: " + r.note : "Không có ghi chú.", "muted"),
      node("p", new Date(r.created).toLocaleString("vi-VN"), "muted fine"),
    );
    if (r.user_id)
      card.append(
        action("Cấp mật khẩu tạm", async () => {
          if (!confirm("Đặt lại mật khẩu cho @" + r.username + "? Chỉ làm khi đã xác minh đúng chủ tài khoản.")) return;
          const res = await api("/admin/password-resets/" + r.id + "/reset", "POST", {});
          prompt("Mật khẩu tạm của @" + res.username + " (sao chép và gửi cho người dùng):", res.temporaryPassword);
          await navigate("admin");
        }, "follow"),
      );
    card.append(
      action("Bỏ qua", async () => {
        await api("/admin/password-resets/" + r.id + "/dismiss", "POST", {});
        await navigate("admin");
      }),
    );
    panel.append(card);
  }
  panel.append(node("h3", "Báo cáo"));
  const { reports } = await api("/admin/reports");
  if (!reports.length) panel.append(node("p", "Chưa có báo cáo."));
  for (const r of reports) {
    const card = node("article", undefined, "social-card");
    card.append(
      node("h3", r.target_type + " · " + r.status),
      node("p", r.reason),
      node(
        "p",
        r.subject?.body || r.subject?.username || "Nội dung không còn tồn tại.",
      ),
    );
    const perform = async (action, target) => {
      if (!confirm("Xác nhận " + action + "?")) return;
      await api("/admin/moderate", "POST", { action, target });
      await navigate("admin");
    };
    if (r.target_type === "short" && r.subject)
      card.append(
        action(r.subject.hidden ? "Hiện video" : "Ẩn video", () =>
          perform(r.subject.hidden ? "show-short" : "hide-short", r.target_id),
        ),
      );
    if (r.target_type === "post" && r.subject)
      card.append(
        action(r.subject.hidden ? "Hiện bài" : "Ẩn bài", () =>
          perform(r.subject.hidden ? "show-post" : "hide-post", r.target_id),
        ),
      );
    if (r.subject?.userId)
      card.append(
        action("Đình chỉ tài khoản", () =>
          perform("suspend-user", r.subject.userId),
        ),
      );
    if (r.status === "open")
      card.append(action("Đóng báo cáo", () => perform("close-report", r.id)));
    panel.append(card);
  }
  const { users } = await api("/admin/users");
  panel.append(node("h3", "Tài khoản gần đây"));
  for (const u of users) {
    const row = node("article", undefined, "social-card");
    row.append(
      node(
        "strong",
        u.username + " · " + u.role + (u.suspended ? " · Đã đình chỉ" : ""),
      ),
    );
    if (u.role !== "admin")
      row.append(
        action(u.suspended ? "Khôi phục" : "Đình chỉ", async () => {
          if (!confirm("Thay đổi trạng thái " + u.username + "?")) return;
          await api("/admin/moderate", "POST", {
            action: u.suspended ? "restore-user" : "suspend-user",
            target: u.id,
          });
          await navigate("admin");
        }),
      );
    panel.append(row);
  }
}
try {
  me = (await api("/me")).user;
  await enter();
} catch {
  showAuth();
}

$("create-post").onclick = async () => {
  await navigate("feed");
  document.querySelector(".composer textarea")?.focus();
};

window.addEventListener("kinnect-report", (event) =>
  report(event.detail.targetType, event.detail.targetId).catch((e) =>
    status(e.message),
  ),
);

window.addEventListener("kinnect-live-state", (event) => {
  document.querySelector('[data-tab="live"]').textContent = event.detail
    ? "Live ●"
    : "Live";
});
