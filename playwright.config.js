import { defineConfig } from "@playwright/test";
const port = Number(process.env.E2E_PORT || 3210);
export default defineConfig({
  testDir: "./e2e",
  workers: 1,
  // Dùng 45s cho mỗi test (nhiều spec có camera/WebRTC/socket cần dựng), và
  // mỗi assertion `expect`/`expect.poll` mặc định 10s để đỡ gãy do mạng chậm.
  timeout: 45000,
  expect: { timeout: 10000 },
  // Thử lại một lần cho test bập bênh (WebRTC, hẹn giờ UI) để không fail cả suite vì một lần nhịp lỗi.
  retries: 1,
  reporter: process.env.CI ? [["list"], ["github"]] : [["list"]],
  use: {
    baseURL: `http://127.0.0.1:${port}`,
    viewport: { width: 412, height: 915 },
    actionTimeout: 10000,
    navigationTimeout: 15000,
    // Giữ trace và screenshot của lần retry để chẩn đoán khi vẫn fail.
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
    launchOptions: {
      ...(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE
        ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE }
        : {}),
      args: [
        "--no-sandbox",
        "--use-fake-device-for-media-stream",
        "--use-fake-ui-for-media-stream",
        "--autoplay-policy=no-user-gesture-required",
      ],
    },
  },
  webServer: {
    command: "node scripts/e2e-server.js",
    url: `http://127.0.0.1:${port}/health`,
    reuseExistingServer: false,
    timeout: 30000,
  },
});
