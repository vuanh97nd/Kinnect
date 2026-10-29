// discover: UI functions share live application state through explicit accessors.
export function createDiscover(context) {
function userCard(u) {
  const card = context.node("article", undefined, "social-card person-tile");
  const photo = context.node("div", undefined, "tile-photo " + context.hue(u.id));
  photo.append(context.avatar(u));
  if(u.distanceLabel||u.distanceBand){photo.classList.add("has-distance");const distanceText=u.distanceLabel||u.distanceBand.replace("Gần bạn · dưới khoảng ","< ").replace("Khoảng ","");const distance=context.node("span",distanceText,"tile-chip");distance.title="Khoảng cách ước tính, làm tròn 100 m";photo.append(distance);}
  const head = context.node("button", undefined, "tile-name");
  head.type = "button";
  head.append(context.node("h3", u.name), context.node("p", "@" + u.username, "muted"));
  head.onclick = () => context.navigate("profile", { user: u.id });
  photo.append(head);
  photo.append(
    context.more([
      ["Chặn", async () => {
        if (!confirm("Chặn " + u.name + "? Hai bên sẽ không thấy nhau trong khám phá, bảng tin, chat và phòng live.")) return;
        await context.api("/users/" + u.id + "/block", "POST", {});
        context.status("Đã chặn " + u.name + ".");
        await context.navigate(context.tab);
      }],
      ["Báo cáo", () => context.report("user", u.id)],
    ]),
  );
  const presence = context.node("div", undefined, "presence-badges");
  if (u.isActive) presence.append(context.node("span", "● Online", "presence online"));
  if (u.isNew) presence.append(context.node("span", "Mới", "presence new-member"));
  photo.append(presence);
  card.append(photo, profileBadges(u));
  if (u.bio) card.append(context.node("p", u.bio, "tile-bio"));
  const tags = context.node("div", undefined, "tags");
  u.interests.slice(0, 4).forEach((v) => tags.append(context.node("span", v)));
  card.append(tags);
  if (u.score) card.append(context.node("p", u.score + " sở thích chung", "match"));
  const buttons = context.node("div", undefined, "card-actions");
  buttons.append(
    context.action(u.following ? "Bỏ theo dõi" : "Theo dõi", async () => {
      await context.api("/users/" + u.id + "/follow", u.following ? "DELETE" : "POST", {});
      await context.navigate(context.tab);
    }, u.following ? "secondary" : "follow"),
    context.action("Nhắn tin", () => context.openChat(u)),
  );
  const followButton=buttons.children[0],messageButton=buttons.children[1];
  followButton.setAttribute('aria-label',u.following?'Bỏ theo dõi':'Theo dõi');followButton.title=u.following?'Bỏ theo dõi':'Theo dõi';
  followButton.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="9" cy="7" r="4"/><path d="M2 21v-2a7 7 0 0 1 14 0v2"/>'+(u.following?'<path d="m17 9 2 2 4-5"/>':'<path d="M20 5v8m-4-4h8"/>')+'</svg>';
  messageButton.setAttribute('aria-label','Nhắn tin');messageButton.title='Nhắn tin';messageButton.innerHTML=context.reelIcon('comment');
  card.append(buttons);
  return card;
}

function profileBadges(user) {
  const box = context.node("div", undefined, "identity-badges");
  const genderIcons = { "Nam": "♂", "Nữ": "♀", "Nam chuyển giới": "⚧", "Nữ chuyển giới": "⚧", "Phi nhị nguyên": "◇" };
  const roles = { "Top": "↑", "Bottom": "↓", "Vers": "↕", "Vers Top": "↗", "Vers Bottom": "↘", "Side": "○" };
  const labels = [
    user.age ? [String(user.age) + " tuổi", "age"] : null,
    user.city ? ["⌖ " + user.city, "location"] : null,
    user.gender ? [(genderIcons[user.gender] || "◇") + " " + user.gender, "gender"] : null,
    user.orientation ? [user.orientation, "orientation"] : null,
    user.relationshipRole ? [(roles[user.relationshipRole] || "↕") + " " + user.relationshipRole, "role"] : null,
    user.pronouns ? [user.pronouns, "pronouns"] : null,
  ].filter(Boolean);
  for (const [label, kind] of labels) { const badge = context.node("span", label, "identity-badge badge-" + kind); badge.title = label; box.append(badge); }
  return box;
}

async function discover(panel, q = "") {
  let selected = context.discoveryMode, request = 0;
  const tools = context.node("section", undefined, "discovery-tools social-card");
  const chips = context.node("div", undefined, "chips discovery-tabs");
  chips.setAttribute("aria-label", "Lọc thành viên");
  for (const [label, value] of [["Gần đây", "nearby"], ["Mới", "new"], ["Đang online", "active"], ["Hợp gu", "interests"]]) {
    const b = context.node("button", label, "chip" + (value === selected ? " active" : "")); b.type = "button"; b.setAttribute("aria-pressed", String(value === selected));
    b.onclick = () => { selected = context.discoveryMode = value;context.replaceNavigationOptions({mode:value}); for (const c of chips.children) { c.classList.toggle("active", c === b); c.setAttribute("aria-pressed", String(c === b)); } if(value === "nearby"){if(!enable.disabled)enable.onclick();}else load().catch(showError); };
    chips.append(b);
  }
  const location = context.node("section", undefined, "nearby-consent");
  const locationText = context.node("p", "", "muted"); locationText.setAttribute("role", "status");
  const enable = context.node("button", "Bật vị trí", "secondary"); enable.type = "button";
  const disable = context.node("button", "Tắt", "ghost"); disable.type = "button";
  location.append(locationText, enable, disable); tools.append(chips, location); panel.append(tools);
  const heading = context.node("h3", "", "section-title discovery-results-title");
  const list = context.node("div", undefined, "people-grid"); panel.append(heading, list);
  function showError(e) { locationText.textContent = e.message; list.replaceChildren(context.empty("📍", "Chưa tải được thành viên", "Bạn có thể thử lại hoặc chọn Mới tham gia.")); }
  async function load() {
    const version = ++request, mode = selected;
    const own = (await context.api("/me")).user;
    if (version !== request) return;
    context.me = own;
    location.hidden = mode !== "nearby" || context.me.hasLocation;
    enable.textContent = "Bật vị trí";
    enable.hidden = context.me.hasLocation;
    disable.hidden = !context.me.hasLocation;
    locationText.textContent = context.me.hasLocation
      ? ""
      : "📍 Bật vị trí để thấy người gần bạn";
    const nearby = mode === "nearby" && context.me.hasLocation;
    heading.textContent = mode === "nearby" ? (nearby ? "Thành viên quanh bạn" : "Mới tham gia") : mode === "active" ? "Đang hoạt động" : mode === "interests" ? "Người cùng sở thích" : "Mới tham gia";
    list.replaceChildren(context.skeleton("grid"));
    const { users } = await context.api("/discover?q=" + encodeURIComponent(q) + (nearby ? "&nearby=1" : "") + "&sort=" + (mode === "nearby" ? "new" : mode));
    if (version !== request) return;
    list.replaceChildren(...users.map(userCard));
    if (!users.length) list.append(context.empty(nearby ? "📍" : "🔎", nearby ? "Chưa có thành viên quanh bạn" : mode === "active" ? "Chưa có ai đang hoạt động" : "Chưa tìm thấy ai", nearby ? "Chỉ những người đã bật vị trí trong 24 giờ gần nhất mới xuất hiện. Bạn có thể xem thêm ở Mới tham gia." : mode === "active" ? "Chưa có thành viên đang hoạt động. Hãy xem thêm ở Mới tham gia." : "Bổ sung sở thích hoặc thử bộ lọc khác."));
  }
  enable.onclick = async () => {
    enable.disabled = true;
    locationText.textContent = "Đang lấy vị trí của bạn…";
    try {
      if (!window.isSecureContext || !navigator.geolocation) throw Error("Mở Kinnect bằng HTTPS hoặc localhost để sử dụng vị trí.");
      const position = await new Promise((resolve, reject) => navigator.geolocation.getCurrentPosition(resolve, reject, { enableHighAccuracy: true, timeout: 20000, maximumAge: 60000 }));
      context.me = (await context.api("/me/location", "PATCH", { enabled: true, latitude: position.coords.latitude, longitude: position.coords.longitude })).user;
      context.lastGeoSync=Date.now();context.rememberLocation(true);context.startLocationTracking();
      await load();
    } catch (e) {
      locationText.textContent = e.code === 1 ? "Quyền vị trí đang bị chặn. Hãy cho phép vị trí trong quyền của trang rồi thử lại." : e.code === 2 ? "Chưa lấy được vị trí. Kiểm tra dịch vụ vị trí trên thiết bị rồi thử lại." : e.code === 3 ? "Lấy vị trí quá thời gian. Hãy thử lại ở nơi có tín hiệu tốt hơn." : e.message;
    } finally { enable.disabled = false; }
  };
  disable.onclick = async () => { disable.disabled = true; try { context.me = (await context.api("/me/location", "PATCH", { enabled: false })).user; context.rememberLocation(false);context.stopLocationTracking();await load(); } catch (e) { showError(e); } finally { disable.disabled = false; } };
  context.nearbyRefresh=()=>panel.isConnected&&selected==="nearby"?load().catch(showError):undefined;
  await load();
}

  return {userCard, profileBadges, discover};
}
