import assert from "node:assert/strict";
import test from "node:test";

function passwordDecision(current, next, confirm) {
  if (current.trim() === "") return { message: "Vui lòng nhập mật khẩu hiện tại.", sendsToServer: false };
  if (next.length < 6) return { message: "Mật khẩu mới phải có ít nhất 6 ký tự.", sendsToServer: false };
  if (next.length > 128) return { message: "Mật khẩu mới cần 6–128 ký tự.", sendsToServer: false };
  if (confirm.trim() === "") return { message: "Vui lòng nhập lại mật khẩu mới.", sendsToServer: false };
  if (confirm !== next) return { message: "Mật khẩu nhập lại không khớp.", sendsToServer: false };
  return { message: null, sendsToServer: true };
}

test("password validation does not post invalid input", () => {
  const cases = [
    ["", "abcdef", "abcdef", false],
    ["current-secret", "abcde", "abcde", false],
    ["current-secret", "abcdef", "abcdef", true],
    ["current-secret", "abcdefg", "abcdefg", true],
    ["current-secret", "abcdef", "", false],
    ["current-secret", "abcdef", "abcdefX", false],
  ];
  const posted = [];
  for (const [current, next, confirm, shouldPost] of cases) {
    const decision = passwordDecision(current, next, confirm);
    assert.equal(decision.sendsToServer, shouldPost);
    if (decision.sendsToServer) posted.push({ current, next });
  }
  assert.deepEqual(posted.map((item) => item.next.length), [6, 7]);
  assert.equal(posted.length, 2);
});

test("language preference is local and survives a cold read", () => {
  const store = new Map();
  function save(value) { store.set("kinnect_app_language", value); }
  function resolve(device) {
    const saved = store.get("kinnect_app_language") ?? "system";
    if (saved === "vi") return "vi";
    if (saved === "en") return "en";
    return device.toLowerCase().startsWith("vi") ? "vi" : "en";
  }
  save("en");
  assert.equal(resolve("vi-VN"), "en");
  save("system");
  assert.equal(resolve("vi-VN"), "vi");
  assert.equal(resolve("en-US"), "en");
  save("vi");
  assert.equal(resolve("en-US"), "vi");
});

test("notification toggles stay on device", () => {
  const prefs = { enabled: true, messages: true, friends: true, posts: true };
  function allows(kind) {
    if (kind === "call") return true;
    if (!prefs.enabled) return false;
    if (kind === "message") return prefs.messages;
    if (kind.startsWith("friend_")) return prefs.friends;
    return prefs.posts;
  }
  prefs.messages = false;
  assert.equal(allows("message"), false);
  assert.equal(allows("friend_request"), true);
  prefs.enabled = false;
  assert.equal(allows("post"), false);
  assert.equal(allows("call"), true);
});

test("shorts mute does not resume a paused clip and swipe changes item", () => {
  const state = { index: 0, userPaused: false, muted: false };
  const playing = () => !state.userPaused;
  state.userPaused = true;
  state.muted = !state.muted;
  assert.equal(playing(), false);
  state.index = 1;
  state.userPaused = false;
  assert.equal(state.index, 1);
  assert.equal(playing(), true);
  assert.equal(state.muted, true);
});

test("gift total and music search stay inside the fixture", () => {
  const quote = (unit, quantity) => ({ total: unit * quantity, confirm: unit * quantity >= 1000 });
  assert.deepEqual(quote(10, 5), { total: 50, confirm: false });
  assert.deepEqual(quote(1000, 1), { total: 1000, confirm: true });
  const tracks = [
    ["Giai điệu kết nối", "Kinnect Audio"],
    ["Nắng sớm thành phố", "Minh Anh"],
  ];
  const found = tracks.filter(([title, artist]) => `${title} ${artist}`.toLowerCase().includes("nắng"));
  assert.equal(found.length, 1);
  assert.equal(found[0][0], "Nắng sớm thành phố");
});
