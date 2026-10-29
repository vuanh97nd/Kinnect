import { test, expect } from "@playwright/test";
async function signUp(page, name) {
  await page.goto("/");
  await page.getByRole("button", { name: "Tôi đã có tài khoản", exact: true }).click();
  await page
    .getByRole("button", { name: "Tạo tài khoản mới", exact: true })
    .click();
  await page.locator("#username").fill(name);
  await page.locator("#password").fill("abcdef");
  await page.locator("#display-name").fill(name);
  await page.locator("#agree").check();
  await page.locator("#auth-submit").click();
  await expect(page.locator("#app")).toBeVisible();
}
test("mobile social journey: register, profile, matching, mutual chat, post, notification, block and logout", async ({
  browser,
}) => {
  const aContext = await browser.newContext({
      viewport: { width: 412, height: 915 },
    }),
    bContext = await browser.newContext({
      viewport: { width: 412, height: 915 },
    });
  const a = await aContext.newPage(),
    b = await bContext.newPage();
  const errors = [];
  for (const p of [a, b]) p.on("pageerror", (e) => errors.push(e.message));
  await signUp(a, "alice_browser");
  await signUp(b, "bruno_browser");
  await a.getByRole("button", { name: "Hồ sơ", exact: true }).click();
  await a.getByRole("button", {name:"Tài khoản của tôi",exact:true}).click();await a.getByRole("menuitem",{name:"Cài đặt tài khoản",exact:true}).click();await a.getByRole("button",{name:"Chỉnh sửa tài khoản",exact:true}).click();
  await a
    .getByRole("textbox",{name:"Giới thiệu",exact:true})
    .fill("Một người bạn thích cà phê.");
  await a.getByLabel("Sở thích, phân cách bằng dấu phẩy").fill("coffee, music");
  await a.getByRole("button", { name: "Xong", exact: true }).click();
  await expect(a.locator("#notice")).toHaveText("Đã lưu hồ sơ.");
  await b.getByRole("button", { name: "Hồ sơ", exact: true }).click();
  await b.getByRole("button", {name:"Tài khoản của tôi",exact:true}).click();await b.getByRole("menuitem",{name:"Cài đặt tài khoản",exact:true}).click();await b.getByRole("button",{name:"Chỉnh sửa tài khoản",exact:true}).click();
  await b.getByLabel("Sở thích, phân cách bằng dấu phẩy").fill("coffee");
  await b.getByRole("button", { name: "Xong", exact: true }).click();
  await expect(b.locator("#notice")).toHaveText("Đã lưu hồ sơ.");
  await a.getByRole("button", { name: "Khám phá", exact: true }).click();
  await expect(a.getByText("1 sở thích chung")).toHaveCount(1);
  const bruno = a.locator(".person-tile").filter({has:a.getByRole("heading",{name:"bruno_browser",exact:true})});
  await bruno.getByRole("button", { name: "Theo dõi", exact: true }).click();
  await expect(
    a.locator(".person-tile").filter({has:a.getByRole("heading",{name:"bruno_browser",exact:true})}).getByRole("button", { name: "Bỏ theo dõi", exact: true }),
  ).toBeVisible();
  await b.getByRole("button", { name: "Khám phá", exact: true }).click();
  const alice = b.locator(".person-tile").filter({has:b.getByRole("heading",{name:"alice_browser",exact:true})});
  await alice.getByRole("button", { name: "Theo dõi", exact: true }).click();
  await expect(
    b.locator(".person-tile").filter({has:b.getByRole("heading",{name:"alice_browser",exact:true})}).getByRole("button", { name: "Bỏ theo dõi", exact: true }),
  ).toBeVisible();
  await bruno.getByRole("button", { name: "Nhắn tin", exact: true }).click();
  await a
    .getByRole("textbox", { name: "Tin nhắn riêng" })
    .fill("Xin chào từ Kinnect");
  await a.getByRole("button", { name: "Gửi", exact: true }).click();
  await expect(
    a.locator(".dm-log").getByText("Xin chào từ Kinnect", { exact: true }),
  ).toBeVisible();
  await b.getByRole("button", { name: "Tin nhắn", exact: true }).click();
  await b.locator(".inbox-row").first().click();
  await expect(
    b.locator(".dm-log").getByText("Xin chào từ Kinnect", { exact: true }),
  ).toBeVisible();
  await a.getByRole("button", { name: "Bảng tin", exact: true }).click();
  await a
    .getByRole("textbox", { name: "Nội dung bài viết" })
    .fill("Ngày đầu tiên cùng cộng đồng Kinnect");
  await a.getByRole("button", { name: "Chia sẻ", exact: true }).click();
  await expect(
    a.getByText("Ngày đầu tiên cùng cộng đồng Kinnect", { exact: true }),
  ).toBeVisible();
  await b.getByRole("button", { name: "Bảng tin", exact: true }).click();
  await expect(
    b.getByText("Ngày đầu tiên cùng cộng đồng Kinnect", { exact: true }),
  ).toBeVisible();
  await b.locator('[data-tab="notifications"]').click();
  await expect(
    b.getByText("đã gửi tin nhắn cho bạn.", { exact: true }),
  ).toBeVisible();
  await b.getByRole("button",{name:"Đóng thông báo",exact:true}).click();
  await b.getByRole("button", { name: "Khám phá", exact: true }).click();
  b.once("dialog", (d) => d.accept());
  await alice.locator(".more summary").click();
  const menu=b.getByRole('dialog',{name:'Tùy chọn khác'});await expect(menu).toBeVisible();
  const menuBox=await menu.boundingBox();expect(menuBox.x).toBeGreaterThanOrEqual(0);expect(menuBox.x+menuBox.width).toBeLessThanOrEqual(412);
  expect(await menu.evaluate(el=>el.scrollWidth-el.clientWidth)).toBe(0);
  await b.screenshot({path:'C:/Users/ANH/Documents/Codex/2026-10-24/ki-m-tra-claude-ang-l/outputs/audit/390-profile-menu.png'});
  await b.getByRole("button", { name: "Chặn", exact: true }).click();
  await expect(
    b.locator(".person-tile").filter({has:b.getByRole("heading",{name:"alice_browser",exact:true})}),
  ).toHaveCount(0);
  await b.getByRole("button", { name: "Bảng tin", exact: true }).click();
  await expect(
    b.getByText("Ngày đầu tiên cùng cộng đồng Kinnect", { exact: true }),
  ).toHaveCount(0);
  await a.screenshot({
    path: "test-results/kinnect-mobile-feed.png",
    fullPage: true,
  });
  await a.getByRole("button",{name:"Video",exact:true}).click();await a.getByRole("button",{name:"Các buổi đang live",exact:true}).click();await expect(a.locator(".live-grid")).toBeVisible();
  await a.getByRole("button", { name: "Tài khoản của tôi", exact: true }).click();
  await a.getByRole("menuitem", { name: "Đăng xuất", exact: true }).click();
  await expect(a.locator("#auth")).toBeVisible();
  expect(errors).toEqual([]);
  await aContext.close();
  await bContext.close();
});

async function livePair(browser, prefix) {
  const hc = await browser.newContext({
      permissions: ["camera", "microphone"],
    }),
    vc = await browser.newContext();
  const host = await hc.newPage(),
    viewer = await vc.newPage();
  await signUp(host, prefix + "_host");
  await signUp(viewer, prefix + "_viewer");
  await host.getByRole("button",{name:"Quay video",exact:true}).click();await host.getByRole("button",{name:"Phát trực tiếp",exact:true}).click();await host.getByRole("textbox",{name:"Tiêu đề buổi live",exact:true}).fill("Local camera smoke test");await host.getByRole("button",{name:"Lên sóng",exact:true}).click();
  await expect(host.locator("#live")).toBeVisible();
  await viewer.getByRole("button",{name:"Video",exact:true}).click();await viewer.getByRole("button",{name:"Các buổi đang live",exact:true}).click();await viewer.locator(".live-card").first().click();
  await expect(viewer.locator("#live")).toBeVisible();
  return { hc, vc, host, viewer };
}
test("live browser capture, room chat and background cleanup (without received video assertion)", async ({
  browser,
}) => {
  const { hc, vc, host, viewer } = await livePair(browser, "controls");
  await expect
    .poll(() =>
      host
        .locator("#video")
        .evaluate((v) => v.readyState >= 2 && v.videoWidth > 0),
    )
    .toBe(true);
  await viewer.locator("#message").fill("Live chat hoạt động");
  await viewer.locator("#chat button").click();
  await expect(host.locator("#messages")).toContainText("Live chat hoạt động");
  await host.locator("#mic").click();
  await expect(host.locator("#mic")).toHaveText("Bật micro");
  await host.evaluate(() =>
    window.dispatchEvent(new Event("kinnect-background")),
  );
  await expect(host.locator("#live")).toBeHidden();
  await expect(viewer.locator("#live")).toBeHidden();
  await hc.close();
  await vc.close();
});
test("received video frames over local WebRTC", async ({ browser }) => {
  test.skip(
    process.env.KINNECT_MEDIA_E2E !== "1",
    "Opt-in: requires a network that permits WebRTC media or configured TURN; managed Chromium disables non-proxied UDP.",
  );
  const { hc, vc, viewer } = await livePair(browser, "frames");
  try {
    await expect
      .poll(
        () =>
          viewer
            .locator("#video")
            .evaluate((v) => v.readyState >= 2 && v.videoWidth > 0),
        { timeout: 15000 },
      )
      .toBe(true);
  } finally {
    await hc.close();
    await vc.close();
  }
});

test("uploaded MP4 is decoded and played through authenticated HTTP video endpoint", async ({
  page,
}) => {
  const { readFile } = await import("node:fs/promises");
  const bytes = await readFile(
    new URL("../test/fixtures/short.mp4", import.meta.url),
  );
  await signUp(page, "short_browser");
  const navigation = page.getByRole("navigation", { name: "Điều hướng chính", exact: true });
  await navigation.getByRole("button", { name: "Video", exact: true }).click();
  await page.getByRole("button", { name: "Đang theo dõi", exact: true }).click();
  await expect(page.getByRole("heading", { name: "Chưa có video từ người bạn theo dõi" })).toBeVisible();
  await expect(page.locator("body")).toHaveAttribute("data-reel", "empty");
  expect(await page.locator("body").evaluate(el => getComputedStyle(el).backgroundColor)).not.toBe("rgb(0, 0, 0)");
  await page.locator(".reel-live-shortcut").click();
  await expect(page.locator(".live-grid")).toBeVisible();
  await expect(page.locator("#social-panel")).toBeVisible();
  const response = await page.request.post("/api/shorts", {
    data: {
      caption: "Browser video smoke",
      data: "data:video/mp4;base64," + bytes.toString("base64"),
    },
  });
  expect(response.status()).toBe(201);
  await navigation.getByRole("button", { name: "Video", exact: true }).click();
  await page.getByRole("button", { name: "Đề xuất", exact: true }).click();
  await expect(page.locator("body")).toHaveAttribute("data-reel", "ready");
  await expect
    .poll(() =>
      page
        .locator(".reel-item video").first()
        .evaluate((v) => v.videoWidth === 160 && v.readyState >= 2),
    )
    .toBe(true);
  await page.locator(".reel-item video").first().evaluate(v => v.play());
  await expect
    .poll(() =>
      page.locator(".reel-item video").first().evaluate((v) => v.currentTime),
    )
    .toBeGreaterThan(0);
  await page.locator(".reel-item video").first().evaluate(v => { window.reviewVideo = v; });
  await page.locator(".reel-live-shortcut").click();
  expect(await page.evaluate(() => window.reviewVideo.paused)).toBe(true);
  await expect(page.locator(".live-grid")).toBeVisible();
});

test("nearby consent, optional Les identity and notification permission/bell work on mobile", async ({browser}) => {
  const ctx=await browser.newContext({viewport:{width:390,height:844}});
  await ctx.addInitScript(()=>{
    window.locationRequests=0;window.notificationRequests=0;
    Object.defineProperty(navigator,"geolocation",{value:{getCurrentPosition(resolve){window.locationRequests++;resolve({coords:{latitude:21.03,longitude:105.85}});}}});
    class FakeNotification { static permission="default";static async requestPermission(){window.notificationRequests++;this.permission="granted";return "granted";} }
    Object.defineProperty(window,"Notification",{value:FakeNotification});
  });
  const p=await ctx.newPage();await signUp(p,"community_browser");
  await expect(p.locator(".view-discover")).toBeVisible();
  expect(await p.evaluate(()=>[window.locationRequests,window.notificationRequests])).toEqual([0,0]);
  // Notification permission is configured in account settings.
  await p.getByRole("button",{name:"Tài khoản của tôi",exact:true}).click();
  await p.getByRole("menuitem",{name:"Cài đặt tài khoản",exact:true}).click();
  await p.locator(".settings-entry>summary").filter({hasText:"Thông báo và âm thanh"}).click();
  await p.getByRole("button",{name:"Bật thông báo trình duyệt",exact:true}).click();
  expect(await p.evaluate(()=>window.notificationRequests)).toBe(1);
  await p.keyboard.press("Escape");
  await p.getByRole("button",{name:"Khám phá",exact:true}).click();await p.getByRole("button",{name:"Gần đây",exact:true}).click();
  await expect(p.getByRole("heading",{name:"Thành viên quanh bạn",exact:true})).toBeVisible();
  expect(await p.evaluate(()=>window.locationRequests)).toBe(1);
  await expect(p.locator(".nearby-consent")).toBeHidden();
  await p.getByRole("button",{name:"Tài khoản của tôi",exact:true}).click();
  await p.getByRole("menuitem",{name:"Cài đặt tài khoản",exact:true}).click();
  await p.locator('.settings-entry>summary').filter({hasText:'Vị trí'}).click();await p.getByRole("button",{name:"Tắt vị trí",exact:true}).click();
  await p.getByRole("button",{name:"Hồ sơ",exact:true}).click();
  await p.getByRole('button',{name:'Tài khoản của tôi',exact:true}).click();await p.getByRole('menuitem',{name:'Cài đặt tài khoản',exact:true}).click();await p.getByRole('button',{name:'Chỉnh sửa tài khoản',exact:true}).click();
  await p.getByLabel("Xu hướng tính dục",{exact:true}).fill("Les / Đồng tính nữ");
  await p.getByLabel("Giới tính",{exact:true}).fill("Nữ");
  await p.getByLabel("Vai trò",{exact:true}).fill("Vers Bottom");
  await p.getByLabel("Hiển thị giới tính, xu hướng và vai trò trên hồ sơ",{exact:true}).check();
  await p.getByRole("button",{name:"Xong",exact:true}).click();
  await expect(p.getByRole("region",{name:"Thông tin cá nhân"}).getByRole("definition").filter({hasText:"Les / Đồng tính nữ"})).toBeVisible();
  const other=await browser.newContext();
  await other.request.post("/api/register",{data:{username:"notification_browser",password:"abcdef",name:"Bạn mới",agree18:true}});
  const own=(await (await ctx.request.get("/api/me")).json()).user;
  await other.request.post("/api/users/"+own.id+"/follow",{data:{}});
  await expect(p.locator("#unread")).toHaveText("1");
  await p.locator("#notification-bell").click();
  await expect(p.locator("#notification-center")).toBeVisible();
  await expect(p.locator("#notification-center").getByText("đã theo dõi bạn.",{exact:true})).toBeVisible();
  await p.locator("#notification-center").getByRole("button",{name:"Đánh dấu đã đọc",exact:true}).click();
  await expect(p.locator("#unread")).toBeEmpty();
  await other.close();await ctx.close();
});

for (const width of [390, 1440]) {
  test(`Studio closes during recording and pending camera switch at ${width}px`, async ({ browser }) => {
    const context = await browser.newContext({ viewport: { width, height: 900 }, permissions: ['camera', 'microphone'] });
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    try {
      await page.goto('/');
      await page.evaluate(async () => {
        const get = navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);
        window.cameraTracks = [];
        navigator.mediaDevices.getUserMedia = async options => {
          const stream = await get(options);
          window.cameraTracks.push(...stream.getTracks());
          return stream;
        };
        const { openStudio } = await import('/camera.js');
        window.openTestStudio = () => openStudio({ onDone: async () => {}, notify: message => { window.studioNotice = message; } });
        await window.openTestStudio();
      });
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
      await page.getByRole('button', { name: 'Bắt đầu quay', exact: true }).click();
      await expect(page.locator('.studio')).toHaveClass(/recording/);
      await page.getByRole('button', { name: 'Đóng', exact: true }).click();
      await expect.poll(() => page.evaluate(() => window.cameraTracks.every(t => t.readyState === 'ended'))).toBe(true);
      await page.evaluate(async () => {
        await window.openTestStudio();
        const get = navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);
        navigator.mediaDevices.getUserMedia = async options => {
          const stream = await get(options);
          await new Promise(resolve => { window.releaseCamera = resolve; });
          return stream;
        };
      });
      await page.getByRole('button', { name: 'Lật', exact: true }).click();
      await expect.poll(() => page.evaluate(() => typeof window.releaseCamera)).toBe('function');
      await page.getByRole('button', { name: 'Đóng', exact: true }).click();
      await page.evaluate(() => window.releaseCamera());
      await expect.poll(() => page.evaluate(() => window.cameraTracks.every(t => t.readyState === 'ended'))).toBe(true);
      await expect(page.locator('.studio')).toHaveCount(0);
      expect(errors).toEqual([]);
    } finally { await context.close(); }
  });
}
