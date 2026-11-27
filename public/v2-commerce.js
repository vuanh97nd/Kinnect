// Lazy-loaded Commerce (Wallet + Store) screens for Kinnect Web v2.

export function storePreview({ s, esc, av }) {
  const p = s.store?.products.find((item) => item.id === s.storePreview);
  return p
    ? `<section class="panel kn-store-preview"><h2>Xem thử · ${esc(p.name)}</h2>${av({ name: "Minh Anh", storeStyle: p.id })}<p class="store-preview-chat store-${esc(p.id)}">Xin chào! Đây là bản xem thử.</p><p>${esc(p.description)}</p><small>Xem thử không thay đổi hồ sơ và không cấp quyền sử dụng.</small></section>`
    : "";
}

export function storeArtwork(p, { esc, ic }) {
  return '<div class="store-art store-' + esc(p.id) + '">' + (
    p.kind === "studio"
      ? '<div class="store-film"><i>' + ic("sparkles") + "</i><i>" + ic("play") + "</i><i>" + ic("clapperboard") + '</i></div><span class="store-art-caption">AURORA · TRAVEL · CINEMA</span>'
      : '<div class="store-art-orbit"></div><div class="store-art-avatar">K</div><div class="store-art-chat"><i></i><i></i></div><span class="store-art-caption">' + esc(p.name.toUpperCase()) + " COLLECTION</span>"
  ) + "</div>";
}

export function renderWalletScreen({ s, ic, esc, btn, loading, childHeading }) {
  const w = s.wallet;
  if (!w) return childHeading("Ví Kinnect") + loading();
  const money = (n) => Number(n || 0).toLocaleString("vi-VN") + "đ";
  const xu = (n) => Number(n || 0).toLocaleString("vi-VN") + " xu";
  const purchased = Number(w.purchasedCoins || 0);
  const gifted = Number(w.giftedCoins ?? w.trialCoins ?? 0);
  const withdrawable = Number(w.withdrawableVnd ?? w.earningsVnd ?? 0);
  const entries = Array.isArray(w.entries) ? w.entries : [];
  const formatEntryAmount = (e) => {
    if (e.currency === "vnd" || e.kind === "creator_settlement") return money(e.creatorVnd);
    const delta = Number(e.coins || 0);
    return (delta > 0 ? "+" : delta < 0 ? "-" : "") + Math.abs(delta).toLocaleString("vi-VN") + " xu";
  };
  return childHeading("Ví Kinnect")
    + '<section class="kn-wallet"><div class="wallet-balance"><span>' + ic("wallet") + " VÍ KINNECT</span><h2>"
    + Number(w.coins || 0).toLocaleString("vi-VN") + " <small>xu</small></h2>"
    + '<p class="wallet-breakdown">Xu mua: <strong>' + xu(purchased) + '</strong> · Xu tặng: <strong>' + xu(gifted) + "</strong></p>"
    + btn("Nạp xu", "plus", "wallet-unavailable", "primary")
    + '</div><div class="panel wallet-earnings"><span>Thu nhập từ Live</span><h2>' + money(w.earningsVnd) + '</h2><p>Khả dụng rút: <strong>' + money(withdrawable) + "</strong> · Bạn nhận 75% · Nền tảng 25%</p>"
    + btn("Rút tiền", "arrow-up-right", "wallet-unavailable", "secondary")
    + '</div><p class="wallet-status">Đang kết nối thanh toán và chi trả tự động. Chưa mở nạp, mua bằng xu hoặc rút tiền.</p><section class="panel"><h2>Lịch sử giao dịch</h2>'
    + (entries.length
      ? entries.map((e) => '<div class="wallet-history"><span>' + esc(e.title || (e.kind === "creator_settlement" ? "Thu nhập quà tặng" : e.kind)) + (e.subtitle ? "<small> · " + esc(e.subtitle) + "</small>" : "") + "</span><strong>" + formatEntryAmount(e) + "</strong><small>" + new Date(e.created).toLocaleString("vi-VN") + "</small></div>").join("")
      : "<p>Chưa có giao dịch</p>")
    + '</section><p class="wallet-status">Tỷ lệ chia áp dụng sau phí thanh toán và hoàn tiền. Xu mua vật phẩm và thu nhập được rút là hai số dư riêng.</p></section>';
}

export function renderStoreScreen(ctx) {
  const { s, ic, esc, btn, loading, childHeading } = ctx;
  const data = s.store;
  if (!data) return childHeading("Cửa hàng Kinnect") + loading();
  const filter = s.storeFilter || "style";
  const isOwned = (p) => (p.id === "kinnect_studio_pro" ? !!data.studioProPermanent : (data.owned || []).includes(p.id));
  const products = data.products.filter((p) => (filter === "owned" ? isOwned(p) : p.kind === filter));
  return childHeading("Cửa hàng Kinnect")
    + `<section class="kn-store"><div class="store-hero"><div class="store-hero-copy"><span class="store-eyebrow">${ic("shopping-bag")} KINNECT SHOP</span><h2>Thêm sắc màu.<br>Thêm chất riêng.</h2><span class="store-status">${ic("sparkles")} Xem thử miễn phí</span></div><div class="store-hero-art" aria-hidden="true"><span><img src="/kinnect-logo-v106.svg" alt=""></span><i></i><b>${ic("sparkles")}</b></div></div><div class="store-category" aria-label="Danh mục cửa hàng">${[["style", "palette", "Phong cách"], ["studio", "clapperboard", "Studio Pro"], ["owned", "check", "Đã sở hữu"]].map(([v, i, t]) => `<button type="button" data-do="store-filter" data-value="${v}" aria-pressed="${filter === v}">${ic(i)}<span>${t}</span></button>`).join("")}</div>${storePreview(ctx)}<div class="store-section-title"><h2>${filter === "studio" ? "Sáng tạo cùng Studio Pro" : filter === "owned" ? "Bộ sưu tập của bạn" : "Chọn màu cho cá tính"}</h2><small>${products.length} lựa chọn</small></div><div class="kn-store-grid">${products.map((p) => {
      const owned = isOwned(p);
      return `<article class="panel kn-store-product">${storeArtwork(p, ctx)}<div class="store-product-copy"><div class="store-product-title"><h2>${esc(p.name)}</h2>${ic(p.kind === "studio" ? "clapperboard" : "palette")}</div><div class="store-price">${owned ? "Đã sở hữu" : Number(p.referenceVnd).toLocaleString("vi-VN") + "đ"}<small>${owned ? "Đồng bộ theo tài khoản" : "Giá dự kiến · Mua một lần"}</small></div>${btn("Xem thử", "eye", "store-preview", "primary", p.id)}${owned ? btn(data.appearance === p.id ? "Đang sử dụng" : p.kind === "style" ? "Áp dụng" : "Mở trên Android", "check", p.kind === "style" ? "store-apply" : "store-info", "secondary", p.id) : '<span class="store-coming-soon">Chưa mở bán trên web</span>'}</div></article>`;
    }).join("") || '<p class="panel">Bộ sưu tập đang chờ phong cách đầu tiên của bạn.</p>'}</div><div class="store-footer">${btn("Khôi phục & đồng bộ", "refresh-cw", "nav", "secondary", "store")}${data.appearance ? btn("Phong cách mặc định", "palette", "store-apply", "secondary", "") : ""}<p>Xem thử miễn phí · Chưa mở bán. Studio Pro dành cho Android.</p></div></section>`;
}
