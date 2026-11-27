// Lazy-loaded Group 2 features: 2FA/TOTP, chat message edit, group polls, group voice/video calls.

const twoFactorState = { loaded: false, enabled: false, pending: false, recoveryRemaining: 0, setup: null, freshBackup: null, busy: false, userId: "" };
const groupCallState = {
  activeGroupId: "",
  groupName: "",
  mode: "audio",
  selfId: "",
  stream: null,
  muted: false,
  videoOff: false,
  participants: [],
  peers: new Map(), // peerId -> RTCPeerConnection
  streams: new Map(), // peerId -> MediaStream
  bannerByGroup: new Map(), // groupId -> { active, mode, participants }
};

export function resetTwoFactorState() {
  Object.assign(twoFactorState, {
    loaded: false,
    enabled: false,
    pending: false,
    recoveryRemaining: 0,
    setup: null,
    freshBackup: null,
    busy: false,
    userId: "",
  });
}

export async function loadTwoFactor(api, userId = "") {
  const nextId = String(userId || "");
  if (twoFactorState.userId !== nextId) {
    twoFactorState.setup = null;
    twoFactorState.freshBackup = null;
    twoFactorState.userId = nextId;
  }
  const data = await api("/me/2fa");
  Object.assign(twoFactorState, {
    loaded: true,
    enabled: !!data.enabled,
    pending: !!data.pending,
    recoveryRemaining: Number(data.recoveryRemaining || 0),
  });
}

export function renderTwoFactorScreen({ s, ic, esc, btn, childHeading, loading }) {
  if (!twoFactorState.loaded) return childHeading("Xác thực 2 lớp (2FA)", "security") + loading();
  const st = twoFactorState;
  const statusBadge = st.enabled
    ? `<p class="push-state ok">${ic("shield-check")}<span><strong>Đã bật xác thực 2 lớp.</strong> Còn ${st.recoveryRemaining} mã dự phòng chưa dùng.${s.me?.role === "admin" ? " Tài khoản quản trị được khuyến nghị luôn bật 2FA." : ""}</span></p>`
    : `<p class="push-state">${ic("shield-check")}<span>Chưa bật xác thực 2 lớp. Dùng Google Authenticator, Microsoft Authenticator hoặc 1Password để tạo mã 6 số mỗi khi đăng nhập.</span></p>`;

  const backupList = (codes) =>
    `<div class="v2-2fa-codes"><strong>Mã dự phòng một lần (lưu lại nơi an toàn):</strong><div class="v2-2fa-code-grid">${codes.map((c) => `<code>${esc(c)}</code>`).join("")}</div></div>`;

  const hasPwd = s.me?.hasPassword !== false;
  const oauthNote = `<p class="body-copy"><small>Tài khoản đăng nhập mạng xã hội chưa có mật khẩu. Nếu phiên đăng nhập đã quá 10 phút, hãy đăng nhập lại rồi thử lại.</small></p>`;
  let bodyHtml = "";
  if (!st.enabled) {
    if (!st.setup) {
      bodyHtml = `<form data-2fa-setup class="settings-section">${hasPwd ? `<label class="v2-field">Nhập mật khẩu hiện tại để thiết lập<input type="password" name="password" autocomplete="current-password" required></label>` : oauthNote}<button type="submit" class="primary" ${st.busy ? "disabled" : ""}>Tạo khóa xác thực 2FA</button></form>`;
    } else {
      bodyHtml = `<div class="v2-2fa-setup">
        <p class="body-copy">1. Mở ứng dụng xác thực (Google Authenticator / Authy) → Thêm khóa thủ công với mã bí mật bên dưới:</p>
        <div class="v2-2fa-secret"><code>${esc(st.setup.secret)}</code>${btn("Sao chép khóa", "copy", "2fa-copy-secret", "secondary")}</div>
        <p class="body-copy"><small>Hoặc mở liên kết cấu hình: <a href="${esc(st.setup.otpauthUri)}">Thêm vào ứng dụng xác thực</a></small></p>
        ${backupList(st.setup.backupCodes || [])}
        <form data-2fa-enable class="settings-section">
          <label class="v2-field">2. Nhập mã 6 chữ số từ ứng dụng để kích hoạt<input name="code" inputmode="numeric" autocomplete="one-time-code" maxlength="6" placeholder="123456" required></label>
          <button type="submit" class="primary" ${st.busy ? "disabled" : ""}>Xác minh &amp; Bật 2FA</button>
        </form>
      </div>`;
    }
  } else {
    bodyHtml = `${st.freshBackup ? backupList(st.freshBackup) : ""}
      <details class="v2-2fa-details"><summary>Tạo lại 8 mã dự phòng mới</summary>
        <form data-2fa-recovery class="settings-section">
          ${hasPwd ? `<label class="v2-field">Mật khẩu hiện tại<input type="password" name="password" autocomplete="current-password" required></label>` : oauthNote}
          <label class="v2-field">Mã 6 số hiện tại<input name="code" inputmode="numeric" maxlength="10" required></label>
          <button type="submit" class="secondary" ${st.busy ? "disabled" : ""}>Tạo bộ mã dự phòng mới</button>
        </form>
      </details>
      <details class="v2-2fa-details"><summary>Tắt xác thực 2 lớp</summary>
        <form data-2fa-disable class="settings-section">
          ${hasPwd ? `<label class="v2-field">Mật khẩu hiện tại<input type="password" name="password" autocomplete="current-password" required></label>` : oauthNote}
          <label class="v2-field">Mã 6 số hoặc mã dự phòng<input name="code" maxlength="12" required></label>
          <button type="submit" class="danger" ${st.busy ? "disabled" : ""}>Tắt 2FA</button>
        </form>
      </details>`;
  }

  return childHeading("Xác thực 2 lớp (2FA)", "security") + `<section class="panel settings-section">${statusBadge}${bodyHtml}</section>`;
}

export function renderOauth2faScreen({ authHead, authBanner, authFormError, authField, submitBtn, btn }) {
  return (
    authHead("Xác thực 2 lớp (2FA)", "Nhập mã 6 số hoặc mã dự phòng để hoàn tất đăng nhập.") +
    authBanner() +
    `<form data-oauth-2fa class="auth-form" novalidate>${authFormError()}${authField(
      "totpCode",
      "Mã xác thực 2 lớp",
      "shield-check",
      'inputmode="numeric" autocomplete="one-time-code" maxlength="12" placeholder="123456"'
    )}${submitBtn("shield-check", "Xác minh")}</form>` +
    btn("Quay lại đăng nhập", "arrow-left", "auth-screen", "", "login")
  );
}

export async function handleTwoFactorSubmit(form, { api, s, toast, render, signedIn }) {
  if (form.matches("[data-oauth-2fa]")) {
    const totpCode = String(s.auth.values.totpCode || "").trim();
    if (!totpCode) {
      s.auth.errors = { totpCode: "Nhập mã xác thực 2 lớp (2FA)." };
      render();
      return true;
    }
    s.auth.busy = true;
    s.auth.errors = {};
    render();
    try {
      await api("/oauth/app-session", "POST", { code: s.auth.oauth2faCode, totpCode });
      s.auth.oauth2faCode = "";
      if (signedIn) await signedIn((await api("/me")).user, "Chào mừng trở lại");
      return true;
    } catch (err) {
      s.auth.errors = err.data?.requires2fa ? { totpCode: err.message } : { _form: err.message };
      if (err.status === 401) s.auth.oauth2faCode = "";
    } finally {
      s.auth.busy = false;
    }
    render();
    return true;
  }
  if (!form.matches("[data-2fa-setup],[data-2fa-enable],[data-2fa-disable],[data-2fa-recovery]")) return false;
  if (s.me?.id) twoFactorState.userId = String(s.me.id);
  const f = new FormData(form);
  twoFactorState.busy = true;
  render();
  try {
    if (form.matches("[data-2fa-setup]")) {
      const r = await api("/me/2fa/setup", "POST", { password: String(f.get("password") || "") });
      twoFactorState.setup = r;
      twoFactorState.pending = true;
      toast("Đã tạo khóa 2FA. Hãy nhập mã 6 số để kích hoạt.");
    } else if (form.matches("[data-2fa-enable]")) {
      const r = await api("/me/2fa/enable", "POST", { code: String(f.get("code") || "") });
      twoFactorState.enabled = true;
      twoFactorState.pending = false;
      twoFactorState.recoveryRemaining = Number(r.recoveryRemaining || 8);
      twoFactorState.freshBackup = twoFactorState.setup?.backupCodes || null;
      twoFactorState.setup = null;
      if (s.me) s.me.twoFactorEnabled = true;
      toast("Đã bật xác thực 2 lớp.");
    } else if (form.matches("[data-2fa-disable]")) {
      await api("/me/2fa/disable", "POST", { password: String(f.get("password") || ""), code: String(f.get("code") || "") });
      Object.assign(twoFactorState, { enabled: false, pending: false, recoveryRemaining: 0, setup: null, freshBackup: null });
      if (s.me) s.me.twoFactorEnabled = false;
      toast("Đã tắt xác thực 2 lớp.");
    } else if (form.matches("[data-2fa-recovery]")) {
      const r = await api("/me/2fa/recovery", "POST", { password: String(f.get("password") || ""), code: String(f.get("code") || "") });
      twoFactorState.freshBackup = r.backupCodes || [];
      twoFactorState.recoveryRemaining = Number(r.recoveryRemaining || 0);
      toast("Đã tạo bộ mã dự phòng mới.");
    }
  } catch (err) {
    toast(err.message);
  } finally {
    twoFactorState.busy = false;
    render();
  }
  return true;
}

export async function openEditMessageDialog(message, target, { api, ic, esc, toast, loadChat, loadInbox, render }) {
  const d = document.createElement("dialog");
  d.className = "kn-feature-sheet";
  d.setAttribute("aria-label", "Chỉnh sửa tin nhắn");
  d.innerHTML = `<form><div class="sheet-head"><h2>Chỉnh sửa tin nhắn</h2><button type="button" data-close aria-label="Đóng">${ic("x")}</button></div><label class="v2-field">Nội dung mới<textarea name="body" rows="3" maxlength="2000" required>${esc(message.body || "")}</textarea></label><div class="row"><button type="button" class="secondary" data-close>Huỷ</button><button type="submit" class="primary">Lưu thay đổi</button></div></form>`;
  d.querySelectorAll("[data-close]").forEach((b) => (b.onclick = () => d.close()));
  d.querySelector("form").onsubmit = async (e) => {
    e.preventDefault();
    const clean = String(new FormData(e.target).get("body") || "").trim();
    if (!clean) return;
    const submit = d.querySelector("[type=submit]");
    submit.disabled = true;
    try {
      const kind = target.isGroup ? "group" : "direct";
      await api(`/chat-messages/${kind}/${encodeURIComponent(message.id)}`, "PATCH", { body: clean });
      d.close();
      await Promise.all([loadChat(target), loadInbox()]);
      toast("Đã chỉnh sửa tin nhắn");
      render();
    } catch (err) {
      toast(err.message);
      submit.disabled = false;
    }
  };
  d.addEventListener("close", () => d.remove(), { once: true });
  document.body.append(d);
  d.showModal();
}

export async function openGroupPollsDialog(group, { api, s, ic, esc, toast, knConfirm }) {
  const d = document.createElement("dialog");
  d.className = "kn-feature-sheet v2-polls-dialog";
  d.setAttribute("aria-label", "Bình chọn nhóm");
  const isManager = group.owner === s.me.id || (group.members || []).some((u) => u.id === s.me.id && u.groupRole === "deputy");
  let polls = [];

  async function refresh() {
    const r = await api(`/groups/${encodeURIComponent(group.id)}/polls`);
    polls = r.polls || [];
    paint();
  }

  function paint() {
    const listHtml = polls.length
      ? polls
          .map((p) => {
            const canManage = p.creatorId === s.me.id || isManager;
            const total = Math.max(1, p.totalVotes || 0);
            const opts = (p.options || [])
              .map((o) => {
                const pct = p.totalVotes ? Math.round((o.votes / total) * 100) : 0;
                return `<button type="button" class="v2-poll-opt ${o.voted ? "voted" : ""}" data-vote="${esc(p.id)}:${esc(o.id)}" ${p.closed ? "disabled" : ""}><progress class="v2-poll-bar" max="100" value="${pct}" aria-hidden="true"></progress><span class="v2-poll-label">${o.voted ? "✓ " : ""}${esc(o.label)}</span><b>${o.votes} (${pct}%)</b></button>`;
              })
              .join("");
            return `<article class="v2-poll-card"><header><strong>${esc(p.question)}</strong><small>${esc(p.creator?.name || "")} · ${p.totalVoters || 0} người chọn${p.multiple ? " · Chọn nhiều" : ""}${p.closed ? " · Đã đóng" : ""}</small></header><div class="v2-poll-opts">${opts}</div>${canManage ? `<div class="row">${!p.closed ? `<button type="button" class="secondary" data-poll-close="${esc(p.id)}">Đóng bình chọn</button>` : ""}<button type="button" class="secondary" data-poll-del="${esc(p.id)}">Xoá</button></div>` : ""}</article>`;
          })
          .join("")
      : `<p class="body-copy">Nhóm chưa có bình chọn nào. Tạo bình chọn đầu tiên bên dưới.</p>`;

    d.innerHTML = `<div class="sheet-head"><h2>Bình chọn · ${esc(group.name)}</h2><button type="button" data-close aria-label="Đóng">${ic("x")}</button></div>
      <div class="v2-polls-list">${listHtml}</div>
      <details class="v2-poll-create"${!polls.length ? " open" : ""}><summary>+ Tạo bình chọn mới</summary>
        <form data-poll-form class="settings-section">
          <label class="v2-field">Câu hỏi<input name="question" maxlength="200" placeholder="Cuối tuần đi đâu?" required></label>
          <label class="v2-field">Các lựa chọn (mỗi dòng 1 lựa chọn, 2–10 mục)<textarea name="options" rows="4" placeholder="Đà Lạt&#10;Vũng Tàu&#10;Phú Quốc" required></textarea></label>
          <label class="setting-toggle"><span><strong>Cho phép chọn nhiều</strong></span><input type="checkbox" name="multiple"></label>
          <button type="submit" class="primary">Đăng bình chọn</button>
        </form>
      </details>`;

    d.querySelector("[data-close]").onclick = () => d.close();
    d.querySelectorAll("[data-vote]").forEach((btnEl) => {
      btnEl.onclick = async () => {
        const [pollId, optId] = btnEl.dataset.vote.split(":");
        const p = polls.find((x) => x.id === pollId);
        if (!p || p.closed) return;
        let nextIds;
        if (p.multiple) {
          const cur = new Set(p.myOptionIds || []);
          if (cur.has(optId)) cur.delete(optId);
          else cur.add(optId);
          nextIds = [...cur];
        } else {
          nextIds = (p.myOptionIds || []).includes(optId) ? [] : [optId];
        }
        try {
          await api(`/groups/${encodeURIComponent(group.id)}/polls/${encodeURIComponent(pollId)}/vote`, "POST", { optionIds: nextIds });
          await refresh();
        } catch (err) {
          toast(err.message);
        }
      };
    });
    d.querySelectorAll("[data-poll-close]").forEach((btnEl) => {
      btnEl.onclick = async () => {
        try {
          await api(`/groups/${encodeURIComponent(group.id)}/polls/${encodeURIComponent(btnEl.dataset.pollClose)}/close`, "POST", {});
          await refresh();
        } catch (err) {
          toast(err.message);
        }
      };
    });
    d.querySelectorAll("[data-poll-del]").forEach((btnEl) => {
      btnEl.onclick = async () => {
        if (!(await knConfirm("Xoá bình chọn này?"))) return;
        try {
          await api(`/groups/${encodeURIComponent(group.id)}/polls/${encodeURIComponent(btnEl.dataset.pollDel)}`, "DELETE");
          await refresh();
        } catch (err) {
          toast(err.message);
        }
      };
    });
    d.querySelector("[data-poll-form]")?.addEventListener("submit", async (e) => {
      e.preventDefault();
      const fd = new FormData(e.target);
      const question = String(fd.get("question") || "").trim();
      const options = String(fd.get("options") || "")
        .split(/\r?\n/)
        .map((x) => x.trim())
        .filter(Boolean);
      const multiple = fd.get("multiple") === "on";
      try {
        await api(`/groups/${encodeURIComponent(group.id)}/polls`, "POST", { question, options, multiple });
        toast("Đã tạo bình chọn nhóm");
        await refresh();
      } catch (err) {
        toast(err.message);
      }
    });
  }

  d.addEventListener("close", () => d.remove(), { once: true });
  document.body.append(d);
  d.showModal();
  d.innerHTML = `<div class="sheet-head"><h2>Bình chọn nhóm</h2><button type="button" data-close aria-label="Đóng">${ic("x")}</button></div><p class="body-copy">Đang tải…</p>`;
  d.querySelector("[data-close]").onclick = () => d.close();
  try {
    await refresh();
  } catch (err) {
    toast(err.message);
    d.close();
  }
}

// ---------- Group Voice / Video Call ----------
async function fetchIceServers(api) {
  try {
    const r = await api("/call-config");
    if (Array.isArray(r.iceServers) && r.iceServers.length) return r.iceServers;
  } catch {}
  return [{ urls: "stun:stun.l.google.com:19302" }];
}

function escHtml(v) {
  return String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

function renderGroupCallOverlay() {
  document.querySelector(".v2-gcall-dock")?.remove();
  if (!groupCallState.activeGroupId) return;
  const dock = document.createElement("section");
  dock.className = "v2-gcall-dock panel";
  dock.setAttribute("aria-label", "Cuộc gọi nhóm");
  const tiles = groupCallState.participants
    .map((p) => {
      const isSelf = p.peerId === groupCallState.selfId;
      return `<div class="v2-gcall-tile" data-gcall-peer="${escHtml(p.peerId)}"><video autoplay playsinline ${isSelf ? "muted" : ""}></video><span class="v2-gcall-name">${escHtml(p.name)}${isSelf ? " (Bạn)" : ""}${p.muted ? " 🔇" : ""}</span></div>`;
    })
    .join("");
  dock.innerHTML = `<div class="v2-gcall-head"><strong>Gọi nhóm · ${escHtml(groupCallState.groupName)} (${groupCallState.participants.length})</strong><div class="row"><button type="button" data-gc="mic" class="secondary">${groupCallState.muted ? "Bật mic" : "Tắt mic"}</button>${groupCallState.mode === "video" ? `<button type="button" data-gc="cam" class="secondary">${groupCallState.videoOff ? "Bật cam" : "Tắt cam"}</button>` : ""}<button type="button" data-gc="leave" class="danger">Rời gọi</button></div></div><div class="v2-gcall-grid">${tiles}</div>`;

  dock.querySelectorAll("[data-gcall-peer]").forEach((tile) => {
    const peerId = tile.dataset.gcallPeer;
    const video = tile.querySelector("video");
    const stream = peerId === groupCallState.selfId ? groupCallState.stream : groupCallState.streams.get(peerId);
    if (stream) {
      video.srcObject = stream;
      video.play().catch(() => {});
    }
  });
  dock.querySelector("[data-gc=mic]").onclick = () => {
    groupCallState.muted = !groupCallState.muted;
    groupCallState.stream?.getAudioTracks().forEach((t) => (t.enabled = !groupCallState.muted));
    groupCallState._socketSend?.({ type: "group-call-media", groupId: groupCallState.activeGroupId, muted: groupCallState.muted });
    renderGroupCallOverlay();
  };
  dock.querySelector("[data-gc=cam]")?.addEventListener("click", () => {
    groupCallState.videoOff = !groupCallState.videoOff;
    groupCallState.stream?.getVideoTracks().forEach((t) => (t.enabled = !groupCallState.videoOff));
    groupCallState._socketSend?.({ type: "group-call-media", groupId: groupCallState.activeGroupId, video: !groupCallState.videoOff });
    renderGroupCallOverlay();
  });
  dock.querySelector("[data-gc=leave]").onclick = () => leaveGroupCall(true);
  document.body.append(dock);
}

async function createMeshPeer(peerId, offer, { api, socketSend }) {
  const groupId = groupCallState.activeGroupId;
  if (!groupId) return null;
  const existing = groupCallState.peers.get(peerId);
  if (existing) existing.close();
  const iceServers = await fetchIceServers(api);
  if (groupCallState.activeGroupId !== groupId) return null;
  const pc = new RTCPeerConnection({ iceServers });
  pc.pendingCandidates = [];
  groupCallState.peers.set(peerId, pc);
  if (groupCallState.stream) {
    for (const track of groupCallState.stream.getTracks()) pc.addTrack(track, groupCallState.stream);
  }
  pc.onicecandidate = (e) => {
    if (e.candidate && groupCallState.activeGroupId === groupId) {
      socketSend({ type: "group-call-signal", groupId, to: peerId, candidate: e.candidate.toJSON() });
    }
  };
  pc.ontrack = (e) => {
    if (groupCallState.activeGroupId !== groupId) return;
    const stream = e.streams[0] || new MediaStream([e.track]);
    groupCallState.streams.set(peerId, stream);
    renderGroupCallOverlay();
  };
  if (offer) {
    const desc = await pc.createOffer();
    if (groupCallState.activeGroupId !== groupId) {
      pc.close();
      return null;
    }
    await pc.setLocalDescription(desc);
    if (groupCallState.activeGroupId !== groupId) {
      pc.close();
      return null;
    }
    socketSend({ type: "group-call-signal", groupId, to: peerId, description: pc.localDescription.toJSON() });
  }
  return pc;
}

export async function startGroupCall(group, mode, { api, ensureSocket, socketSend, toast, busy = false }) {
  if (busy) {
    toast("Kết thúc cuộc gọi hoặc buổi live hiện tại trước khi gọi nhóm.");
    return;
  }
  if (groupCallState.activeGroupId === group.id) return;
  if (groupCallState.activeGroupId) leaveGroupCall(true);
  groupCallState._socketSend = socketSend;
  groupCallState._api = api;
  try {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true, video: mode === "video" ? { facingMode: "user", width: { ideal: 640 }, height: { ideal: 480 } } : false });
    groupCallState.stream = stream;
    groupCallState.activeGroupId = group.id;
    groupCallState.groupName = group.name || "Nhóm";
    groupCallState.mode = mode === "video" ? "video" : "audio";
    groupCallState.muted = false;
    groupCallState.videoOff = false;
    await ensureSocket();
    socketSend({ type: "group-call-join", groupId: group.id, mode: groupCallState.mode });
    renderGroupCallOverlay();
  } catch (err) {
    toast("Không mở được micro/camera cho cuộc gọi nhóm: " + err.message);
    leaveGroupCall(false);
  }
}

export function leaveGroupCall(notify = true) {
  const gid = groupCallState.activeGroupId;
  if (notify && gid) groupCallState._socketSend?.({ type: "group-call-leave", groupId: gid });
  for (const pc of groupCallState.peers.values()) pc.close();
  groupCallState.peers.clear();
  groupCallState.streams.clear();
  groupCallState.stream?.getTracks().forEach((t) => t.stop());
  groupCallState.stream = null;
  groupCallState.activeGroupId = "";
  groupCallState.selfId = "";
  groupCallState.participants = [];
  document.querySelector(".v2-gcall-dock")?.remove();
}

export function resetGroupCallState() {
  leaveGroupCall(false);
  groupCallState.bannerByGroup.clear();
  groupCallState._socketSend = null;
  groupCallState._api = null;
}

export async function handleGroupCallSignal(m, { api, socketSend, toast, render }) {
  if (!String(m.type || "").startsWith("group-call-")) return false;
  groupCallState._socketSend = socketSend;
  groupCallState._api = api;
  if (m.type === "group-call-state") {
    groupCallState.bannerByGroup.set(m.groupId, { active: !!m.active, mode: m.mode, participants: m.participants || [] });
    if (groupCallState.activeGroupId === m.groupId) {
      groupCallState.participants = m.participants || [];
      renderGroupCallOverlay();
    }
    render();
    return true;
  }
  if (m.type === "group-call-joined" && m.groupId === groupCallState.activeGroupId) {
    groupCallState.selfId = m.selfId;
    groupCallState.participants = m.participants || [];
    renderGroupCallOverlay();
    for (const peerId of m.peers || []) {
      await createMeshPeer(peerId, true, { api, socketSend });
    }
    return true;
  }
  if (m.type === "group-call-peer-left" && m.groupId === groupCallState.activeGroupId) {
    groupCallState.peers.get(m.peerId)?.close();
    groupCallState.peers.delete(m.peerId);
    groupCallState.streams.delete(m.peerId);
    renderGroupCallOverlay();
    return true;
  }
  if (m.type === "group-call-signal" && m.groupId === groupCallState.activeGroupId) {
    let pc = groupCallState.peers.get(m.from);
    if (!pc) pc = await createMeshPeer(m.from, false, { api, socketSend });
    if (!pc || m.groupId !== groupCallState.activeGroupId) return true;
    if (m.description) {
      await pc.setRemoteDescription(m.description);
      const queued = pc.pendingCandidates || [];
      pc.pendingCandidates = [];
      for (const cand of queued) {
        await pc.addIceCandidate(cand).catch(() => {});
      }
      if (m.description.type === "offer") {
        await pc.setLocalDescription(await pc.createAnswer());
        socketSend({ type: "group-call-signal", groupId: m.groupId, to: m.from, description: pc.localDescription.toJSON() });
      }
    } else if (m.candidate) {
      if (pc.remoteDescription) {
        await pc.addIceCandidate(m.candidate).catch(() => {});
      } else {
        (pc.pendingCandidates ||= []).push(m.candidate);
      }
    }
    return true;
  }
  if (m.type === "group-call-ended") {
    if (m.groupId) groupCallState.bannerByGroup.delete(m.groupId);
    if (m.groupId && m.groupId === groupCallState.activeGroupId) {
      leaveGroupCall(false);
      toast("Cuộc gọi nhóm đã kết thúc.");
    }
    render();
    return true;
  }
  if (m.type === "group-call-error") {
    toast(m.message || "Không thể tham gia cuộc gọi nhóm.");
    if (m.groupId === groupCallState.activeGroupId && !groupCallState.selfId) leaveGroupCall(false);
    return true;
  }
  return true;
}

export function groupCallBannerHtml(groupId, { esc, ic, btn }) {
  const b = groupCallState.bannerByGroup.get(groupId);
  if (!b?.active || !b.participants?.length) return "";
  if (groupCallState.activeGroupId === groupId) return "";
  return `<div class="v2-gcall-banner">${ic(b.mode === "video" ? "video" : "phone")}<span>Cuộc gọi nhóm đang diễn ra · ${b.participants.length} người</span>${btn("Tham gia", "phone", b.mode === "video" ? "group-call-video" : "group-call-audio", "primary")}</div>`;
}

export async function refreshGroupCallBanner(groupId, api) {
  try {
    const r = await api(`/groups/${encodeURIComponent(groupId)}/call`);
    groupCallState.bannerByGroup.set(groupId, { active: !!r.active, mode: r.mode, participants: r.participants || [] });
  } catch {}
}

export function copyTwoFactorSecret(toast) {
  if (!twoFactorState.setup?.secret) return;
  navigator.clipboard?.writeText(twoFactorState.setup.secret).then(() => toast("Đã sao chép khóa 2FA")).catch(() => toast("Hãy chọn và sao chép thủ công."));
}
