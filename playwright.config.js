import { defineConfig } from "@playwright/test";
const port = Number(process.env.E2E_PORT || 3210);
export default defineConfig({
  testDir: "./e2e",
  workers: 1,
  timeout: 30000,
  use: {
    baseURL: `http://127.0.0.1:${port}`,
    viewport: { width: 412, height: 915 },
    launchOptions: {
      ...(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE
        ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE }
        : {}),
      args: [
        "--no-sandbox",
        "--use-fake-device-for-media-stream",
        "--autoplay-policy=no-user-gesture-required",
      ],
    },
  },
  webServer: {
    command: "node scripts/e2e-server.js",
    url: `http://127.0.0.1:${port}/health`,
    reuseExistingServer: false,
  },
});
