import { test, expect } from "@playwright/test";
async function signUp(page, name) {
  await page.goto("/");
  await page.getByRole("button", { name: "Bỏ qua", exact: true }).click();
  await page
    .getByRole("button", { name: "Tạo tài khoản", exact: true })
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
  await a.getByRole("button", { name: "Sửa hồ sơ", exact: true }).click();
  await a
    .getByLabel("Giới thiệu", { exact: true })
    .fill("Một người bạn thích cà phê.");
  await a.getByLabel("Sở thích, phân cách bằng dấu phẩy").fill("coffee, music");
  await a.getByRole("button", { name: "Lưu hồ sơ", exact: true }).click();
  await expect(a.locator("#notice")).toHaveText("Đã lưu hồ sơ.");
  await b.getByRole("button", { name: "Hồ sơ", exact: true }).click();
  await b.getByRole("button", { name: "Sửa hồ sơ", exact: true }).click();
  await b.getByLabel("Sở thích, phân cách bằng dấu phẩy").fill("coffee");
  await b.getByRole("button", { name: "Lưu hồ sơ", exact: true }).click();
  await expect(b.locator("#notice")).toHaveText("Đã lưu hồ sơ.");
  await a.getByRole("button", { name: "Khám phá", exact: true }).click();
  await expect(a.getByText("1 sở thích chung")).toBeVisible();
  await a.getByRole("button", { name: "Theo dõi", exact: true }).click();
  await expect(
    a.getByRole("button", { name: "Bỏ theo dõi", exact: true }),
  ).toBeVisible();
  await b.getByRole("button", { name: "Khám phá", exact: true }).click();
  await b.getByRole("button", { name: "Theo dõi", exact: true }).click();
  await expect(
    b.getByRole("button", { name: "Bỏ theo dõi", exact: true }),
  ).toBeVisible();
  await a.getByRole("button", { name: "Nhắn tin", exact: true }).click();
  await a
    .getByRole("textbox", { name: "Tin nhắn riêng" })
    .fill("Xin chào từ Kinnect");
  await a.getByRole("button", { name: "Gửi", exact: true }).click();
  await expect(
    a.getByText("Xin chào từ Kinnect", { exact: true }),
  ).toBeVisible();
  await b.getByRole("button", { name: "Tin nhắn", exact: true }).click();
  await b.locator(".inbox-row").first().click();
  await expect(
    b.getByText("Xin chào từ Kinnect", { exact: true }),
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
  await b.getByRole("button", { name: "Khám phá", exact: true }).click();
  b.once("dialog", (d) => d.accept());
  await b.locator(".person-tile .more summary").first().click();
  await b.getByRole("button", { name: "Chặn", exact: true }).click();
  await expect(
    b.getByRole("button", { name: "Nhắn tin", exact: true }),
  ).toHaveCount(0);
  await b.getByRole("button", { name: "Bảng tin", exact: true }).click();
  await expect(
    b.getByText("Ngày đầu tiên cùng cộng đồng Kinnect", { exact: true }),
  ).toHaveCount(0);
  await a.screenshot({
    path: "test-results/kinnect-mobile-feed.png",
    fullPage: true,
  });
  await a.getByRole("button", { name: "Live", exact: true }).click();
  await expect(
    a.getByRole("button", { name: "Bắt đầu livestream", exact: true }),
  ).toBeVisible();
  await a.getByRole("button", { name: "Tài khoản", exact: true }).click();
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
  await host.getByRole("button", { name: "Live", exact: true }).click();
  await host.locator("#title").fill("Local camera smoke test");
  await host
    .getByRole("button", { name: "Bắt đầu livestream", exact: true })
    .click();
  await expect(host.locator("#live")).toBeVisible();
  await viewer.getByRole("button", { name: "Live", exact: true }).click();
  await viewer.getByRole("button", { name: "Vào xem", exact: true }).click();
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
  await expect(page.getByRole("heading", { name: "Chưa có video nào" })).toBeVisible();
  await expect(page.locator("body")).toHaveAttribute("data-reel", "empty");
  expect(await page.locator("body").evaluate(el => getComputedStyle(el).backgroundColor)).not.toBe("rgb(0, 0, 0)");
  await navigation.getByRole("button", { name: "Live", exact: true }).click();
  await expect(page.locator("#live-panel")).toBeVisible();
  await expect(page.locator("#social-panel")).toBeHidden();
  const response = await page.request.post("/api/shorts", {
    data: {
      caption: "Browser video smoke",
      data: "data:video/mp4;base64," + bytes.toString("base64"),
    },
  });
  expect(response.status()).toBe(201);
  await navigation.getByRole("button", { name: "Video", exact: true }).click();
  await expect(page.locator("body")).toHaveAttribute("data-reel", "ready");
  await expect
    .poll(() =>
      page
        .locator(".reel-item video")
        .evaluate((v) => v.videoWidth === 160 && v.readyState >= 2),
    )
    .toBe(true);
  await page.locator(".reel-item video").evaluate(v => v.play());
  await expect
    .poll(() =>
      page.locator(".reel-item video").evaluate((v) => v.currentTime),
    )
    .toBeGreaterThan(0);
  await page.locator(".reel-item video").evaluate(v => { window.reviewVideo = v; });
  await navigation.getByRole("button", { name: "Live", exact: true }).click();
  expect(await page.evaluate(() => window.reviewVideo.paused)).toBe(true);
  await expect(page.locator("#live-panel")).toBeVisible();
});
