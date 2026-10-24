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
const status = (text) => {
  $("notice").textContent = text;
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
}
function authMode(value) {
  mode = value;
  $("register-fields").hidden = mode !== "register";
  $("register-fields").disabled = mode !== "register";
  $("auth-submit").textContent =
    mode === "register" ? "Tạo tài khoản 18+" : "Đăng nhập";
  $("password").autocomplete =
    mode === "register" ? "new-password" : "current-password";
  $("auth-status").textContent = "";
}
$("login-mode").onclick = () => authMode("login");
$("register-mode").onclick = () => authMode("register");
$("auth-form").onsubmit = async (e) => {
  e.preventDefault();
  $("auth-submit").disabled = true;
  try {
    const result = await api("/" + mode, "POST", {
      username: $("username").value,
      password: $("password").value,
      name: $("display-name").value,
      birthDate: $("birth-date").value,
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
  $("auth").hidden = true;
  $("app").hidden = false;
  $("name").value = me.name;
  connectLive();
  status("Chào " + me.name + ". Hãy bắt đầu bằng một lời chào!");
  await navigate("feed");
  clearInterval(notificationTimer);
  notificationTimer = setInterval(() => refreshUnread().catch(() => {}), 15000);
  await refreshUnread();
}
$("logout").onclick = async () => {
  try {
    await api("/logout", "POST", {});
    me = null;
    disconnectLive();
    showAuth();
  } catch (e) {
    status(e.message);
  }
};
for (const button of document.querySelectorAll("[data-tab]"))
  button.onclick = () =>
    navigate(button.dataset.tab).catch((e) => status(e.message));
async function navigate(value) {
  clearInterval(timer);
  timer = null;
  tab = value;
  for (const b of document.querySelectorAll("[data-tab]"))
    b.classList.toggle("active", b.dataset.tab === value);
  $("social-panel").hidden = value === "live";
  $("live-panel").hidden = value !== "live";
  const panel = $("social-panel");
  panel.replaceChildren();
  if (value === "live") return;
  try {
    if (value === "feed") await feed(panel);
    if (value === "discover") await discover(panel);
    if (value === "profile") await profile(panel);
    if (value === "inbox") await inbox(panel);
    if (value === "notifications") await notifications(panel);
  } catch (e) {
    status(e.message);
    panel.append(node("p", "Không tải được dữ liệu. Hãy thử lại."));
  }
}
function avatar(u) {
  if (!u.avatar) {
    const e = node(
      "span",
      (u.name || "?").slice(0, 1).toUpperCase(),
      "avatar fallback",
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
function userCard(u) {
  const card = node("article", undefined, "social-card");
  const head = node("div", undefined, "person");
  head.append(avatar(u));
  const info = node("div");
  info.append(node("h3", u.name), node("p", "@" + u.username, "muted"));
  head.append(info);
  card.append(
    head,
    node("p", u.bio || "Một người bạn mới đang chờ câu chuyện của bạn."),
  );
  const tags = node("div", undefined, "tags");
  u.interests.forEach((v) => tags.append(node("span", v)));
  card.append(tags);
  if (u.score) card.append(node("p", u.score + " sở thích chung", "muted"));
  const buttons = node("div", undefined, "card-actions");
  buttons.append(
    action(u.following ? "Bỏ theo dõi" : "Theo dõi", async () => {
      await api(
        "/users/" + u.id + "/follow",
        u.following ? "DELETE" : "POST",
        {},
      );
      await navigate(tab);
    }),
    action("Nhắn tin", () => openChat(u)),
    action("Chặn", async () => {
      if (
        !confirm(
          "Chặn " +
            u.name +
            "? Hai bên sẽ không thấy nhau trong khám phá, bảng tin, chat và phòng live.",
        )
      )
        return;
      await api("/users/" + u.id + "/block", "POST", {});
      status("Đã chặn.");
      await navigate(tab);
    }),
    action("Báo cáo", () => report("user", u.id)),
  );
  card.append(buttons);
  return card;
}
async function report(targetType, targetId) {
  const reason = prompt(
    "Mô tả vấn đề (ít nhất 5 ký tự). Báo cáo sẽ được chủ máy chủ kiểm tra thủ công.",
  );
  if (!reason) return;
  await api("/reports", "POST", { targetType, targetId, reason });
  status("Đã gửi báo cáo để xem xét. Nếu cần, hãy chặn người dùng này.");
}
async function discover(panel) {
  panel.append(
    node("h2", "Những kết nối cùng tần số"),
    node(
      "p",
      "Gợi ý theo số sở thích chung, không sử dụng vị trí chính xác.",
      "muted",
    ),
  );
  const form = node("form");
  const search = node("input");
  search.placeholder = "Tìm tên hoặc sở thích…";
  search.setAttribute("aria-label", "Tìm bạn");
  const button = node("button", "Tìm kiếm");
  form.append(search, button);
  panel.append(form);
  const list = node("div", undefined, "people-grid");
  panel.append(list);
  async function load() {
    const { users } = await api(
      "/discover?q=" + encodeURIComponent(search.value),
    );
    if (tab !== "discover") return;
    list.replaceChildren();
    users.forEach((u) => list.append(userCard(u)));
    if (!users.length)
      list.append(
        node(
          "p",
          "Chưa tìm thấy ai. Hãy bổ sung sở thích hoặc mời bạn bè tham gia.",
          "muted",
        ),
      );
  }
  form.onsubmit = (e) => {
    e.preventDefault();
    load().catch((e) => status(e.message));
  };
  await load();
}
async function feed(panel) {
  panel.append(node("h2", "Chuyện của chúng mình"));
  const form = node("form", undefined, "social-card");
  const input = node("textarea");
  input.placeholder = "Hôm nay bạn muốn chia sẻ điều gì?";
  input.maxLength = 2000;
  input.required = true;
  input.setAttribute("aria-label", "Nội dung bài viết");
  const visibility = node("select");
  visibility.setAttribute("aria-label", "Ai có thể xem bài viết");
  for (const [value, label] of [
    ["public", "Mọi thành viên"],
    ["followers", "Chỉ người theo dõi"],
  ]) {
    const o = node("option", label);
    o.value = value;
    visibility.append(o);
  }
  const submit = node("button", "Chia sẻ");
  form.append(input, visibility, submit);
  form.onsubmit = async (e) => {
    e.preventDefault();
    submit.disabled = true;
    try {
      await api("/posts", "POST", {
        body: input.value,
        visibility: visibility.value,
      });
      await navigate("feed");
    } catch (e) {
      status(e.message);
      submit.disabled = false;
    }
  };
  panel.append(form);
  const { posts } = await api("/posts");
  if (!posts.length)
    panel.append(
      node("p", "Bảng tin còn trống. Chia sẻ lời chào đầu tiên nhé.", "muted"),
    );
  for (const p of posts) {
    const card = node("article", undefined, "social-card");
    const head = node("div", undefined, "person");
    head.append(avatar(p.author), node("strong", p.author.name));
    card.append(
      head,
      node(
        "p",
        new Date(p.created).toLocaleString("vi-VN") +
          " · " +
          (p.visibility === "followers" ? "Người theo dõi" : "Thành viên"),
        "muted fine",
      ),
      node("p", p.body, "post-body"),
    );
    if (p.user_id === me.id)
      card.append(
        action("Xóa bài", async () => {
          if (confirm("Xóa bài viết này?")) {
            await api("/posts/" + p.id, "DELETE", {});
            await navigate("feed");
          }
        }),
      );
    else card.append(action("Báo cáo", () => report("post", p.id)));
    panel.append(card);
  }
}
function field(form, label, value, type = "text") {
  const wrapper = node("label", label);
  const input = node(type === "textarea" ? "textarea" : "input");
  if (type !== "textarea") input.type = type;
  input.value = value;
  wrapper.append(input);
  form.append(wrapper);
  return input;
}
async function profile(panel) {
  me = (await api("/me")).user;
  panel.append(node("h2", "Không gian của bạn"));
  const form = node("form", undefined, "social-card");
  const name = field(form, "Tên hiển thị", me.name);
  name.maxLength = 60;
  name.required = true;
  const bio = field(form, "Giới thiệu", me.bio, "textarea");
  bio.maxLength = 500;
  const interests = field(
    form,
    "Sở thích, phân cách bằng dấu phẩy",
    me.interests.join(", "),
  );
  interests.maxLength = 350;
  const visible = field(
    form,
    "Cho phép xuất hiện trong khám phá",
    "",
    "checkbox",
  );
  visible.checked = me.discoverable;
  const dm = node("select");
  dm.setAttribute("aria-label", "Quyền nhận tin nhắn");
  for (const [value, label] of [
    ["mutual", "Chỉ nhận tin khi theo dõi lẫn nhau"],
    ["everyone", "Nhận tin từ mọi thành viên"],
  ]) {
    const o = node("option", label);
    o.value = value;
    dm.append(o);
  }
  dm.value = me.dmMode;
  form.append(dm);
  const save = node("button", "Lưu hồ sơ");
  form.append(save);
  form.onsubmit = async (e) => {
    e.preventDefault();
    save.disabled = true;
    try {
      me = (
        await api("/me", "PATCH", {
          name: name.value,
          bio: bio.value,
          interests: interests.value.split(","),
          discoverable: visible.checked,
          dmMode: dm.value,
        })
      ).user;
      $("name").value = me.name;
      status("Đã lưu hồ sơ.");
    } catch (e) {
      status(e.message);
    } finally {
      save.disabled = false;
    }
  };
  panel.append(form);
  const photos = node("section", undefined, "social-card");
  photos.append(node("h3", "Ảnh đại diện"), avatar(me));
  const upload = node("input");
  upload.type = "file";
  upload.accept = "image/png,image/jpeg,image/webp";
  upload.setAttribute("aria-label", "Tải ảnh đại diện, tối đa 1 MB");
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
      status("Đã lưu ảnh.");
      await navigate("profile");
    } catch (e) {
      status(e.message);
    }
  };
  photos.append(upload);
  panel.append(photos);
  const blocks = node("section", undefined, "social-card");
  blocks.append(node("h3", "Người đã chặn"));
  const { users } = await api("/blocks");
  if (!users.length) blocks.append(node("p", "Chưa chặn ai.", "muted"));
  for (const u of users) {
    const line = node("p", u.name + " ");
    line.append(
      action("Bỏ chặn", async () => {
        await api("/users/" + u.id + "/block", "DELETE", {});
        await navigate("profile");
      }),
    );
    blocks.append(line);
  }
  panel.append(blocks);
}
async function inbox(panel) {
  panel.append(
    node("h2", "Tin nhắn riêng"),
    node(
      "p",
      "Mặc định chỉ người theo dõi lẫn nhau mới gửi được tin. Chưa có mã hóa đầu cuối.",
      "muted",
    ),
  );
  const { users } = await api("/conversations");
  if (!users.length)
    panel.append(
      node(
        "p",
        "Chưa có cuộc trò chuyện. Khám phá và theo dõi bạn mới để bắt đầu.",
        "muted",
      ),
    );
  for (const u of users) {
    const card = node("div", undefined, "social-card person");
    card.append(
      avatar(u),
      node("strong", u.name),
      action("Mở trò chuyện", () => openChat(u)),
    );
    panel.append(card);
  }
}
async function openChat(u) {
  await navigate("inbox");
  const panel = $("social-panel");
  panel.replaceChildren(
    node("h2", "Trò chuyện với " + u.name),
    action("Quay lại hộp thư", () => navigate("inbox")),
  );
  const log = node("div", undefined, "dm-log");
  log.setAttribute("role", "log");
  log.setAttribute("aria-live", "polite");
  panel.append(log);
  const form = node("form", undefined, "dm-compose");
  const input = node("input");
  input.maxLength = 2000;
  input.required = true;
  input.placeholder = "Gửi lời chào…";
  input.setAttribute("aria-label", "Tin nhắn riêng");
  const button = node("button", "Gửi");
  form.append(input, button);
  panel.append(form);
  let signature = "";
  async function load() {
    const result = await api("/users/" + u.id + "/messages");
    if (tab !== "inbox" || !log.isConnected) return;
    const next = JSON.stringify(result.messages);
    if (signature === next) return;
    signature = next;
    log.replaceChildren();
    for (const m of result.messages) {
      const bubble = node(
        "article",
        undefined,
        "bubble " + (m.sender === me.id ? "mine" : ""),
      );
      bubble.append(
        node("p", m.body),
        node("small", new Date(m.created).toLocaleString("vi-VN")),
      );
      if (m.sender !== me.id)
        bubble.append(action("Báo cáo", () => report("message", m.id)));
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
    }
  };
  await load();
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
  $("unread").textContent = count ? "(" + count + ")" : "";
}
async function notifications(panel) {
  panel.append(node("h2", "Những kết nối mới"));
  const { notifications } = await api("/notifications");
  for (const n of notifications) {
    const card = node("article", undefined, "social-card");
    card.append(
      node("strong", n.actor.name),
      node(
        "p",
        n.kind === "follow" ? "đã theo dõi bạn." : "đã gửi tin nhắn cho bạn.",
      ),
    );
    if (n.kind === "message")
      card.append(action("Xem tin nhắn", () => openChat(n.actor)));
    panel.append(card);
  }
  if (!notifications.length)
    panel.append(node("p", "Chưa có thông báo mới.", "muted"));
  await api("/notifications", "POST", {});
  await refreshUnread();
}
try {
  me = (await api("/me")).user;
  await enter();
} catch {
  showAuth();
}

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
