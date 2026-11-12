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

  // Load avatar frames as base64
  function getBase64(fileRel) {
    const full = path.join(process.cwd(), fileRel);
    if (!fs.existsSync(full)) return '';
    const buf = fs.readFileSync(full);
    const ext = path.extname(full).slice(1);
    const mime = ext === 'webp' ? 'image/webp' : 'image/png';
    return `data:${mime};base64,${buf.toString('base64')}`;
  }

  const frameNeon = getBase64('android/app/src/main/res/drawable/avatar_frame_neon.webp');
  const frameAurora = getBase64('android/app/src/main/res/drawable/avatar_frame_aurora.webp');
  const frameGalaxy = getBase64('android/app/src/main/res/drawable/avatar_frame_galaxy.webp');
  const frameIce = getBase64('android/app/src/main/res/drawable/avatar_frame_ice.webp');
  const frameRuby = getBase64('android/app/src/main/res/drawable/avatar_frame_ruby.webp');
  const frameEmber = getBase64('android/app/src/main/res/drawable/avatar_frame_ember.webp');

  const html = `<!DOCTYPE html>
<html lang="vi">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=412, initial-scale=1.0">
  <title>Kinnect Store 1x1 Parity</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; user-select: none; }
    body {
      width: 412px;
      min-height: 915px;
      background: #0d0c14;
      font-family: -apple-system, BlinkMacSystemFont, "Google Sans", "Segoe UI", Roboto, sans-serif;
      color: #f1f5f9;
      display: flex;
      flex-direction: column;
    }

    /* Top Bar */
    .header-bar {
      width: 100%;
      height: 56px;
      padding: 0 16px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      border-bottom: 1px solid rgba(255, 255, 255, 0.08);
      background: #13111e;
      position: sticky;
      top: 0;
      z-index: 20;
    }
    .back-btn {
      width: 36px;
      height: 36px;
      display: flex;
      align-items: center;
      justify-content: center;
      border-radius: 50%;
      color: #f1f5f9;
    }
    .title-group {
      display: flex;
      align-items: center;
      gap: 8px;
      font-size: 17px;
      font-weight: 700;
    }
    .wallet-chip {
      display: flex;
      align-items: center;
      gap: 6px;
      background: rgba(139, 92, 246, 0.15);
      border: 1px solid rgba(139, 92, 246, 0.35);
      padding: 6px 12px;
      border-radius: 999px;
      font-size: 13px;
      font-weight: 700;
      color: #c084fc;
    }

    /* Scrollable Container */
    .content {
      padding: 16px;
      display: flex;
      flex-direction: column;
      gap: 14px;
    }

    /* Hero Banner */
    .hero-banner {
      border-radius: 20px;
      padding: 18px 18px 20px 18px;
      background: linear-gradient(135deg, #3B1E6D 0%, #1E1338 100%);
      border: 1px solid rgba(192, 132, 252, 0.25);
      box-shadow: 0 10px 24px rgba(59, 30, 109, 0.35);
    }
    .hero-top {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 10px;
    }
    .hero-badge {
      display: flex;
      align-items: center;
      gap: 6px;
      font-size: 11px;
      font-weight: 800;
      letter-spacing: 1.5px;
      color: #c084fc;
    }
    .hero-pill {
      display: flex;
      align-items: center;
      gap: 4px;
      padding: 4px 10px;
      background: rgba(255, 255, 255, 0.18);
      border-radius: 999px;
      font-size: 11px;
      font-weight: 700;
      color: #ffffff;
    }
    .hero-title {
      font-size: 21px;
      font-weight: 800;
      line-height: 1.35;
      color: #ffffff;
    }

    /* Category Filter Strip */
    .category-strip {
      display: flex;
      gap: 8px;
      overflow-x: auto;
      padding-bottom: 4px;
      scrollbar-width: none;
    }
    .cat-tab {
      display: flex;
      align-items: center;
      gap: 6px;
      padding: 7px 14px;
      border-radius: 999px;
      font-size: 12px;
      font-weight: 700;
      white-space: nowrap;
      cursor: pointer;
    }
    .cat-tab.active {
      background: #8b5cf6;
      color: #ffffff;
      box-shadow: 0 4px 14px rgba(139, 92, 246, 0.45);
    }
    .cat-tab.inactive {
      background: #1c182b;
      color: #94a3b8;
      border: 1px solid rgba(255, 255, 255, 0.06);
    }

    /* 2-Column 1x1 Cards Grid */
    .grid {
      display: grid;
      grid-template-columns: repeat(2, 1fr);
      gap: 12px;
    }

    .card {
      background: #161324;
      border-radius: 16px;
      border: 1px solid rgba(255, 255, 255, 0.08);
      overflow: hidden;
      display: flex;
      flex-direction: column;
      box-shadow: 0 4px 16px rgba(0, 0, 0, 0.35);
    }

    /* 1:1 Aspect Ratio Artwork Box */
    .art-box-1x1 {
      position: relative;
      width: 100%;
      aspect-ratio: 1 / 1;
      border-radius: 14px 14px 0 0;
      overflow: hidden;
      display: flex;
      align-items: center;
      justify-content: center;
    }

    /* Avatar inside 1:1 */
    .avatar-wrapper {
      position: relative;
      width: 82%;
      height: 82%;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    .avatar-bg-circle {
      position: absolute;
      width: 72%;
      height: 72%;
      border-radius: 50%;
      background: #23183d;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 26px;
      font-weight: 800;
      color: #ffffff;
    }
    .avatar-frame-img {
      position: absolute;
      width: 100%;
      height: 100%;
      object-fit: contain;
      z-index: 2;
    }

    .tier-badge {
      position: absolute;
      top: 6px;
      right: 6px;
      padding: 3px 8px;
      border-radius: 999px;
      background: rgba(17, 16, 24, 0.85);
      font-size: 9px;
      font-weight: 800;
      letter-spacing: 0.5px;
      z-index: 5;
    }
    .tier-gold { color: #f59e0b; border: 1px solid rgba(245, 158, 11, 0.4); }
    .tier-purple { color: #c084fc; border: 1px solid rgba(192, 132, 252, 0.4); }
    .tier-blue { color: #38bdf8; border: 1px solid rgba(56, 189, 248, 0.4); }

    /* Card Details */
    .card-body {
      padding: 10px;
      display: flex;
      flex-direction: column;
      gap: 4px;
    }
    .card-title {
      font-size: 13.5px;
      font-weight: 700;
      color: #ffffff;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }
    .card-subtitle {
      font-size: 11px;
      color: #94a3b8;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }
    .card-price {
      display: flex;
      align-items: center;
      gap: 4px;
      font-size: 13px;
      font-weight: 800;
      color: #f59e0b;
      margin: 2px 0 6px 0;
    }
    .card-actions {
      display: flex;
      gap: 6px;
    }
    .btn-preview {
      flex: 1;
      padding: 6px 0;
      border-radius: 999px;
      background: rgba(255, 255, 255, 0.08);
      font-size: 11px;
      font-weight: 700;
      color: #c084fc;
      border: 1px solid rgba(192, 132, 252, 0.3);
      cursor: pointer;
      text-align: center;
    }
    .btn-buy {
      flex: 1;
      padding: 6px 0;
      border-radius: 999px;
      background: linear-gradient(135deg, #8b5cf6 0%, #ec4899 100%);
      font-size: 11px;
      font-weight: 700;
      color: #ffffff;
      border: none;
      cursor: pointer;
      text-align: center;
      box-shadow: 0 4px 12px rgba(139, 92, 246, 0.35);
    }
  </style>
</head>
<body>
  <!-- Header Bar -->
  <div class="header-bar">
    <div class="title-group">
      <div class="back-btn">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M19 12H5M12 19l-7-7 7-7"/></svg>
      </div>
      <span>Cửa hàng</span>
    </div>
    <div style="display: flex; align-items: center; gap: 8px;">
      <div class="wallet-chip">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M21 7.28V5c0-1.1-.9-2-2-2H5c-1.11 0-2 .9-2 2v14c0 1.1.89 2 2 2h14c1.1 0 2-.9 2-2v-2.28c.59-.35 1-.98 1-1.72V9c0-.74-.41-1.37-1-1.72zM20 9v6h-7V9h7zM5 19V5h14v2h-6c-1.1 0-2 .9-2 2v6c0 1.1.9 2 2 2h6v2H5z"/></svg>
        <span>10.000 xu</span>
      </div>
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#94a3b8" stroke-width="2"><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/><circle cx="5" cy="12" r="1"/></svg>
    </div>
  </div>

  <div class="content">
    <!-- Hero Shop Banner -->
    <div class="hero-banner">
      <div class="hero-top">
        <div class="hero-badge">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="#c084fc"><path d="M20 4H4v2h16V4zm1 10v-2l-1-5H4l-1 5v2h1v6h10v-6h4v6h2v-6h1zm-9 4H6v-4h6v4z"/></svg>
          <span>KINNECT SHOP</span>
        </div>
        <div class="hero-pill">
          <svg width="12" height="12" viewBox="0 0 24 24" fill="#ffffff"><path d="M12 2l2.4 7.2H21l-5.8 4.3 2.2 7-5.4-4.2-5.4 4.2 2.2-7L3 9.2h6.6z"/></svg>
          <span>Xem thử miễn phí</span>
        </div>
      </div>
      <div class="hero-title">Thêm sắc màu.<br>Thêm chất riêng.</div>
    </div>

    <!-- Category Filter Tabs -->
    <div class="category-strip">
      <div class="cat-tab active">Phong cách</div>
      <div class="cat-tab inactive">Gói Live</div>
      <div class="cat-tab inactive">Gói Studio</div>
      <div class="cat-tab inactive">Quà tặng</div>
      <div class="cat-tab inactive">Hội viên</div>
      <div class="cat-tab inactive">Của tôi</div>
    </div>

    <!-- 2-Column 1x1 Cards Grid (Zero cropping!) -->
    <div class="grid">
      <!-- Card 1: Neon -->
      <div class="card">
        <div class="art-box-1x1" style="background: linear-gradient(135deg, #7c3aed 0%, #06b6d4 100%);">
          <div class="tier-badge tier-purple">SỬ THI</div>
          <div class="avatar-wrapper">
            <div class="avatar-bg-circle">K</div>
            <img class="avatar-frame-img" src="${frameNeon}" alt="Neon Frame">
          </div>
        </div>
        <div class="card-body">
          <div class="card-title">Neon</div>
          <div class="card-subtitle">Dấu ấn thành thị</div>
          <div class="card-price">
            <svg width="13" height="13" viewBox="0 0 24 24" fill="#f59e0b"><circle cx="12" cy="12" r="10"/></svg>
            <span>300 xu</span>
          </div>
          <div class="card-actions">
            <button class="btn-preview">Xem thử</button>
            <button class="btn-buy">Đổi</button>
          </div>
        </div>
      </div>

      <!-- Card 2: Aurora -->
      <div class="card">
        <div class="art-box-1x1" style="background: linear-gradient(135deg, #8b5cf6 0%, #ec4899 100%);">
          <div class="tier-badge tier-gold">HUYỀN THOẠI</div>
          <div class="avatar-wrapper">
            <div class="avatar-bg-circle">K</div>
            <img class="avatar-frame-img" src="${frameAurora}" alt="Aurora Frame">
          </div>
        </div>
        <div class="card-body">
          <div class="card-title">Cực quang</div>
          <div class="card-subtitle">Sắc màu kết nối</div>
          <div class="card-price">
            <svg width="13" height="13" viewBox="0 0 24 24" fill="#f59e0b"><circle cx="12" cy="12" r="10"/></svg>
            <span>500 xu</span>
          </div>
          <div class="card-actions">
            <button class="btn-preview">Xem thử</button>
            <button class="btn-buy">Đổi</button>
          </div>
        </div>
      </div>

      <!-- Card 3: Galaxy -->
      <div class="card">
        <div class="art-box-1x1" style="background: linear-gradient(135deg, #312e81 0%, #a855f7 100%);">
          <div class="tier-badge tier-gold">HUYỀN THOẠI</div>
          <div class="avatar-wrapper">
            <div class="avatar-bg-circle">K</div>
            <img class="avatar-frame-img" src="${frameGalaxy}" alt="Galaxy Frame">
          </div>
        </div>
        <div class="card-body">
          <div class="card-title">Galaxy</div>
          <div class="card-subtitle">Vũ trụ của bạn</div>
          <div class="card-price">
            <svg width="13" height="13" viewBox="0 0 24 24" fill="#f59e0b"><circle cx="12" cy="12" r="10"/></svg>
            <span>800 xu</span>
          </div>
          <div class="card-actions">
            <button class="btn-preview">Xem thử</button>
            <button class="btn-buy">Đổi</button>
          </div>
        </div>
      </div>

      <!-- Card 4: Ruby -->
      <div class="card">
        <div class="art-box-1x1" style="background: linear-gradient(135deg, #9f1239 0%, #fb7185 100%);">
          <div class="tier-badge tier-purple">SỬ THI</div>
          <div class="avatar-wrapper">
            <div class="avatar-bg-circle">K</div>
            <img class="avatar-frame-img" src="${frameRuby}" alt="Ruby Frame">
          </div>
        </div>
        <div class="card-body">
          <div class="card-title">Ruby</div>
          <div class="card-subtitle">Hồng ngọc</div>
          <div class="card-price">
            <svg width="13" height="13" viewBox="0 0 24 24" fill="#f59e0b"><circle cx="12" cy="12" r="10"/></svg>
            <span>600 xu</span>
          </div>
          <div class="card-actions">
            <button class="btn-preview">Xem thử</button>
            <button class="btn-buy">Đổi</button>
          </div>
        </div>
      </div>
    </div>
  </div>
</body>
</html>`;

  await page.setContent(html);
  await page.waitForTimeout(400);

  const outDir = 'outputs';
  const storePath = path.join(outDir, 'store-1x1-screen.png');
  await page.screenshot({ path: storePath });
  console.log('Saved store 1x1 screenshot to:', storePath);

  const artifactDir = 'C:\\Users\\ANH\\.gemini\\antigravity\\brain\\dab8d5cd-f092-4bd6-993e-a0c622455d85';
  if (fs.existsSync(artifactDir)) {
    const artPath = path.join(artifactDir, 'store-1x1-screen.png');
    fs.copyFileSync(storePath, artPath);
    console.log('Copied store 1x1 screenshot to artifact directory:', artPath);
  }

  await browser.close();
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});

