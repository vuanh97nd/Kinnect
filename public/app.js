import { createEffects, effectPicker } from "./camera.js?v=5";
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
let liveRevision = 0;
let reconnectTimer = 0;
let reconnectDelay = 1000;
let liveEnabled = false;
const notify = (text) => ($("notice").textContent = text);
const send = (data) => {
  if (ws?.readyState === WebSocket.OPEN) ws.send(JSON.stringify(data));
};
function cleanup() {
  liveRevision++;
  for (const p of peers.values()) p.close();
  peers.clear();
  pending.clear();
  stream?.getTracks().forEach((t) => t.stop());
  stream = null;
  stopCamera();
  role = null;
  watchingRoom=null;switchingLive=false;
  updateLiveSwipe();
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
// Vào thẳng một phòng live (từ tab "Trực tiếp" ở trang Video).
let pendingJoin = null, watchingRoom = null, switchingLive = false;
function updateLiveSwipe(){
 const viewing=role==='viewer';
 $('live-swipe-controls').hidden=!viewing;
 for(const id of ['live-previous','live-next'])$(id).disabled=!viewing||rooms.length<2||switchingLive;
}
function switchLive(direction){
 if(role!=='viewer'||switchingLive)return;
 const list=rooms.filter(r=>r.id!==watchingRoom);
 if(!list.length)return notify('Chưa có buổi trực tiếp khác.');
 const current=rooms.findIndex(r=>r.id===watchingRoom),next=rooms[(Math.max(0,current)+direction+rooms.length)%rooms.length];
 if(!next||next.id===watchingRoom)return;
 send({type:'leave'});cleanup();switchingLive=true;joinLiveRoom(next.id);updateLiveSwipe();
}
$('live-next').onclick=()=>switchLive(1);
$('live-previous').onclick=()=>switchLive(-1);
$('live-browse').addEventListener('click',()=>{if(role==='viewer'){send({type:'leave'});cleanup();}});
let swipeStart=null,lastWheel=0;
const liveSurface=$('video').closest('.video-wrap');
liveSurface.addEventListener('touchstart',e=>{const t=e.touches[0];swipeStart=e.touches.length===1?{x:t.clientX,y:t.clientY}:null;},{passive:true});
liveSurface.addEventListener('touchmove',e=>{if(role!=='viewer'||!swipeStart)return;const t=e.touches[0],dy=t.clientY-swipeStart.y;if(Math.abs(dy)>12&&Math.abs(dy)>Math.abs(t.clientX-swipeStart.x))e.preventDefault();},{passive:false});
liveSurface.addEventListener('touchend',e=>{if(!swipeStart)return;const t=e.changedTouches[0],dy=t.clientY-swipeStart.y,dx=t.clientX-swipeStart.x;swipeStart=null;if(Math.abs(dy)>60&&Math.abs(dy)>Math.abs(dx)*1.4)switchLive(dy<0?1:-1);},{passive:true});
liveSurface.addEventListener('touchcancel',()=>{swipeStart=null;},{passive:true});
liveSurface.addEventListener('wheel',e=>{if(role!=='viewer'||Math.abs(e.deltaY)<40||Date.now()-lastWheel<800)return;e.preventDefault();lastWheel=Date.now();switchLive(e.deltaY>0?1:-1);},{passive:false});
export function joinLiveRoom(id) {
  pendingJoin = id;
  if (ws && ws.readyState === WebSocket.OPEN) {
    send({ type: "join", room: id, name: $("name").value || "Khách" });
    pendingJoin = null;
  }
}
export function connectLive() {
  liveEnabled = true;
  clearTimeout(reconnectTimer);
  if (ws && [WebSocket.OPEN, WebSocket.CONNECTING].includes(ws.readyState)) return;
  const socket = ws = new WebSocket(
    `${location.protocol === "https:" ? "wss:" : "ws:"}//${location.host}`,
  );
  ws.onopen = () => {
    if (ws !== socket) return;
    reconnectDelay = 1000;
    connected = true;
    $("connection").textContent = "Đã kết nối";
  };
  ws.onclose = () => {
    if (ws !== socket) return;
    connected = false;
    window.dispatchEvent(new Event("kinnect-call-disconnected"));
    cleanup();
    $("connection").textContent = "Mất kết nối";
    if (liveEnabled) {
      notify("Mất kết nối livestream. Đang kết nối lại…");
      reconnectTimer = setTimeout(connectLive, reconnectDelay);
      reconnectDelay = Math.min(reconnectDelay * 2, 30000);
    }
  };
  ws.onerror = () => notify("Không kết nối được máy chủ livestream.");
  ws.onmessage = async (event) => {
    if (ws !== socket) return;
    try {
      const m = JSON.parse(event.data);
      if(String(m.type).startsWith("call-"))window.dispatchEvent(new CustomEvent("kinnect-call-event",{detail:m}));
      if (m.type === "notifications-changed") window.dispatchEvent(new Event("kinnect-notifications"));
      if (m.type === "rooms") {
        rooms = m.rooms;
        renderRooms();
        updateLiveSwipe();
        if (pendingJoin) { send({ type: "join", room: pendingJoin, name: $("name").value || "Khách" }); pendingJoin = null; }
      }
      if (m.type === "joined") {
        role = m.role;
        watchingRoom=m.room.id;switchingLive=false;updateLiveSwipe();
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
        switchingLive=false;updateLiveSwipe();
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
  liveEnabled = false;
  clearTimeout(reconnectTimer);
  connected = false;
  const previous = ws;
  ws = null;
  cleanup();
  previous?.close();
}
$("create").onsubmit = async (e) => {
  e.preventDefault();
  if (busy) return;
  if (!connected) return notify("Máy chủ chưa kết nối.");
  busy = true;
  const revision = liveRevision;
  $("start").disabled = true;
  try {
    if (!navigator.mediaDevices?.getUserMedia)
      throw Error("Camera cần HTTPS hoặc localhost.");
    const captured = await navigator.mediaDevices.getUserMedia({
      video: matchMedia("(pointer: coarse)").matches ? { facingMode: "user", width: { ideal: 720 }, height: { ideal: 1280 }, aspectRatio: { ideal: 9 / 16 } } : { facingMode: "user", width: { ideal: 1280 }, height: { ideal: 720 }, resizeMode: "none" },
      audio: true,
    });
    if (revision !== liveRevision || !connected) {
      captured.getTracks().forEach(t => t.stop());
      return;
    }
    // iPhone đôi khi trả hình ngang dù máy đang cầm dọc: xin lại khung dọc ngay trên track hiện tại.
    if (matchMedia("(pointer: coarse)").matches) {
      const track = captured.getVideoTracks()[0], s = track?.getSettings?.() || {};
      if ((s.width || 0) > (s.height || 0) && innerHeight > innerWidth)
        for (const c of [{ width: { exact: 720 }, height: { exact: 1280 } }, { aspectRatio: { exact: 9 / 16 } }, { width: { ideal: 480 }, height: { ideal: 640 } }]) {
          try { await track.applyConstraints({ facingMode: "user", ...c }); } catch { continue; }
          const n = track.getSettings();
          if ((n.width || 0) < (n.height || 0)) break;
        }
    }
    rawStream = captured;
    window.kinnectLiveCamera = captured;
    // Hiệu ứng (bộ lọc, làm mịn, sticker) áp lên hình gửi cho người xem.
    fx = createEffects(rawStream, { width: 720, height: 1280, portrait: matchMedia("(pointer: coarse)").matches });
    if (window.kinnectPendingFx) {
      fx.set(window.kinnectPendingFx);
      window.kinnectPendingFx = null;
    }
    stream = fx.stream;
    send({ type: "create", name: $("name").value, title: $("title").value });
  } catch (error) {
    stopCamera();
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
  clearTimeout(reconnectTimer);
  const previous = ws;
  ws = null;
  connected = false;
  cleanup();
  previous?.close();
});
window.addEventListener("pageshow", e => { if (e.persisted && liveEnabled) connectLive(); });
window.addEventListener("online", () => { if (liveEnabled) connectLive(); });

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
  if (role || busy || rawStream) {
    send({ type: "leave" });
    cleanup();
    notify("Đã dừng livestream khi mở ứng dụng khác.");
  }
});

$("gift").onclick = () => send({ type: "gift", kind: $("gift-kind").value });

export function sendCallSignal(message){if(ws?.readyState!==WebSocket.OPEN)throw Error("Chưa kết nối máy chủ. Vui lòng thử lại.");send(message);}
