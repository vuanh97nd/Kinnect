import { createEffects, effectPicker } from "./camera.js?v=3";
const $ = (id) => document.getElementById(id);
// stream: luồng đã qua hiệu ứng (gửi cho người xem); rawStream: camera/micro gốc.
let rawStream = null,
  fx = null;
function stopCamera() {
  fx?.stop();
  fx = null;
  rawStream?.getTracks().forEach((t) => t.stop());
  rawStream = null;
  $("live-fx")?.replaceChildren();
}
let stream = null,
  role = null,
  busy = false,
  connected = false,
  rooms = [],
  hostUserId = null;
const peers = new Map(),
  pending = new Map();
let ws;
const notify = (text) => ($("notice").textContent = text);
const send = (data) => {
  if (ws?.readyState === WebSocket.OPEN) ws.send(JSON.stringify(data));
};
function cleanup() {
  for (const p of peers.values()) p.close();
  peers.clear();
  pending.clear();
  stream?.getTracks().forEach((t) => t.stop());
  stream = null;
  stopCamera();
  role = null;
  window.dispatchEvent(
    new CustomEvent("kinnect-live-state", { detail: false }),
  );
  hostUserId = null;
  $("report-live").hidden = true;
  $("video").srcObject = null;
  $("live").hidden = true;
  $("lobby").hidden = false;
  $("messages").replaceChildren();
  $("count").textContent = "0 người xem";
  $("mic").textContent = "Tắt micro";
  $("camera").textContent = "Tắt camera";
}
function peer(id) {
  if (peers.has(id)) return peers.get(id);
  // Host candidates work on local networks. Public deployment needs configured STUN/TURN.
  const p = new RTCPeerConnection({ iceServers: [] });
  peers.set(id, p);
  p.onicecandidate = (e) => {
    if (e.candidate)
      send({ type: "signal", to: id, candidate: e.candidate.toJSON() });
  };
  p.ontrack = (e) => {
    $("video").srcObject = e.streams[0];
    $("video")
      .play()
      .catch(() => notify("Chạm vào video để bắt đầu phát."));
  };
  p.onconnectionstatechange = () => {
    if (p.connectionState === "failed")
      notify(
        "Không kết nối được video. Kết nối qua Internet cần máy chủ TURN; bản hiện tại dành cho thử nghiệm cục bộ.",
      );
  };
  if (role === "host") stream.getTracks().forEach((t) => p.addTrack(t, stream));
  return p;
}
export function connectLive() {
  ws = new WebSocket(
    `${location.protocol === "https:" ? "wss:" : "ws:"}//${location.host}`,
  );
  ws.onopen = () => {
    connected = true;
    $("connection").textContent = "Đã kết nối";
  };
  ws.onclose = () => {
    connected = false;
    cleanup();
    $("connection").textContent = "Mất kết nối";
    notify("Mất kết nối máy chủ. Tải lại trang để kết nối lại.");
  };
  ws.onerror = () => notify("Không kết nối được máy chủ livestream.");
  ws.onmessage = async (event) => {
    try {
      const m = JSON.parse(event.data);
      if (m.type === "notifications-changed") window.dispatchEvent(new Event("kinnect-notifications"));
      if (m.type === "rooms") {
        rooms = m.rooms;
        renderRooms();
      }
      if (m.type === "joined") {
        role = m.role;
        window.dispatchEvent(
          new CustomEvent("kinnect-live-state", { detail: true }),
        );
        hostUserId = m.hostUserId || null;
        $("report-live").hidden = role === "host";
        $("gift").hidden = $("gift-kind").hidden = role === "host";
        $("lobby").hidden = true;
        $("live").hidden = false;
        $("room-title").textContent = m.room.title;
        $("mic").hidden = $("camera").hidden = role !== "host";
        $("leave").textContent =
          role === "host" ? "Kết thúc livestream" : "Rời phòng";
        $("video").muted = role === "host";
        $("video").controls = role !== "host";
        if (role === "host") {
          $("video").srcObject = stream;
          if (fx) $("live-fx")?.replaceChildren(effectPicker(fx, { dark: false }));
        }
        notify(
          role === "host"
            ? "Bạn đang phát trực tiếp."
            : "Đang kết nối với người phát…",
        );
      }
      if (m.type === "peer" && role === "host") {
        const p = peer(m.id);
        await p.setLocalDescription(await p.createOffer());
        send({
          type: "signal",
          to: m.id,
          description: p.localDescription.toJSON(),
        });
      }
      if (m.type === "signal") {
        const p = peer(m.from);
        if (m.description) {
          await p.setRemoteDescription(m.description);
          for (const c of pending.get(m.from) || []) await p.addIceCandidate(c);
          pending.delete(m.from);
          if (m.description.type === "offer") {
            await p.setLocalDescription(await p.createAnswer());
            send({
              type: "signal",
              to: m.from,
              description: p.localDescription.toJSON(),
            });
          }
        } else if (m.candidate) {
          if (p.remoteDescription) await p.addIceCandidate(m.candidate);
          else {
            const q = pending.get(m.from) || [];
            q.push(m.candidate);
            pending.set(m.from, q);
          }
        }
      }
      if (m.type === "peer-left") {
        peers.get(m.id)?.close();
        peers.delete(m.id);
        pending.delete(m.id);
      }
      if (m.type === "count") $("count").textContent = `${m.viewers} người xem`;
      if (m.type === "gift") {
        const item = document.createElement("p");
        item.textContent =
          m.name +
          " gửi " +
          ({ heart: "♥", rainbow: "🌈", star: "★" }[m.kind] || "quà") +
          " · quà thử nghiệm miễn phí";
        $("messages").append(item);
      }
      if (m.type === "chat") {
        const p = document.createElement("p");
        const b = document.createElement("strong");
        b.textContent = m.name + ": ";
        p.append(b, document.createTextNode(m.text));
        $("messages").append(p);
        if ($("messages").children.length > 200)
          $("messages").firstChild.remove();
        $("messages").scrollTop = $("messages").scrollHeight;
      }
      if (m.type === "ended") {
        cleanup();
        notify("Buổi livestream đã kết thúc.");
      }
      if (m.type === "error") {
        if (!role && stream) {
          stream.getTracks().forEach((t) => t.stop());
          stream = null;
          stopCamera();
        }
        notify(m.message);
      }
    } catch {
      notify("Không thể thiết lập kết nối video. Hãy rời phòng và thử lại.");
    }
  };
}
export function disconnectLive() {
  cleanup();
  ws?.close();
}
$("create").onsubmit = async (e) => {
  e.preventDefault();
  if (busy) return;
  if (!connected) return notify("Máy chủ chưa kết nối.");
  busy = true;
  $("start").disabled = true;
  try {
    if (!navigator.mediaDevices?.getUserMedia)
      throw Error("Camera cần HTTPS hoặc localhost.");
    rawStream = await navigator.mediaDevices.getUserMedia({
      video: { width: { ideal: 1280 }, height: { ideal: 720 } },
      audio: true,
    });
    // Hiệu ứng (bộ lọc, làm mịn, sticker) áp lên hình gửi cho người xem.
    fx = createEffects(rawStream, { width: 720, height: 1280 });
    if (window.kinnectPendingFx) {
      fx.set(window.kinnectPendingFx);
      window.kinnectPendingFx = null;
    }
    stream = fx.stream;
    send({ type: "create", name: $("name").value, title: $("title").value });
  } catch (error) {
    notify("Không mở được camera/micro: " + error.message);
  } finally {
    busy = false;
    $("start").disabled = false;
  }
};
$("leave").onclick = () => {
  send({ type: "leave" });
  cleanup();
  notify("Bạn đã rời phòng.");
};
$("chat").onsubmit = (e) => {
  e.preventDefault();
  send({ type: "chat", text: $("message").value });
  $("message").value = "";
};
for (const [id, kind, label] of [
  ["mic", "audio", "micro"],
  ["camera", "video", "camera"],
])
  $(id).onclick = () => {
    const tracks = stream?.getTracks().filter((t) => t.kind === kind) || [];
    const enabled = !tracks[0]?.enabled;
    tracks.forEach((t) => (t.enabled = enabled));
    $(id).textContent = (enabled ? "Tắt " : "Bật ") + label;
  };
window.addEventListener("pagehide", () => {
  cleanup();
  ws?.close();
});

function renderRooms() {
  const query = $("search").value.trim().toLocaleLowerCase("vi");
  const filtered = rooms.filter((r) =>
    (r.title + " " + r.host).toLocaleLowerCase("vi").includes(query),
  );
  if ($("sort").value === "popular")
    filtered.sort((a, b) => b.viewers - a.viewers);
  else filtered.reverse();
  $("rooms").replaceChildren();
  if (!filtered.length)
    $("rooms").textContent = query
      ? "Không tìm thấy phòng phù hợp."
      : "Chưa có ai lên sóng. Hãy mở đầu cuộc trò chuyện!";
  for (const r of filtered) {
    const card = document.createElement("article");
    card.className = "room";
    const title = document.createElement("h3");
    title.textContent = r.title;
    const desc = document.createElement("p");
    desc.textContent = `${r.host} · ${r.viewers} người xem`;
    const b = document.createElement("button");
    b.textContent = "Vào xem";
    b.onclick = () => {
      if (!$("name").value.trim())
        return notify("Nhập tên hiển thị trước khi vào xem.");
      send({ type: "join", room: r.id, name: $("name").value });
    };
    card.append(title, desc, b);
    $("rooms").append(card);
  }
}

$("search").oninput = renderRooms;
$("sort").onchange = renderRooms;
try {
  $("name").value = localStorage.getItem("kinnect-name") || "";
} catch {}
$("name").addEventListener("change", () => {
  try {
    localStorage.setItem("kinnect-name", $("name").value.trim());
  } catch {}
});

$("report-live").onclick = () => {
  if (hostUserId)
    window.dispatchEvent(
      new CustomEvent("kinnect-report", {
        detail: { targetType: "user", targetId: hostUserId },
      }),
    );
};

window.addEventListener("kinnect-background", () => {
  if (role) {
    send({ type: "leave" });
    cleanup();
    notify("Đã dừng livestream khi mở ứng dụng khác.");
  }
});

$("gift").onclick = () => send({ type: "gift", kind: $("gift-kind").value });
