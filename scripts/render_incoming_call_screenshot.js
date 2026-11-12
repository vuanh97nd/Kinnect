import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';

async function main() {
  const browser = await chromium.launch({
    headless: true,
    executablePath: 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe'
  });
  const context = await browser.newContext({
    viewport: { width: 412, height: 915 },
    deviceScaleFactor: 2.625
  });
  const page = await context.newPage();

  const html = `<!DOCTYPE html>
<html lang="vi">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=412, initial-scale=1.0">
  <title>Kinnect Incoming Call</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; user-select: none; }
    body {
      width: 412px;
      height: 915px;
      background: linear-gradient(180deg, #191c28 0%, #131520 50%, #0d0e14 100%);
      font-family: -apple-system, BlinkMacSystemFont, "Google Sans", "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: space-between;
      color: #f2f0f8;
      overflow: hidden;
      position: relative;
    }

    /* Android Status Bar */
    .status-bar {
      width: 100%;
      height: 38px;
      padding: 10px 24px 0 24px;
      display: flex;
      justify-content: space-between;
      align-items: center;
      font-size: 13px;
      font-weight: 600;
      color: #e8eaed;
      z-index: 10;
    }
    .status-icons {
      display: flex;
      align-items: center;
      gap: 6px;
    }

    /* Main Column */
    .caller-section {
      display: flex;
      flex-direction: column;
      align-items: center;
      margin-top: 24px;
      z-index: 5;
    }

    /* Material 3 Pixel Call Pill */
    .call-pill {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      padding: 6px 16px;
      background: rgba(168, 199, 250, 0.14);
      border: 1px solid rgba(168, 199, 250, 0.25);
      border-radius: 999px;
      font-size: 13px;
      font-weight: 500;
      color: #d3e3fd;
      letter-spacing: 0.01em;
    }

    .caller-name {
      font-size: 32px;
      font-weight: 700;
      letter-spacing: -0.01em;
      color: #f2f0f8;
      margin-top: 22px;
      margin-bottom: 4px;
      text-align: center;
    }

    .call-status {
      font-size: 14.5px;
      font-weight: 400;
      color: #9aa0a6;
      text-align: center;
    }

    /* Halo & Concentric Pulsing Rings */
    .halo-container {
      position: relative;
      width: 220px;
      height: 220px;
      display: flex;
      align-items: center;
      justify-content: center;
      margin-top: 40px;
    }

    .halo-ring {
      position: absolute;
      border-radius: 50%;
      pointer-events: none;
    }
    .ring-3 {
      width: 216px;
      height: 216px;
      background: rgba(124, 92, 255, 0.08);
      border: 1px solid rgba(168, 199, 250, 0.22);
    }
    .ring-2 {
      width: 172px;
      height: 172px;
      background: rgba(124, 92, 255, 0.12);
      border: 1px solid rgba(168, 199, 250, 0.32);
    }
    .ring-1 {
      width: 140px;
      height: 140px;
      background: rgba(124, 92, 255, 0.18);
      border: 1.5px solid rgba(168, 199, 250, 0.45);
    }

    .avatar-circle {
      position: relative;
      width: 116px;
      height: 116px;
      border-radius: 50%;
      background: linear-gradient(135deg, #8b5cf6 0%, #4f46e5 100%);
      border: 2.5px solid rgba(255, 255, 255, 0.40);
      box-shadow: 0 16px 36px rgba(124, 92, 255, 0.45);
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 46px;
      font-weight: 700;
      color: #ffffff;
      z-index: 2;
    }

    /* Actions Section */
    .actions-section {
      width: 100%;
      padding: 0 36px 64px 36px;
      display: flex;
      justify-content: space-around;
      align-items: center;
      z-index: 5;
    }

    .action-item {
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 12px;
    }

    .btn-wrapper {
      position: relative;
      width: 96px;
      height: 96px;
      display: flex;
      align-items: center;
      justify-content: center;
    }

    /* Pulsing Green Halo behind Answer */
    .answer-halo {
      position: absolute;
      width: 96px;
      height: 96px;
      border-radius: 50%;
      background: rgba(52, 168, 83, 0.18);
      border: 2px solid rgba(52, 168, 83, 0.45);
      box-shadow: 0 0 24px rgba(52, 168, 83, 0.35);
    }

    .call-btn {
      width: 76px;
      height: 76px;
      border-radius: 50%;
      display: flex;
      align-items: center;
      justify-content: center;
      cursor: pointer;
      position: relative;
      z-index: 2;
      transition: transform 0.15s ease;
    }

    .decline-btn {
      background: #ea4335;
      box-shadow: 0 10px 28px rgba(234, 67, 53, 0.50);
    }

    .answer-btn {
      background: #34a853;
      box-shadow: 0 10px 28px rgba(52, 168, 83, 0.55);
    }

    .call-btn svg {
      width: 36px;
      height: 36px;
      fill: #ffffff;
    }

    .btn-label {
      font-size: 14px;
      font-weight: 700;
      color: #f0f2f5;
      letter-spacing: 0.01em;
    }

    /* Android Home Indicator Bar */
    .home-bar {
      position: absolute;
      bottom: 12px;
      left: 50%;
      transform: translateX(-50%);
      width: 108px;
      height: 4px;
      background: rgba(255, 255, 255, 0.4);
      border-radius: 999px;
    }
  </style>
</head>
<body>
  <!-- Android Status Bar -->
  <div class="status-bar">
    <span>22:40</span>
    <div class="status-icons">
      <!-- 5G -->
      <svg width="18" height="14" viewBox="0 0 24 24" fill="#e8eaed"><path d="M12 4C7.31 4 3.07 5.9 0 8.98L12 21 24 8.98C20.93 5.9 16.69 4 12 4z"/></svg>
      <!-- Battery -->
      <svg width="18" height="14" viewBox="0 0 24 24" fill="#e8eaed"><path d="M17 5v14H7V5h10m1-2H6c-.55 0-1 .45-1 1v16c0 .55.45 1 1 1h12c.55 0 1-.45 1-1V4c0-.55-.45-1-1-1zm-3-2h-4c-.55 0-1 .45-1 1v1h6V2c0-.55-.45-1-1-1z"/></svg>
    </div>
  </div>

  <!-- Caller Section -->
  <div class="caller-section">
    <div class="call-pill">
      <svg width="14" height="14" viewBox="0 0 24 24" fill="#a8c7fa"><path d="M20.01 15.38c-1.23 0-2.42-.2-3.53-.56a.977.977 0 0 0-1.01.24l-2.2 2.2a15.045 15.045 0 0 1-6.59-6.59l2.2-2.21a.96.96 0 0 0 .25-1.01A11.36 11.36 0 0 1 8.5 3.92c0-.55-.45-1-1-1H4c-.55 0-1 .45-1 1 0 9.39 7.61 17 17 17 .55 0 1-.45 1-1v-3.49c0-.55-.45-1-1-1z"/></svg>
      <span>Kinnect · Cuộc gọi thoại đến</span>
    </div>

    <div class="caller-name">Bích Phương</div>
    <div class="call-status">Đang đổ chuông…</div>

    <!-- Pulsing Rings & Caller Avatar -->
    <div class="halo-container">
      <div class="halo-ring ring-3"></div>
      <div class="halo-ring ring-2"></div>
      <div class="halo-ring ring-1"></div>
      <div class="avatar-circle">P</div>
    </div>
  </div>

  <!-- Action Buttons (Decline / Accept with new solid icons) -->
  <div class="actions-section">
    <!-- Decline Button -->
    <div class="action-item">
      <div class="btn-wrapper">
        <div class="call-btn decline-btn">
          <!-- Solid white call end receiver (Material 3 baseline_call_end / ic_call_decline) -->
          <svg viewBox="0 0 24 24">
            <path d="M12 9c-1.6 0-3.15.25-4.6.72v3.1c0 .39-.23.74-.56.9-.98.49-1.87 1.12-2.66 1.85-.18.18-.43.28-.7.28-.28 0-.53-.11-.71-.29L.29 13.08a.99.99 0 0 1 0-1.41C3.41 8.52 7.46 6.5 12 6.5s8.59 2.02 11.71 5.17c.39.39.39 1.02 0 1.41l-2.48 2.48c-.18.18-.43.29-.71.29-.27 0-.52-.11-.7-.28-.79-.74-1.69-1.36-2.67-1.85-.33-.16-.56-.5-.56-.9v-3.1C15.15 9.25 13.6 9 12 9z"/>
          </svg>
        </div>
      </div>
      <span class="btn-label">Từ chối</span>
    </div>

    <!-- Answer Button with Glowing Ripple Halo -->
    <div class="action-item">
      <div class="btn-wrapper">
        <div class="answer-halo"></div>
        <div class="call-btn answer-btn">
          <!-- Solid white answer call receiver (Material 3 baseline_call / ic_call_accept) -->
          <svg viewBox="0 0 24 24">
            <path d="M20.01 15.38c-1.23 0-2.42-.2-3.53-.56a.977.977 0 0 0-1.01.24l-2.2 2.2a15.045 15.045 0 0 1-6.59-6.59l2.2-2.21a.96.96 0 0 0 .25-1.01A11.36 11.36 0 0 1 8.5 3.92c0-.55-.45-1-1-1H4c-.55 0-1 .45-1 1 0 9.39 7.61 17 17 17 .55 0 1-.45 1-1v-3.49c0-.55-.45-1-1-1z"/>
          </svg>
        </div>
      </div>
      <span class="btn-label">Trả lời</span>
    </div>
  </div>

  <!-- Android Navigation Bar Indicator -->
  <div class="home-bar"></div>
</body>
</html>`;

  await page.setContent(html);
  await page.waitForTimeout(400);

  const outDir = 'outputs';
  if (!fs.existsSync(outDir)) fs.mkdirSync(outDir, { recursive: true });

  const screenPath = path.join(outDir, 'incoming-call-screen.png');
  await page.screenshot({ path: screenPath });
  console.log('Saved screenshot to:', screenPath);

  // Also copy to artifact directory
  const artifactDir = 'C:\\Users\\ANH\\.gemini\\antigravity\\brain\\dab8d5cd-f092-4bd6-993e-a0c622455d85';
  if (fs.existsSync(artifactDir)) {
    const artPath = path.join(artifactDir, 'incoming-call-screen.png');
    fs.copyFileSync(screenPath, artPath);
    console.log('Copied screenshot to artifact directory:', artPath);
  }

  await browser.close();
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
