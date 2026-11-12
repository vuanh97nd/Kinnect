import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';

const ARTIFACT_DIR = 'C:\\Users\\ANH\\.gemini\\antigravity\\brain\\dab8d5cd-f092-4bd6-993e-a0c622455d85';
const OUT_DIR = 'outputs';

if (!fs.existsSync(OUT_DIR)) {
  fs.mkdirSync(OUT_DIR, { recursive: true });
}

// iPhone 16 Pro Dimensions
const IPHONE_WIDTH = 393;
const IPHONE_HEIGHT = 852;

// SVG Icons
const ICONS = {
  dynamicIsland: `<div class="dynamic-island"><div class="di-camera"></div><div class="di-sensor"></div></div>`,
  statusBar: (time = "9:41") => `
    <div class="ios-status-bar">
      <div class="status-time">${time}</div>
      <div class="dynamic-island-placeholder"></div>
      <div class="status-icons">
        <svg width="17" height="12" viewBox="0 0 17 12" fill="currentColor">
          <rect x="0" y="8" width="3" height="4" rx="1"/>
          <rect x="4.5" y="5.5" width="3" height="6.5" rx="1"/>
          <rect x="9" y="3" width="3" height="9" rx="1"/>
          <rect x="13.5" y="0" width="3" height="12" rx="1"/>
        </svg>
        <svg width="16" height="12" viewBox="0 0 16 12" fill="currentColor">
          <path d="M8 2.4c2.8 0 5.3 1.1 7.2 3L16 4.6C13.8 2.4 11.1 1.2 8 1.2S2.2 2.4 0 4.6l.8.8C2.7 3.5 5.2 2.4 8 2.4zm0 3.6c1.8 0 3.5.7 4.8 2l.8-.8C12.1 5.7 10.1 4.8 8 4.8s-4.1.9-5.6 2.4l.8.8C4.5 6.7 6.2 6 8 6zm0 3.6c.9 0 1.7.3 2.4 1l.8-.8C10.3 8.9 9.2 8.4 8 8.4s-2.3.5-3.2 1.4l.8.8c.7-.7 1.5-1 2.4-1zM8 12a1.2 1.2 0 100-2.4 1.2 1.2 0 000 2.4z"/>
        </svg>
        <svg width="25" height="12" viewBox="0 0 25 12" fill="currentColor">
          <rect x="0.5" y="0.5" width="21" height="11" rx="3.5" stroke="currentColor" fill="none"/>
          <rect x="2" y="2" width="16" height="8" rx="2" fill="currentColor"/>
          <path d="M23 4v4c.6-.4 1-1.1 1-2s-.4-1.6-1-2z"/>
        </svg>
      </div>
    </div>
  `,
  homeIndicator: `<div class="home-indicator-bar"><div class="home-indicator"></div></div>`,
  chevronRight: `<svg width="8" height="14" viewBox="0 0 8 14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M1 1l6 6-6 6"/></svg>`,
  chevronDown: `<svg width="14" height="8" viewBox="0 0 14 8" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M1 1l6 6 6-6"/></svg>`,
  cameraRotate: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M23 4v6h-6"/><path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"/></svg>`,
  camera: `<svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><path d="M4 4h3l2-2h6l2 2h3a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2zm8 3a5 5 0 1 0 0 10 5 5 0 0 0 0-10zm0 2a3 3 0 1 1 0 6 3 3 0 0 1 0-6z"/></svg>`,
  mic: `<svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><path d="M12 14a3 3 0 0 0 3-3V5a3 3 0 0 0-6 0v6a3 3 0 0 0 3 3zm5-3a5 5 0 0 1-10 0H5a7 7 0 0 0 6 6.92V21h2v-3.08A7 7 0 0 0 19 11h-2z"/></svg>`,
  speaker: `<svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><path d="M3 9v6h4l5 5V4L7 9H3zm13.5 3c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02zM14 3.23v2.06c2.89.86 5 3.54 5 6.71s-2.11 5.85-5 6.71v2.06c4.01-.91 7-4.49 7-8.77s-2.99-7.86-7-8.77z"/></svg>`,
  endCall: `<svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor"><path d="M12 9c-1.6 0-3.15.25-4.6.72v3.1c0 .39-.23.74-.56.9-.98.49-1.87 1.12-2.66 1.85-.18.18-.43.28-.7.28-.28 0-.53-.11-.71-.29L.29 13.08a.996.996 0 0 1 0-1.41C2.52 9.4 6.99 8 12 8s9.48 1.4 11.71 3.67c.39.39.39 1.02 0 1.41l-2.48 2.48c-.18.18-.43.29-.71.29-.27 0-.52-.1-.7-.28-.79-.74-1.69-1.36-2.67-1.85-.33-.16-.56-.5-.56-.9v-3.1C15.15 9.25 13.6 9 12 9z"/></svg>`,
  // Squircle SF Symbols
  bag: `<svg width="17" height="17" viewBox="0 0 24 24" fill="currentColor"><path d="M19 6h-2c0-2.76-2.24-5-5-5S7 3.24 7 6H5c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V8c0-1.1-.9-2-2-2zm-7-3c1.66 0 3 1.34 3 3H9c0-1.66 1.34-3 3-3zm7 17H5V8h14v12zm-7-8c-1.66 0-3-1.34-3-3H7c0 2.76 2.24 5 5 5s5-2.24 5-5h-2c0 1.66-1.34 3-3 3z"/></svg>`,
  card: `<svg width="17" height="17" viewBox="0 0 24 24" fill="currentColor"><path d="M20 4H4c-1.11 0-1.99.89-1.99 2L2 18c0 1.11.89 2 2 2h16c1.11 0 2-.89 2-2V6c0-1.11-.89-2-2-2zm0 14H4v-6h16v6zm0-10H4V6h16v2z"/></svg>`,
  people: `<svg width="17" height="17" viewBox="0 0 24 24" fill="currentColor"><path d="M16 11c1.66 0 2.99-1.34 2.99-3S17.66 5 16 5c-1.66 0-3 1.34-3 3s1.34 3 3 3zm-8 0c1.66 0 2.99-1.34 2.99-3S9.66 5 8 5C6.34 5 5 6.34 5 8s1.34 3 3 3zm0 2c-2.33 0-7 1.17-7 3.5V19h14v-2.5c0-2.33-4.67-3.5-7-3.5zm8 0c-.29 0-.62.02-.97.05 1.16.84 1.97 1.97 1.97 3.45V19h6v-2.5c0-2.33-4.67-3.5-7-3.5z"/></svg>`,
  bell: `<svg width="17" height="17" viewBox="0 0 24 24" fill="currentColor"><path d="M12 22c1.1 0 2-.9 2-2h-4c0 1.1.9 2 2 2zm6-6v-5c0-3.07-1.63-5.64-4.5-6.32V4c0-.83-.67-1.5-1.5-1.5s-1.5.67-1.5 1.5v.68C7.64 5.36 6 7.92 6 11v5l-2 2v1h16v-1l-2-2zm-2 1H8v-6c0-2.48 1.51-4.5 4-4.5s4 2.02 4 4.5v6z"/></svg>`,
  appearance: `<svg width="17" height="17" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18V4c4.41 0 8 3.59 8 8s-3.59 8-8 8z"/></svg>`,
  privacy: `<svg width="17" height="17" viewBox="0 0 24 24" fill="currentColor"><path d="M18 10.5V6a6 6 0 0 0-12 0v4.5C4.9 11.13 4 12.46 4 14v6a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-6c0-1.54-.9-2.87-2-3.5zM8 6a4 4 0 0 1 8 0v4H8V6zm10 14H6v-6c0-.55.45-1 1-1h10c.55 0 1 .45 1 1v6z"/></svg>`,
  shield: `<svg width="17" height="17" viewBox="0 0 24 24" fill="currentColor"><path d="M12 1L3 5v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V5l-9-4zm0 10.99h7c-.53 4.12-3.28 7.79-7 8.94V12H5V6.3l7-3.11v8.8z"/></svg>`,
  key: `<svg width="17" height="17" viewBox="0 0 24 24" fill="currentColor"><path d="M21 10h-8.35A5.99 5.99 0 0 0 7 6c-3.31 0-6 2.69-6 6s2.69 6 6 6a5.99 5.99 0 0 0 5.65-4H17v4h4v-4h2v-4h-2zm-14 4a2 2 0 1 1 0-4 2 2 0 0 1 0 4z"/></svg>`,
  help: `<svg width="17" height="17" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 16h-2v-2h2v2zm1.07-7.75l-.9.92C12.45 11.9 12 12.5 12 14h-2v-.5c0-1.1.45-2.1 1.17-2.83l1.24-1.26c.37-.36.59-.86.59-1.41 0-1.1-.9-2-2-2s-2 .9-2 2H7c0-2.76 2.24-5 5-5s5 2.24 5 5c0 .88-.36 1.68-.93 2.25z"/></svg>`,
  info: `<svg width="17" height="17" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-6h2v6zm0-8h-2V7h2v2z"/></svg>`,
  logout: `<svg width="17" height="17" viewBox="0 0 24 24" fill="currentColor"><path d="M17 7l-1.41 1.41L18.17 11H8v2h10.17l-2.58 2.58L17 17l5-5zM4 5h8V3H4c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h8v-2H4V5z"/></svg>`
};

const COMMON_CSS = `
  * { box-sizing: border-box; margin: 0; padding: 0; user-select: none; -webkit-tap-highlight-color: transparent; }
  body {
    width: ${IPHONE_WIDTH}px;
    height: ${IPHONE_HEIGHT}px;
    background: #000;
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display", "Helvetica Neue", sans-serif;
    color: #fff;
    overflow: hidden;
    position: relative;
    display: flex;
    flex-direction: column;
  }
  .ios-status-bar {
    width: 100%;
    height: 54px;
    padding: 14px 28px 0 32px;
    display: flex;
    justify-content: space-between;
    align-items: center;
    font-size: 15px;
    font-weight: 600;
    letter-spacing: -0.3px;
    z-index: 100;
    position: absolute;
    top: 0;
    left: 0;
    color: #fff;
  }
  .dynamic-island-placeholder {
    width: 124px;
    height: 35px;
    background: #000;
    border-radius: 20px;
    position: absolute;
    left: 50%;
    transform: translateX(-50%);
    top: 11px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0 12px;
    box-shadow: 0 0 1px 1px rgba(255,255,255,0.06);
  }
  .dynamic-island-placeholder::after {
    content: '';
    width: 11px;
    height: 11px;
    background: #101015;
    border-radius: 50%;
    border: 1px solid #1c1c24;
    position: absolute;
    right: 14px;
  }
  .status-icons {
    display: flex;
    align-items: center;
    gap: 7px;
  }
  .home-indicator-bar {
    width: 100%;
    height: 34px;
    position: absolute;
    bottom: 0;
    left: 0;
    display: flex;
    justify-content: center;
    align-items: center;
    z-index: 100;
    pointer-events: none;
  }
  .home-indicator {
    width: 138px;
    height: 5px;
    background: #fff;
    border-radius: 3px;
    opacity: 0.85;
  }
`;

async function renderAccountScreen(page) {
  const html = `<!DOCTYPE html>
  <html>
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=${IPHONE_WIDTH}, initial-scale=1.0">
    <title>Kinnect Account</title>
    <style>
      ${COMMON_CSS}
      .app-viewport {
        width: 100%;
        height: 100%;
        background: #0d0a1c;
        display: flex;
        flex-direction: column;
        padding-top: 54px;
        padding-bottom: 34px;
        overflow-y: hidden;
      }
      .nav-bar {
        height: 48px;
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 0 16px;
        position: relative;
      }
      .nav-title {
        font-size: 17px;
        font-weight: 600;
        color: #fff;
      }
      .scroll-content {
        flex: 1;
        padding: 6px 16px 20px 16px;
        display: flex;
        flex-direction: column;
        gap: 14px;
      }
      /* Profile Card */
      .profile-card {
        background: #1a1430;
        border: 1px solid rgba(255, 255, 255, 0.08);
        border-radius: 18px;
        padding: 14px 16px;
        display: flex;
        align-items: center;
        gap: 14px;
      }
      .avatar-box {
        width: 56px;
        height: 56px;
        border-radius: 50%;
        background: linear-gradient(135deg, #A855F7, #6366F1);
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 22px;
        font-weight: 700;
        color: #fff;
        box-shadow: 0 4px 12px rgba(168, 85, 247, 0.35);
      }
      .profile-meta {
        flex: 1;
      }
      .profile-name {
        font-size: 17px;
        font-weight: 700;
        color: #fff;
        margin-bottom: 2px;
      }
      .profile-handle {
        font-size: 13px;
        color: rgba(255, 255, 255, 0.55);
      }
      /* Grouped Card */
      .settings-group {
        background: #1a1430;
        border: 0.8px solid rgba(255, 255, 255, 0.08);
        border-radius: 14px;
        overflow: hidden;
        display: flex;
        flex-direction: column;
      }
      .settings-row {
        display: flex;
        align-items: center;
        padding: 10px 16px;
        gap: 14px;
        cursor: pointer;
      }
      .squircle-badge {
        width: 32px;
        height: 32px;
        border-radius: 8px;
        display: flex;
        align-items: center;
        justify-content: center;
        color: #fff;
        box-shadow: 0 2px 6px rgba(0, 0, 0, 0.25);
        flex-shrink: 0;
      }
      .row-title {
        flex: 1;
        font-size: 16px;
        font-weight: 400;
        color: #fff;
        letter-spacing: -0.2px;
      }
      .row-title.danger {
        color: #F43F5E;
        font-weight: 500;
      }
      .row-chevron {
        color: rgba(255, 255, 255, 0.28);
      }
      .divider-line {
        height: 0.8px;
        background: rgba(255, 255, 255, 0.08);
        margin-left: 60px;
      }
      .footer-label {
        text-align: center;
        font-size: 12px;
        color: rgba(255, 255, 255, 0.4);
        padding-top: 4px;
      }
    </style>
  </head>
  <body>
    ${ICONS.statusBar("9:41")}
    <div class="app-viewport">
      <div class="nav-bar">
        <div class="nav-title">Tài khoản</div>
      </div>
      <div class="scroll-content">
        <!-- Profile Card -->
        <div class="profile-card">
          <div class="avatar-box">VA</div>
          <div class="profile-meta">
            <div class="profile-name">Vũ Anh</div>
            <div class="profile-handle">@vuanh97nd · Nhà sáng tạo</div>
          </div>
          <div class="row-chevron">${ICONS.chevronRight}</div>
        </div>

        <!-- Group 1: Store & Wallet -->
        <div class="settings-group">
          <div class="settings-row">
            <div class="squircle-badge" style="background: linear-gradient(180deg, #8E2DE2 0%, #4A00E0 100%);">
              ${ICONS.bag}
            </div>
            <div class="row-title">Cửa hàng Kinnect</div>
            <div class="row-chevron">${ICONS.chevronRight}</div>
          </div>
          <div class="divider-line"></div>
          <div class="settings-row">
            <div class="squircle-badge" style="background: linear-gradient(180deg, #F59E0B 0%, #D97706 100%);">
              ${ICONS.card}
            </div>
            <div class="row-title">Ví Kinnect</div>
            <div class="row-chevron">${ICONS.chevronRight}</div>
          </div>
        </div>

        <!-- Group 2: Social & Appearance -->
        <div class="settings-group">
          <div class="settings-row">
            <div class="squircle-badge" style="background: linear-gradient(180deg, #3B82F6 0%, #1D4ED8 100%);">
              ${ICONS.people}
            </div>
            <div class="row-title">Bạn bè</div>
            <div class="row-chevron">${ICONS.chevronRight}</div>
          </div>
          <div class="divider-line"></div>
          <div class="settings-row">
            <div class="squircle-badge" style="background: linear-gradient(180deg, #EF4444 0%, #DC2626 100%);">
              ${ICONS.bell}
            </div>
            <div class="row-title">Cài đặt thông báo</div>
            <div class="row-chevron">${ICONS.chevronRight}</div>
          </div>
          <div class="divider-line"></div>
          <div class="settings-row">
            <div class="squircle-badge" style="background: linear-gradient(180deg, #6366F1 0%, #4F46E5 100%);">
              ${ICONS.appearance}
            </div>
            <div class="row-title">Giao diện</div>
            <div class="row-chevron">${ICONS.chevronRight}</div>
          </div>
        </div>

        <!-- Group 3: Privacy & Security -->
        <div class="settings-group">
          <div class="settings-row">
            <div class="squircle-badge" style="background: linear-gradient(180deg, #64748B 0%, #475569 100%);">
              ${ICONS.privacy}
            </div>
            <div class="row-title">Cài đặt và quyền riêng tư</div>
            <div class="row-chevron">${ICONS.chevronRight}</div>
          </div>
          <div class="divider-line"></div>
          <div class="settings-row">
            <div class="squircle-badge" style="background: linear-gradient(180deg, #0EA5E9 0%, #0284C7 100%);">
              ${ICONS.shield}
            </div>
            <div class="row-title">Bảo mật và đăng nhập</div>
            <div class="row-chevron">${ICONS.chevronRight}</div>
          </div>
          <div class="divider-line"></div>
          <div class="settings-row">
            <div class="squircle-badge" style="background: linear-gradient(180deg, #10B981 0%, #059669 100%);">
              ${ICONS.key}
            </div>
            <div class="row-title">Đổi mật khẩu</div>
            <div class="row-chevron">${ICONS.chevronRight}</div>
          </div>
        </div>

        <!-- Group 4: Support & Info -->
        <div class="settings-group">
          <div class="settings-row">
            <div class="squircle-badge" style="background: linear-gradient(180deg, #0D9488 0%, #0F766E 100%);">
              ${ICONS.help}
            </div>
            <div class="row-title">Trợ giúp và hỗ trợ</div>
            <div class="row-chevron">${ICONS.chevronRight}</div>
          </div>
          <div class="divider-line"></div>
          <div class="settings-row">
            <div class="squircle-badge" style="background: linear-gradient(180deg, #8B5CF6 0%, #7C3AED 100%);">
              ${ICONS.info}
            </div>
            <div class="row-title">Giới thiệu Kinnect</div>
            <div class="row-chevron">${ICONS.chevronRight}</div>
          </div>
        </div>

        <!-- Group 5: Logout -->
        <div class="settings-group">
          <div class="settings-row">
            <div class="squircle-badge" style="background: linear-gradient(180deg, #F43F5E 0%, #E11D48 100%);">
              ${ICONS.logout}
            </div>
            <div class="row-title danger">Đăng xuất</div>
            <div class="row-chevron">${ICONS.chevronRight}</div>
          </div>
        </div>

        <div class="footer-label">Kinnect · Kết nối đúng gu · Sống đúng mình</div>
      </div>
    </div>
    ${ICONS.homeIndicator}
  </body>
  </html>`;

  await page.setContent(html);
  await page.waitForTimeout(300);
  const outPath = path.join(OUT_DIR, 'ios-simulator-account.png');
  await page.screenshot({ path: outPath });
  const artPath = path.join(ARTIFACT_DIR, 'ios-simulator-account.png');
  fs.copyFileSync(outPath, artPath);
  console.log('Saved account screenshot to:', outPath);
}

async function renderCallScreen(page) {
  const html = `<!DOCTYPE html>
  <html>
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=${IPHONE_WIDTH}, initial-scale=1.0">
    <title>Kinnect Call</title>
    <style>
      ${COMMON_CSS}
      .call-container {
        width: 100%;
        height: 100%;
        position: relative;
        background: #000;
        overflow: hidden;
      }
      /* Fullscreen Remote Video */
      .remote-video {
        width: 100%;
        height: 100%;
        object-fit: cover;
        position: absolute;
        top: 0;
        left: 0;
      }
      .remote-bg-gradient {
        position: absolute;
        inset: 0;
        background: linear-gradient(180deg, rgba(0,0,0,0.55) 0%, rgba(0,0,0,0.1) 25%, rgba(0,0,0,0.2) 70%, rgba(0,0,0,0.7) 100%);
      }
      /* Top Floating Bar */
      .top-floating-bar {
        position: absolute;
        top: 60px;
        left: 16px;
        right: 16px;
        display: flex;
        align-items: center;
        justify-content: space-between;
        z-index: 50;
      }
      .circle-blur-btn {
        width: 44px;
        height: 44px;
        border-radius: 50%;
        background: rgba(255, 255, 255, 0.18);
        backdrop-filter: blur(20px);
        -webkit-backdrop-filter: blur(20px);
        display: flex;
        align-items: center;
        justify-content: center;
        color: #fff;
        border: 1px solid rgba(255, 255, 255, 0.25);
      }
      .caller-info-center {
        display: flex;
        flex-direction: column;
        align-items: center;
        text-shadow: 0 2px 8px rgba(0, 0, 0, 0.6);
      }
      .caller-name {
        font-size: 19px;
        font-weight: 700;
        color: #fff;
        letter-spacing: -0.3px;
      }
      .call-duration {
        font-size: 13px;
        font-weight: 500;
        color: rgba(255, 255, 255, 0.85);
        background: rgba(0, 0, 0, 0.35);
        padding: 2px 8px;
        border-radius: 10px;
        margin-top: 3px;
      }
      /* Floating Picture-in-Picture */
      .floating-pip {
        position: absolute;
        top: 120px;
        right: 16px;
        width: 104px;
        height: 148px;
        border-radius: 16px;
        overflow: hidden;
        border: 1.5px solid rgba(255, 255, 255, 0.3);
        box-shadow: 0 10px 25px rgba(0, 0, 0, 0.6);
        z-index: 60;
        background: #1e1e24;
      }
      .pip-video {
        width: 100%;
        height: 100%;
        object-fit: cover;
      }
      .pip-badge {
        position: absolute;
        bottom: 6px;
        left: 6px;
        background: rgba(0, 0, 0, 0.6);
        padding: 2px 6px;
        border-radius: 6px;
        font-size: 10px;
        color: #fff;
        font-weight: 600;
      }
      /* Bottom Floating Capsule */
      .bottom-capsule-bar {
        position: absolute;
        bottom: 50px;
        left: 24px;
        right: 24px;
        height: 72px;
        background: rgba(30, 26, 46, 0.8);
        backdrop-filter: blur(28px);
        -webkit-backdrop-filter: blur(28px);
        border-radius: 36px;
        border: 1px solid rgba(255, 255, 255, 0.16);
        box-shadow: 0 16px 36px rgba(0, 0, 0, 0.6);
        display: flex;
        align-items: center;
        justify-content: space-evenly;
        padding: 0 12px;
        z-index: 50;
      }
      .capsule-btn {
        width: 48px;
        height: 48px;
        border-radius: 50%;
        background: rgba(255, 255, 255, 0.14);
        display: flex;
        align-items: center;
        justify-content: center;
        color: #fff;
        transition: transform 0.1s;
      }
      .capsule-btn.danger {
        background: linear-gradient(135deg, #EF4444 0%, #DC2626 100%);
        box-shadow: 0 4px 14px rgba(239, 68, 68, 0.45);
      }
    </style>
  </head>
  <body>
    ${ICONS.statusBar("9:41")}
    <div class="call-container">
      <!-- Remote simulated video feed -->
      <img class="remote-video" src="https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=800&q=80" alt="Remote Video" />
      <div class="remote-bg-gradient"></div>

      <!-- Top Floating Bar -->
      <div class="top-floating-bar">
        <div class="circle-blur-btn">${ICONS.chevronDown}</div>
        <div class="caller-info-center">
          <div class="caller-name">Hải Yến</div>
          <div class="call-duration">04:18 · HD Video</div>
        </div>
        <div class="circle-blur-btn">${ICONS.cameraRotate}</div>
      </div>

      <!-- Floating PiP Local Video -->
      <div class="floating-pip">
        <img class="pip-video" src="https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=400&q=80" alt="Local PiP" />
        <div class="pip-badge">Bạn</div>
      </div>

      <!-- Bottom Floating Controls Capsule -->
      <div class="bottom-capsule-bar">
        <div class="capsule-btn">${ICONS.camera}</div>
        <div class="capsule-btn">${ICONS.mic}</div>
        <div class="capsule-btn">${ICONS.speaker}</div>
        <div class="capsule-btn danger">${ICONS.endCall}</div>
      </div>
    </div>
    ${ICONS.homeIndicator}
  </body>
  </html>`;

  await page.setContent(html);
  await page.waitForTimeout(400);
  const outPath = path.join(OUT_DIR, 'ios-simulator-call.png');
  await page.screenshot({ path: outPath });
  const artPath = path.join(ARTIFACT_DIR, 'ios-simulator-call.png');
  fs.copyFileSync(outPath, artPath);
  console.log('Saved call screenshot to:', outPath);
}

async function renderFriendsScreen(page) {
  const html = `<!DOCTYPE html>
  <html>
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=${IPHONE_WIDTH}, initial-scale=1.0">
    <title>Kinnect Friends</title>
    <style>
      ${COMMON_CSS}
      .app-viewport {
        width: 100%;
        height: 100%;
        background: #0d0a1c;
        display: flex;
        flex-direction: column;
        padding-top: 54px;
        padding-bottom: 34px;
        overflow-y: hidden;
      }
      .nav-bar {
        height: 44px;
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 0 16px;
      }
      .nav-title {
        font-size: 17px;
        font-weight: 600;
        color: #fff;
      }
      /* Segmented Control */
      .segmented-picker {
        margin: 6px 16px 10px 16px;
        background: rgba(255, 255, 255, 0.08);
        border-radius: 9px;
        padding: 3px;
        display: flex;
        height: 34px;
      }
      .seg-item {
        flex: 1;
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 13px;
        font-weight: 500;
        color: rgba(255, 255, 255, 0.65);
        border-radius: 7px;
      }
      .seg-item.active {
        background: #2b2247;
        color: #fff;
        font-weight: 600;
        box-shadow: 0 2px 6px rgba(0, 0, 0, 0.3);
      }
      /* Search Input */
      .search-box {
        margin: 0 16px 14px 16px;
        height: 38px;
        background: #1a1430;
        border-radius: 11px;
        border: 1px solid rgba(255, 255, 255, 0.08);
        display: flex;
        align-items: center;
        padding: 0 12px;
        gap: 8px;
        font-size: 14px;
        color: rgba(255, 255, 255, 0.5);
      }
      .search-box svg {
        color: rgba(255, 255, 255, 0.4);
      }
      /* Scroll Content */
      .friends-list {
        flex: 1;
        padding: 0 16px 16px 16px;
        display: flex;
        flex-direction: column;
        gap: 14px;
      }
      .section-header {
        display: flex;
        align-items: center;
        gap: 6px;
        font-size: 13px;
        font-weight: 600;
        text-transform: uppercase;
        letter-spacing: 0.5px;
        padding: 0 4px;
      }
      .section-header.online {
        color: #2E9E66;
      }
      .section-header.offline {
        color: rgba(255, 255, 255, 0.45);
      }
      .header-badge {
        font-size: 11px;
        padding: 1px 7px;
        border-radius: 10px;
        background: rgba(46, 158, 102, 0.2);
        color: #2E9E66;
      }
      .header-badge.gray {
        background: rgba(255, 255, 255, 0.1);
        color: rgba(255, 255, 255, 0.6);
      }
      /* Inset Grouped Friend Card */
      .friend-group {
        background: #1a1430;
        border-radius: 14px;
        border: 0.8px solid rgba(255, 255, 255, 0.08);
        overflow: hidden;
      }
      .friend-row {
        display: flex;
        align-items: center;
        padding: 10px 14px;
        gap: 12px;
      }
      .avatar-wrapper {
        position: relative;
        width: 44px;
        height: 44px;
        flex-shrink: 0;
      }
      .user-avatar {
        width: 44px;
        height: 44px;
        border-radius: 50%;
        object-fit: cover;
      }
      .online-dot {
        position: absolute;
        bottom: 0;
        right: 0;
        width: 12px;
        height: 12px;
        background: #2E9E66;
        border: 2px solid #1a1430;
        border-radius: 50%;
      }
      .user-info {
        flex: 1;
      }
      .user-name {
        font-size: 15px;
        font-weight: 600;
        color: #fff;
      }
      .user-handle {
        font-size: 12px;
        color: rgba(255, 255, 255, 0.5);
      }
      .action-btns {
        display: flex;
        align-items: center;
        gap: 8px;
      }
      .msg-btn {
        width: 32px;
        height: 32px;
        border-radius: 50%;
        background: rgba(168, 85, 247, 0.15);
        color: #A855F7;
        display: flex;
        align-items: center;
        justify-content: center;
      }
      .divider-inset {
        height: 0.8px;
        background: rgba(255, 255, 255, 0.08);
        margin-left: 68px;
      }
    </style>
  </head>
  <body>
    ${ICONS.statusBar("9:41")}
    <div class="app-viewport">
      <div class="nav-bar">
        <div class="nav-title">Bạn bè</div>
      </div>
      <div class="segmented-picker">
        <div class="seg-item active">Bạn bè</div>
        <div class="seg-item">Lời mời (2)</div>
        <div class="seg-item">Đã gửi</div>
      </div>
      <div class="search-box">
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><circle cx="11" cy="11" r="8"/><path d="M21 21l-4.35-4.35"/></svg>
        Tên hoặc @username
      </div>
      <div class="friends-list">
        <!-- Online Section -->
        <div class="section-header online">
          Đang trực tuyến <span class="header-badge">4</span>
        </div>
        <div class="friend-group">
          <div class="friend-row">
            <div class="avatar-wrapper">
              <img class="user-avatar" src="https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=150&q=80" />
              <div class="online-dot"></div>
            </div>
            <div class="user-info">
              <div class="user-name">Hải Yến</div>
              <div class="user-handle">@haiyen.cute · Đang hoạt động</div>
            </div>
            <div class="action-btns">
              <div class="msg-btn">
                <svg width="15" height="15" viewBox="0 0 24 24" fill="currentColor"><path d="M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2z"/></svg>
              </div>
            </div>
          </div>
          <div class="divider-inset"></div>
          <div class="friend-row">
            <div class="avatar-wrapper">
              <img class="user-avatar" src="https://images.unsplash.com/photo-1539571696357-5a69c17a67c6?auto=format&fit=crop&w=150&q=80" />
              <div class="online-dot"></div>
            </div>
            <div class="user-info">
              <div class="user-name">Minh Hoàng</div>
              <div class="user-handle">@hoang.photo · Đang quay video</div>
            </div>
            <div class="action-btns">
              <div class="msg-btn">
                <svg width="15" height="15" viewBox="0 0 24 24" fill="currentColor"><path d="M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2z"/></svg>
              </div>
            </div>
          </div>
        </div>

        <!-- Offline Section -->
        <div class="section-header offline" style="margin-top: 6px;">
          Ngoại tuyến <span class="header-badge gray">12</span>
        </div>
        <div class="friend-group">
          <div class="friend-row">
            <div class="avatar-wrapper">
              <img class="user-avatar" src="https://images.unsplash.com/photo-1517841905240-472988babdf9?auto=format&fit=crop&w=150&q=80" />
            </div>
            <div class="user-info">
              <div class="user-name">Thu Trang</div>
              <div class="user-handle">@thutrang · Hoạt động 25 phút trước</div>
            </div>
            <div class="action-btns">
              <div class="msg-btn">
                <svg width="15" height="15" viewBox="0 0 24 24" fill="currentColor"><path d="M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2z"/></svg>
              </div>
            </div>
          </div>
          <div class="divider-inset"></div>
          <div class="friend-row">
            <div class="avatar-wrapper">
              <img class="user-avatar" src="https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?auto=format&fit=crop&w=150&q=80" />
            </div>
            <div class="user-info">
              <div class="user-name">Quốc Đạt</div>
              <div class="user-handle">@dat.studio · Hoạt động hôm qua</div>
            </div>
            <div class="action-btns">
              <div class="msg-btn">
                <svg width="15" height="15" viewBox="0 0 24 24" fill="currentColor"><path d="M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2z"/></svg>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    ${ICONS.homeIndicator}
  </body>
  </html>`;

  await page.setContent(html);
  await page.waitForTimeout(400);
  const outPath = path.join(OUT_DIR, 'ios-simulator-friends.png');
  await page.screenshot({ path: outPath });
  const artPath = path.join(ARTIFACT_DIR, 'ios-simulator-friends.png');
  fs.copyFileSync(outPath, artPath);
  console.log('Saved friends screenshot to:', outPath);
}

async function renderChatScreen(page) {
  const html = `<!DOCTYPE html>
  <html>
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=${IPHONE_WIDTH}, initial-scale=1.0">
    <title>Kinnect Chat iMessage</title>
    <style>
      ${COMMON_CSS}
      .app-viewport {
        width: 100%;
        height: 100%;
        background: #0d0a1c;
        display: flex;
        flex-direction: column;
        padding-top: 54px;
        padding-bottom: 34px;
        overflow: hidden;
      }
      /* Apple Messages Nav Bar */
      .nav-bar-chat {
        height: 52px;
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 0 12px;
        background: #141026;
        border-bottom: 0.8px solid rgba(255, 255, 255, 0.08);
      }
      .nav-back-btn {
        display: flex;
        align-items: center;
        gap: 4px;
        color: #A855F7;
        font-size: 16px;
        font-weight: 500;
        cursor: pointer;
        padding-right: 6px;
      }
      .nav-peer-info {
        display: flex;
        align-items: center;
        gap: 10px;
        cursor: pointer;
      }
      .nav-peer-avatar-wrap {
        position: relative;
        width: 36px;
        height: 36px;
      }
      .nav-peer-avatar {
        width: 36px;
        height: 36px;
        border-radius: 50%;
        object-fit: cover;
      }
      .nav-peer-online {
        position: absolute;
        bottom: 0;
        right: 0;
        width: 10px;
        height: 10px;
        border-radius: 50%;
        background: #2E9E66;
        border: 2px solid #141026;
      }
      .nav-peer-text {
        display: flex;
        flex-direction: column;
        align-items: flex-start;
      }
      .nav-peer-name {
        font-size: 15px;
        font-weight: 600;
        color: #fff;
      }
      .nav-peer-status {
        font-size: 11px;
        color: #2E9E66;
        font-weight: 500;
      }
      .nav-actions {
        display: flex;
        align-items: center;
        gap: 8px;
      }
      .nav-circle-btn {
        width: 34px;
        height: 34px;
        border-radius: 50%;
        background: #231c3c;
        display: flex;
        align-items: center;
        justify-content: center;
        color: #C084FC;
      }

      /* Chat Messages Scroll */
      .chat-messages-container {
        flex: 1;
        padding: 12px 14px;
        display: flex;
        flex-direction: column;
        gap: 12px;
        overflow-y: hidden;
      }
      .chat-time-header {
        align-self: center;
        font-size: 11px;
        color: rgba(255, 255, 255, 0.4);
        font-weight: 500;
        margin: 4px 0;
      }

      /* iMessage Bubbles with authentic asymmetric shapes */
      .bubble-row {
        display: flex;
        position: relative;
        width: 100%;
      }
      .bubble-row.incoming {
        justify-content: flex-start;
      }
      .bubble-row.outgoing {
        justify-content: flex-end;
      }

      .bubble-col {
        display: flex;
        flex-direction: column;
        max-width: 76%;
        position: relative;
      }
      .bubble-col.incoming {
        align-items: flex-start;
      }
      .bubble-col.outgoing {
        align-items: flex-end;
      }

      .message-bubble {
        padding: 9px 14px;
        font-size: 15px;
        line-height: 1.38;
        position: relative;
        word-break: break-word;
      }

      /* Authentic asymmetric iMessage border radii */
      .message-bubble.incoming {
        background: #201a38;
        color: #fff;
        border: 0.8px solid rgba(255, 255, 255, 0.1);
        border-radius: 18px 18px 18px 4px;
      }
      .message-bubble.outgoing {
        background: linear-gradient(135deg, #8E2DE2 0%, #4A00E0 100%);
        color: #fff;
        border-radius: 18px 18px 4px 18px;
        box-shadow: 0 2px 8px rgba(110, 20, 230, 0.35);
      }

      /* Floating Tapback reaction pill */
      .tapback-badge {
        position: absolute;
        top: -10px;
        padding: 2px 6px;
        background: #282144;
        border: 1px solid rgba(255, 255, 255, 0.15);
        border-radius: 12px;
        font-size: 13px;
        box-shadow: 0 4px 10px rgba(0, 0, 0, 0.45);
        display: flex;
        align-items: center;
        justify-content: center;
        z-index: 10;
      }
      .tapback-badge.outgoing {
        left: -8px;
      }
      .tapback-badge.incoming {
        right: -8px;
      }

      .message-footer {
        display: flex;
        align-items: center;
        gap: 6px;
        margin-top: 3px;
        font-size: 11px;
        color: rgba(255, 255, 255, 0.4);
        padding: 0 4px;
      }
      .seen-status {
        color: #A855F7;
        font-weight: 500;
        display: flex;
        align-items: center;
        gap: 2px;
      }

      /* iMessage Input Bar */
      .imessage-input-bar {
        display: flex;
        align-items: center;
        padding: 8px 10px;
        background: #141026;
        border-top: 0.8px solid rgba(255, 255, 255, 0.08);
        gap: 8px;
      }
      .plus-btn {
        width: 32px;
        height: 32px;
        border-radius: 50%;
        background: rgba(255, 255, 255, 0.12);
        color: #fff;
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 20px;
        font-weight: 300;
      }
      .camera-btn {
        color: rgba(255, 255, 255, 0.5);
        display: flex;
        align-items: center;
        justify-content: center;
        width: 28px;
        height: 28px;
      }
      .input-capsule {
        flex: 1;
        background: #201a38;
        border: 0.8px solid rgba(255, 255, 255, 0.12);
        border-radius: 20px;
        padding: 8px 14px;
        display: flex;
        align-items: center;
        justify-content: space-between;
      }
      .input-placeholder {
        font-size: 15px;
        color: rgba(255, 255, 255, 0.4);
      }
      .send-circle-btn {
        width: 28px;
        height: 28px;
        border-radius: 50%;
        background: linear-gradient(135deg, #8E2DE2 0%, #4A00E0 100%);
        display: flex;
        align-items: center;
        justify-content: center;
        color: #fff;
      }
      .mic-btn {
        color: rgba(255, 255, 255, 0.5);
        display: flex;
        align-items: center;
        justify-content: center;
        width: 28px;
        height: 28px;
      }
    </style>
  </head>
  <body>
    ${ICONS.statusBar("9:41")}
    <div class="app-viewport">
      <!-- Apple Messages Navigation Bar -->
      <div class="nav-bar-chat">
        <div class="nav-back-btn">
          <svg width="10" height="18" viewBox="0 0 10 18" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"><path d="M9 1L1 9l8 8"/></svg>
        </div>
        <div class="nav-peer-info">
          <div class="nav-peer-avatar-wrap">
            <img class="nav-peer-avatar" src="https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=150&q=80" />
            <div class="nav-peer-online"></div>
          </div>
          <div class="nav-peer-text">
            <div class="nav-peer-name">Hải Yến</div>
            <div class="nav-peer-status">Đang trực tuyến</div>
          </div>
        </div>
        <div class="nav-actions">
          <div class="nav-circle-btn">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><path d="M20.01 15.38c-1.23 0-2.42-.2-3.53-.56a.977.977 0 0 0-1.01.24l-1.57 1.97c-2.83-1.44-5.15-3.75-6.59-6.59l1.97-1.57c.26-.26.35-.65.24-1.01A11.36 11.36 0 0 1 8.96 4.3a1 1 0 0 0-1-1H4.01a1 1 0 0 0-1 1C3.01 13.94 10.06 21 19.01 21a1 1 0 0 0 1-1v-3.62a1 1 0 0 0-1-1z"/></svg>
          </div>
          <div class="nav-circle-btn">
            <svg width="17" height="17" viewBox="0 0 24 24" fill="currentColor"><path d="M17 10.5V7c0-.55-.45-1-1-1H4c-.55 0-1 .45-1 1v10c0 .55.45 1 1 1h12c.55 0 1-.45 1-1v-3.5l4 4v-11l-4 4z"/></svg>
          </div>
          <div class="nav-circle-btn">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><path d="M12 8c1.1 0 2-.9 2-2s-.9-2-2-2-2 .9-2 2 .9 2 2 2zm0 2c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2zm0 6c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2z"/></svg>
          </div>
        </div>
      </div>

      <!-- Messages Stream -->
      <div class="chat-messages-container">
        <div class="chat-time-header">Hôm nay 09:32</div>

        <!-- Incoming 1 -->
        <div class="bubble-row incoming">
          <div class="bubble-col incoming">
            <div class="message-bubble incoming">
              Chào anh! Giao diện nhắn tin Kinnect Build 122 nhìn xịn sò chuẩn Apple iMessage quá ạ! ✨
            </div>
            <div class="message-footer">
              09:32 · <span style="cursor:pointer">❤️ Thích</span>
            </div>
          </div>
        </div>

        <!-- Outgoing 1 with Tapback reaction -->
        <div class="bubble-row outgoing">
          <div class="bubble-col outgoing">
            <div class="tapback-badge outgoing">❤️</div>
            <div class="message-bubble outgoing">
              Chuẩn luôn em ơi! Đã làm lại đuôi bong bóng tin nhắn bất đối xứng, thanh công cụ iMessage và đồng bộ bạn bè online nhé 🚀
            </div>
            <div class="message-footer">
              09:33 · <span class="seen-status">✓ Đã xem</span>
            </div>
          </div>
        </div>

        <!-- Incoming 2 -->
        <div class="bubble-row incoming">
          <div class="bubble-col incoming">
            <div class="message-bubble incoming">
              Dạ vâng, danh sách ngoại tuyến và trực tuyến hiển thị rất rõ ràng, icon trong tài khoản bo tròn squircle cũng tuyệt đẹp! 🎉
            </div>
            <div class="message-footer">
              09:34
            </div>
          </div>
        </div>

        <!-- Outgoing 2 with sending animation -->
        <div class="bubble-row outgoing">
          <div class="bubble-col outgoing">
            <div class="message-bubble outgoing">
              Anh đang đẩy lên Git để GitHub Actions tự động build file IPA mới đây!
            </div>
            <div class="message-footer">
              09:35 · <span class="seen-status">✓ Đã gửi</span>
            </div>
          </div>
        </div>
      </div>

      <!-- Apple iMessage Input Bar -->
      <div class="imessage-input-bar">
        <div class="plus-btn">+</div>
        <div class="camera-btn">
          <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><path d="M12 12c1.65 0 3-1.35 3-3s-1.35-3-3-3-3 1.35-3 3 1.35 3 3 3zm0 2c-2.21 0-4-1.79-4-4s1.79-4 4-4 4 1.79 4 4-1.79 4-4 4zm7-9h-3.17L14 3H10L8.17 5H5c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V7c0-1.1-.9-2-2-2z"/></svg>
        </div>
        <div class="input-capsule">
          <span class="input-placeholder">Tin nhắn…</span>
          <div class="send-circle-btn">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 19V5M5 12l7-7 7 7"/></svg>
          </div>
        </div>
        <div class="mic-btn">
          <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><path d="M12 14c1.66 0 3-1.34 3-3V5c0-1.66-1.34-3-3-3S9 3.34 9 5v6c0 1.66 1.34 3 3 3zm5-3c0 2.76-2.24 5-5 5s-5-2.24-5-5H5c0 3.53 2.61 6.43 6 6.92V21h2v-2.08c3.39-.49 6-3.39 6-6.92h-2z"/></svg>
        </div>
      </div>
    </div>
    ${ICONS.homeIndicator}
  </body>
  </html>`;

  await page.setContent(html);
  await page.waitForTimeout(400);
  const outPath = path.join(OUT_DIR, 'ios-simulator-chat.png');
  await page.screenshot({ path: outPath });
  const artPath = path.join(ARTIFACT_DIR, 'ios-simulator-chat.png');
  fs.copyFileSync(outPath, artPath);
  console.log('Saved chat screenshot to:', outPath);
}

async function renderOverviewShowcase(page) {
  // Quad device side-by-side presentation
  const OVERVIEW_WIDTH = 1580;
  const OVERVIEW_HEIGHT = 880;

  const html = `<!DOCTYPE html>
  <html>
  <head>
    <meta charset="utf-8">
    <title>Kinnect iOS Parity Showcase</title>
    <style>
      * { box-sizing: border-box; margin: 0; padding: 0; }
      body {
        width: ${OVERVIEW_WIDTH}px;
        height: ${OVERVIEW_HEIGHT}px;
        background: radial-gradient(circle at 50% 20%, #1c1538 0%, #0a0814 100%);
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif;
        color: #fff;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        padding: 24px;
        overflow: hidden;
      }
      .title-section {
        text-align: center;
        margin-bottom: 20px;
      }
      .main-title {
        font-size: 26px;
        font-weight: 800;
        letter-spacing: -0.5px;
        background: linear-gradient(135deg, #fff 30%, #A855F7 100%);
        -webkit-background-clip: text;
        -webkit-text-fill-color: transparent;
      }
      .subtitle {
        font-size: 14px;
        color: rgba(255, 255, 255, 0.6);
        margin-top: 4px;
      }
      .devices-row {
        display: flex;
        gap: 24px;
        align-items: center;
        justify-content: center;
      }
      .device-card {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 10px;
      }
      .device-frame {
        width: 320px;
        height: 694px;
        border-radius: 40px;
        box-shadow: 0 25px 60px rgba(0, 0, 0, 0.7), 0 0 0 9px #1a1924, 0 0 0 10px rgba(255, 255, 255, 0.15);
        overflow: hidden;
        position: relative;
        background: #000;
      }
      .device-frame img {
        width: 100%;
        height: 100%;
        object-fit: cover;
      }
      .card-caption {
        font-size: 13px;
        font-weight: 600;
        color: rgba(255, 255, 255, 0.85);
        display: flex;
        align-items: center;
        gap: 6px;
      }
      .card-caption span {
        font-size: 10px;
        font-weight: 500;
        padding: 2px 7px;
        background: rgba(168, 85, 247, 0.25);
        color: #C084FC;
        border-radius: 10px;
      }
    </style>
  </head>
  <body>
    <div class="title-section">
      <div class="main-title">Kinnect iOS Native Parity — Build 122</div>
      <div class="subtitle">Kiểm thử giao diện giả lập iPhone 16 Pro: Nhắn tin Apple iMessage · Tài khoản Apple Settings · Cuộc gọi FaceTime PiP · Bạn bè Online/Offline</div>
    </div>
    <div class="devices-row">
      <div class="device-card">
        <div class="device-frame">
          <img src="file:///${path.resolve(OUT_DIR, 'ios-simulator-chat.png').replace(/\\/g, '/')}" />
        </div>
        <div class="card-caption">Nhắn tin <span>iMessage & Tapback</span></div>
      </div>
      <div class="device-card">
        <div class="device-frame">
          <img src="file:///${path.resolve(OUT_DIR, 'ios-simulator-account.png').replace(/\\/g, '/')}" />
        </div>
        <div class="card-caption">Mục Tài khoản <span>Apple Settings Squircle</span></div>
      </div>
      <div class="device-card">
        <div class="device-frame">
          <img src="file:///${path.resolve(OUT_DIR, 'ios-simulator-call.png').replace(/\\/g, '/')}" />
        </div>
        <div class="card-caption">Cuộc gọi Video <span>FaceTime PiP & Floating</span></div>
      </div>
      <div class="device-card">
        <div class="device-frame">
          <img src="file:///${path.resolve(OUT_DIR, 'ios-simulator-friends.png').replace(/\\/g, '/')}" />
        </div>
        <div class="card-caption">Danh sách Bạn bè <span>Trực tuyến & Ngoại tuyến</span></div>
      </div>
    </div>
  </body>
  </html>`;

  await page.setViewportSize({ width: OVERVIEW_WIDTH, height: OVERVIEW_HEIGHT });
  await page.setContent(html);
  await page.waitForTimeout(600);
  const outPath = path.join(OUT_DIR, 'ios-simulator-showcase.png');
  await page.screenshot({ path: outPath });
  const artPath = path.join(ARTIFACT_DIR, 'ios-simulator-showcase.png');
  fs.copyFileSync(outPath, artPath);
  console.log('Saved overview showcase to:', outPath);
}

async function main() {
  const browser = await chromium.launch({
    headless: true,
    executablePath: 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe'
  });
  const context = await browser.newContext({
    viewport: { width: IPHONE_WIDTH, height: IPHONE_HEIGHT },
    deviceScaleFactor: 2
  });
  const page = await context.newPage();

  console.log('1. Rendering Chat screen (Apple iMessage)...');
  await renderChatScreen(page);

  console.log('2. Rendering Account screen...');
  await renderAccountScreen(page);

  console.log('3. Rendering Call screen...');
  await renderCallScreen(page);

  console.log('4. Rendering Friends screen...');
  await renderFriendsScreen(page);

  console.log('5. Rendering Overview Showcase...');
  await renderOverviewShowcase(page);

  await browser.close();
  console.log('All screenshots rendered and synced successfully!');
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});

