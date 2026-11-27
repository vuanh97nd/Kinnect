/* ============================================================================
   KINNECT · LỚP HÀNH VI V2  (admin-v2.js)
   ----------------------------------------------------------------------------
   Nạp sau admin.js (defer giữ đúng thứ tự) và chỉ BỔ SUNG — không sửa, không
   ghi đè logic nghiệp vụ. Mọi thứ ở đây đều "lớp phủ": nếu file này lỗi hoặc
   không tải được, admin.js vẫn chạy nguyên vẹn như trước.

   Nội dung:
     1. Khởi động giao diện sáng/tối (không nhấp nháy)
     2. Liên kết bỏ qua điều hướng
     3. Nhóm lại thanh điều hướng 13 mục thành 5 nhóm
     4. Đồng bộ aria-current + ẩn nhóm rỗng
     5. Ô tìm nhanh trong thanh điều hướng (Ctrl/⌘ + K)
     6. Thanh điều hướng đáy theo đúng vai trò
     7. Ngăn kéo di động: bẫy focus, aria-expanded, phím Escape
     8. Sửa ARIA: bỏ aria-live khỏi #content, thêm vùng thông báo riêng
     9. Kênh trò chuyện: role="group" + aria-pressed
    10. Bọc bảng để cuộn ngang an toàn trên màn hình hẹp
   ========================================================================== */

(function () {
  'use strict';

  /* --------------------------------------------------------------------------
     Tiện ích nội bộ
     -------------------------------------------------------------------------- */

  const $ = (id) => document.getElementById(id);

  /** Đọc state của admin.js mà không làm vỡ script nếu biến chưa tồn tại. */
  function getState() {
    try { return typeof state !== 'undefined' ? state : null; }
    catch (e) { return null; }
  }

  /** Đọc bảng icon của admin.js (khai báo bằng const ở phạm vi toàn cục). */
  function getIconPaths() {
    try { return typeof iconPaths !== 'undefined' ? iconPaths : null; }
    catch (e) { return null; }
  }

  function currentUser() {
    const s = getState();
    return s && s.user ? s.user : null;
  }

  function currentPage() {
    const s = getState();
    return s && s.page ? s.page : null;
  }

  /* --------------------------------------------------------------------------
     1. GIAO DIỆN SÁNG / TỐI
     --------------------------------------------------------------------------
     Thứ tự ưu tiên: lựa chọn đã lưu > cài đặt hệ điều hành > sáng.
     Việc áp dụng sớm (ngay khi script chạy) tránh hiện tượng "nháy trắng".
     -------------------------------------------------------------------------- */

  const THEME_KEY = 'kinnect:theme';

  function preferredTheme() {
    try {
      const saved = localStorage.getItem(THEME_KEY);
      if (saved === 'light' || saved === 'dark') return saved;
    } catch (e) { /* chế độ riêng tư có thể chặn localStorage */ }
    try {
      if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {
        return 'dark';
      }
    } catch (e) { /* bỏ qua */ }
    return 'light';
  }

  function applyTheme(theme) {
    document.documentElement.setAttribute('data-theme', theme);
    // Đồng bộ màu thanh trình duyệt trên di động.
    const meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.setAttribute('content', theme === 'dark' ? '#100e18' : '#5a2fc0');
    const btn = $('v2-theme-toggle');
    if (btn) {
      btn.textContent = theme === 'dark' ? '☀️' : '🌙';
      btn.setAttribute('aria-label', theme === 'dark' ? 'Chuyển sang giao diện sáng' : 'Chuyển sang giao diện tối');
      btn.title = btn.getAttribute('aria-label');
    }
  }

  function toggleTheme() {
    const next = document.documentElement.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
    applyTheme(next);
    try { localStorage.setItem(THEME_KEY, next); } catch (e) { /* bỏ qua */ }
  }

  applyTheme(preferredTheme());

  /* --------------------------------------------------------------------------
     2. LIÊN KẾT BỎ QUA ĐIỀU HƯỚNG
     -------------------------------------------------------------------------- */

  function installSkipLink() {
    if ($('v2-skip-link')) return;
    const link = document.createElement('a');
    link.id = 'v2-skip-link';
    link.className = 'v2-skip-link';
    link.href = '#content';
    link.textContent = 'Bỏ qua điều hướng, tới nội dung chính';
    document.body.insertBefore(link, document.body.firstChild);

    // #content phải nhận được focus bằng bàn phím.
    const content = $('content');
    if (content && !content.hasAttribute('tabindex')) content.setAttribute('tabindex', '-1');
  }

  /* --------------------------------------------------------------------------
     3. NHÓM THANH ĐIỀU HƯỚNG
     --------------------------------------------------------------------------
     13 mục phẳng khiến người dùng phải quét toàn bộ danh sách mỗi lần tìm một
     chức năng. Chia thành 5 nhóm theo công việc thực tế của từng bộ phận.
     Các nút gốc được GIỮ NGUYÊN (chỉ di chuyển vị trí), nên mọi đoạn mã trong
     admin.js tìm `#navigation button` vẫn hoạt động bình thường.
     -------------------------------------------------------------------------- */

  const NAV_GROUPS = [
    { id: 'tong-quan', label: 'Tổng quan', pages: ['overview'] },
    { id: 'van-hanh', label: 'Vận hành', pages: ['tickets', 'reports', 'resets'] },
    { id: 'thanh-vien', label: 'Thành viên & an toàn', pages: ['users', 'reputation', 'content'] },
    { id: 'tai-chinh', label: 'Tài chính', pages: ['wallet', 'finance'] },
    { id: 'he-thong', label: 'Hệ thống', pages: ['security', 'operations', 'team', 'activity', 'password'] }
  ];

  function buildNavGroups() {
    const nav = $('navigation');
    if (!nav || nav.dataset.v2Grouped === '1') return;

    const byPage = new Map();
    for (const btn of nav.querySelectorAll('button[data-page]')) {
      byPage.set(btn.dataset.page, btn);
    }
    if (byPage.size === 0) return;

    const used = new Set();
    const fragment = document.createDocumentFragment();

    for (const group of NAV_GROUPS) {
      const buttons = group.pages.map((p) => byPage.get(p)).filter(Boolean);
      if (buttons.length === 0) continue;

      const wrap = document.createElement('div');
      wrap.className = 'nav-group';
      wrap.setAttribute('role', 'group');
      wrap.dataset.v2Group = group.id;

      const title = document.createElement('p');
      title.className = 'nav-group-title';
      title.id = 'navg-' + group.id;
      title.textContent = group.label;
      wrap.setAttribute('aria-labelledby', title.id);

      wrap.append(title, ...buttons);
      fragment.append(wrap);
      buttons.forEach((b) => used.add(b));
    }

    // Bất kỳ nút nào chưa được khai báo trong NAV_GROUPS vẫn phải hiển thị,
    // nếu không người dùng sẽ mất chức năng khi có trang mới được thêm.
    const leftovers = [...byPage.values()].filter((b) => !used.has(b));
    if (leftovers.length) {
      const wrap = document.createElement('div');
      wrap.className = 'nav-group';
      wrap.setAttribute('role', 'group');
      wrap.dataset.v2Group = 'khac';
      const title = document.createElement('p');
      title.className = 'nav-group-title';
      title.id = 'navg-khac';
      title.textContent = 'Khác';
      wrap.setAttribute('aria-labelledby', title.id);
      wrap.append(title, ...leftovers);
      fragment.append(wrap);
    }

    nav.replaceChildren(fragment);
    nav.dataset.v2Grouped = '1';
  }

  /* --------------------------------------------------------------------------
     4. ĐỒNG BỘ TRẠNG THÁI ĐIỀU HƯỚNG
     --------------------------------------------------------------------------
     admin.js bật/tắt lớp .active và thuộc tính .hidden. Ta phản chiếu lại:
       - .active  -> aria-current="page"  (trình đọc màn hình đọc "trang hiện tại")
       - nhóm không còn nút hiển thị -> ẩn luôn tiêu đề nhóm
     -------------------------------------------------------------------------- */

  function syncNavState() {
    const nav = $('navigation');
    if (!nav) return;

    for (const btn of nav.querySelectorAll('button[data-page]')) {
      if (btn.classList.contains('active')) btn.setAttribute('aria-current', 'page');
      else btn.removeAttribute('aria-current');
    }

    for (const group of nav.querySelectorAll('.nav-group')) {
      const buttons = [...group.querySelectorAll('button[data-page]')];
      const anyVisible = buttons.some(
        (b) => !b.hidden && b.getAttribute('data-v2-hidden') !== '1'
      );
      group.setAttribute('data-v2-hidden', anyVisible ? '0' : '1');
    }
  }

  /* --------------------------------------------------------------------------
     5. Ô TÌM NHANH CHỨC NĂNG
     --------------------------------------------------------------------------
     Xuất hiện khi thanh điều hướng có từ 8 mục trở lên. Gõ để lọc, Enter mở kết
     quả đầu tiên, Escape xoá lọc. Phím tắt: Ctrl/⌘ + K hoặc "/".
     -------------------------------------------------------------------------- */

  let navFilterInput = null;

  function stripDiacritics(s) {
    return String(s)
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .replace(/đ/g, 'd')
      .replace(/Đ/g, 'D')
      .toLowerCase();
  }

  function installNavFilter() {
    const nav = $('navigation');
    if (!nav || navFilterInput) return;

    const visibleCount = [...nav.querySelectorAll('button[data-page]')].filter((b) => !b.hidden).length;
    if (visibleCount < 8) return;

    const box = document.createElement('div');
    box.className = 'nav-filter';

    const input = document.createElement('input');
    input.type = 'search';
    input.id = 'v2-nav-filter';
    input.placeholder = 'Lọc nhanh menu…  (phím /)';
    input.setAttribute('aria-label', 'Tìm nhanh chức năng trong thanh điều hướng');
    input.autocomplete = 'off';
    input.spellcheck = false;

    box.append(input);
    nav.parentElement.insertBefore(box, nav);

    navFilterInput = input;

    const apply = () => {
      const q = stripDiacritics(input.value.trim());
      for (const btn of nav.querySelectorAll('button[data-page]')) {
        const raw = btn.dataset.navLabel || btn.querySelector('.nav-item-label')?.textContent || btn.textContent || '';
        const label = stripDiacritics(raw);
        const match = q === '' || label.includes(q);
        btn.setAttribute('data-v2-hidden', match ? '0' : '1');
      }
      syncNavState();
    };

    input.addEventListener('input', apply);

    input.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') {
        input.value = '';
        apply();
        input.blur();
        return;
      }
      if (e.key === 'Enter') {
        const first = [...nav.querySelectorAll('button[data-page]')]
          .find((b) => b.getAttribute('data-v2-hidden') !== '1' && !b.hidden && !b.disabled);
        if (first) {
          e.preventDefault();
          first.click();
          input.value = '';
          apply();
        }
      }
    });

    // Phím tắt "/" mở lọc menu nhanh (Ctrl+K dành cho Bảng Lệnh Toàn Cục).
    document.addEventListener('keydown', (e) => {
      const tag = (e.target && e.target.tagName) || '';
      const typing = /^(INPUT|TEXTAREA|SELECT)$/.test(tag) || (e.target && e.target.isContentEditable);
      if (e.key === '/' && !typing && !$('v2-cmd-palette')?.open) {
        e.preventDefault();
        input.focus();
        input.select();
      }
    });
  }

  /* --------------------------------------------------------------------------
     6. THANH ĐIỀU HƯỚNG ĐÁY THEO VAI TRÒ
     --------------------------------------------------------------------------
     Bản cũ dùng pages.slice(0, 4) nên bộ phận Tài chính thấy "Thành viên",
     "Báo cáo"… là những trang họ không có quyền, còn trang họ cần thì bị cắt.
     Ở đây mỗi vai trò có 3 lối tắt đúng nhu cầu + nút Menu đầy đủ.
     -------------------------------------------------------------------------- */

  const SHORT_LABEL = {
    overview: 'Tổng quan',
    tickets: 'Phiếu',
    reputation: 'Uy tín',
    users: 'Thành viên',
    reports: 'Báo cáo',
    resets: 'Khôi phục',
    wallet: 'Ví & Xu',
    finance: 'Đối soát',
    security: 'Bảo mật AI',
    operations: 'Kỹ thuật',
    content: 'Nội dung',
    team: 'Nhân sự',
    activity: 'Nhật ký',
    password: 'Mật khẩu'
  };

  const ROLE_QUICK = {
    admin: ['overview', 'tickets', 'users'],
    support: ['overview', 'tickets', 'users'],
    finance: ['overview', 'wallet', 'finance'],
    operations: ['overview', 'tickets', 'operations']
  };

  function makeNavIcon(page) {
    const paths = getIconPaths();
    if (paths && paths[page]) {
      const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
      svg.setAttribute('viewBox', '0 0 24 24');
      svg.setAttribute('aria-hidden', 'true');
      svg.setAttribute('focusable', 'false');
      svg.classList.add('mobile-nav-icon-svg');
      for (const d of paths[page]) {
        const p = document.createElementNS('http://www.w3.org/2000/svg', 'path');
        p.setAttribute('d', d);
        svg.append(p);
      }
      return svg;
    }
    const span = document.createElement('span');
    span.className = 'mobile-nav-icon';
    span.setAttribute('aria-hidden', 'true');
    span.textContent = '•';
    return span;
  }

  function renderBottomNavV2(pages, mustChange) {
    const bar = $('mobile-bottom-nav');
    if (!bar) return;

    bar.replaceChildren();

    const user = currentUser();
    const team = document.body.getAttribute('data-portal') || 'support';
    const allowed = Array.isArray(pages) ? pages : [];

    let quick;
    if (mustChange) {
      quick = ['password'];
    } else {
      const preferred = ROLE_QUICK[team] || ROLE_QUICK[user && user.role === 'admin' ? 'admin' : 'support'];
      quick = preferred.filter((p) => allowed.includes(p));
      // Nếu vì lý do nào đó không khớp, lùi về 3 trang đầu mà người dùng có quyền.
      if (quick.length === 0) quick = allowed.slice(0, 3);
      // Luôn có "Tổng quan" nếu được phép, vì đây là điểm quay về.
      if (allowed.includes('overview') && !quick.includes('overview')) {
        quick = ['overview', ...quick].slice(0, 3);
      }
    }

    const activePage = currentPage();

    for (const page of quick) {
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'mobile-nav-item';
      btn.dataset.page = page;
      if (page === activePage) btn.classList.add('active');

      const label = document.createElement('small');
      label.textContent = SHORT_LABEL[page] || page;

      btn.append(makeNavIcon(page), label);
      btn.setAttribute('aria-label', 'Mở trang ' + (SHORT_LABEL[page] || page));
      btn.addEventListener('click', () => {
        if (typeof closeMobileNav === 'function') closeMobileNav();
        if (typeof load === 'function') load(page);
      });
      bar.append(btn);
    }

    const more = document.createElement('button');
    more.type = 'button';
    more.className = 'mobile-nav-item';
    more.setAttribute('aria-label', 'Mở toàn bộ menu điều hướng');
    const moreIcon = document.createElement('span');
    moreIcon.className = 'mobile-nav-icon';
    moreIcon.setAttribute('aria-hidden', 'true');
    moreIcon.textContent = '☰';
    const moreLabel = document.createElement('small');
    moreLabel.textContent = 'Menu';
    more.append(moreIcon, moreLabel);
    more.addEventListener('click', () => {
      if (document.body.classList.contains('mobile-nav-open')) {
        if (typeof closeMobileNav === 'function') closeMobileNav();
      } else if (typeof openMobileNav === 'function') {
        openMobileNav();
      }
    });
    bar.append(more);
    if (typeof window.syncNavBadges === 'function') {
      try { window.syncNavBadges(); } catch (e) { /* bỏ qua */ }
    }
  }

  /* Ghi đè hàm gốc. Nếu admin.js đổi chữ ký hàm sau này, ta vẫn giữ nguyên
     hành vi cũ làm phương án dự phòng. */
  if (typeof window.renderMobileBottomNav === 'function') {
    const original = window.renderMobileBottomNav;
    window.renderMobileBottomNav = function (pages, mustChange) {
      try {
        renderBottomNavV2(pages, mustChange);
      } catch (e) {
        original.call(window, pages, mustChange);
      }
    };
  }

  /* --------------------------------------------------------------------------
     7. NGĂN KÉO DI ĐỘNG — QUẢN LÝ FOCUS
     -------------------------------------------------------------------------- */

  const FOCUSABLE = 'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

  function drawerFocusables() {
    const drawer = $('sidebar-drawer');
    if (!drawer) return [];
    return [...drawer.querySelectorAll(FOCUSABLE)].filter(
      (n) => n.offsetParent !== null || n === document.activeElement
    );
  }

  function isMobileLayout() {
    return window.matchMedia('(max-width: 1024px)').matches;
  }

  function installDrawerA11y() {
    const menuBtn = $('mobile-menu-btn');
    const drawer = $('sidebar-drawer');
    if (menuBtn && drawer) {
      menuBtn.setAttribute('aria-controls', 'sidebar-drawer');
      menuBtn.setAttribute('aria-expanded', 'false');
    }

    const origOpen = window.openMobileNav;
    const origClose = window.closeMobileNav;

    if (typeof origOpen === 'function') {
      window.openMobileNav = function () {
        origOpen.apply(window, arguments);
        if (menuBtn) menuBtn.setAttribute('aria-expanded', 'true');
        // Đưa focus vào mục điều hướng đầu tiên đang hiển thị.
        requestAnimationFrame(() => {
          const items = drawerFocusables();
          const firstNav = items.find((n) => n.matches('#navigation button:not([hidden])'));
          (firstNav || items[0] || drawer)?.focus?.();
        });
      };
    }

    if (typeof origClose === 'function') {
      window.closeMobileNav = function () {
        const wasOpen = document.body.classList.contains('mobile-nav-open');
        origClose.apply(window, arguments);
        if (menuBtn) menuBtn.setAttribute('aria-expanded', 'false');
        // Chỉ trả focus về nút Menu nếu focus đang nằm trong ngăn kéo,
        // tránh cướp focus khi người dùng vừa bấm một mục điều hướng.
        if (wasOpen && drawer && drawer.contains(document.activeElement) && menuBtn) {
          menuBtn.focus();
        }
      };
    }

    // Phím Escape đóng ngăn kéo / khung trò chuyện.
    document.addEventListener('keydown', (e) => {
      if (e.key !== 'Escape') return;
      if (document.body.classList.contains('mobile-nav-open')) {
        if (typeof closeMobileNav === 'function') closeMobileNav();
        return;
      }
      const chat = $('chat-drawer');
      if (chat && !chat.hidden) {
        const closeBtn = $('chat-drawer-close');
        if (closeBtn) closeBtn.click();
      }
    });

    // Giữ focus trong ngăn kéo khi đang mở (bẫy Tab).
    document.addEventListener('keydown', (e) => {
      if (e.key !== 'Tab') return;
      if (!document.body.classList.contains('mobile-nav-open')) return;
      if (!isMobileLayout()) return;

      const items = drawerFocusables();
      if (items.length === 0) return;

      const first = items[0];
      const last = items[items.length - 1];

      if (e.shiftKey && document.activeElement === first) {
        e.preventDefault();
        last.focus();
      } else if (!e.shiftKey && document.activeElement === last) {
        e.preventDefault();
        first.focus();
      }
    });

    // Đổi kích thước lên desktop thì đóng ngăn kéo để không kẹt trạng thái.
    window.addEventListener('resize', () => {
      if (!isMobileLayout() && document.body.classList.contains('mobile-nav-open')) {
        if (typeof closeMobileNav === 'function') closeMobileNav();
      }
    });
  }

  /* --------------------------------------------------------------------------
     8. SỬA ARIA CHO VÙNG NỘI DUNG
     --------------------------------------------------------------------------
     `#content` mang aria-live="polite" nên MỖI lần tải lại trang, trình đọc màn
     hình đọc lại toàn bộ bảng và danh sách — cực kỳ ồn. Thay bằng một vùng
     thông báo riêng, chỉ đọc tên trang vừa mở.
     -------------------------------------------------------------------------- */

  function installContentA11y() {
    const content = $('content');
    if (content) content.removeAttribute('aria-live');

    if ($('v2-announcer')) return;
    const announcer = document.createElement('div');
    announcer.id = 'v2-announcer';
    announcer.className = 'v2-sr-only';
    announcer.setAttribute('role', 'status');
    announcer.setAttribute('aria-live', 'polite');
    announcer.setAttribute('aria-atomic', 'true');
    document.body.append(announcer);
  }

  function installPageAnnouncer() {
    const title = $('page-title');
    if (!title) return;

    let last = '';
    const announce = () => {
      const text = (title.textContent || '').trim();
      if (!text || text === last) return;
      last = text;
      const announcer = $('v2-announcer');
      if (announcer) announcer.textContent = 'Đã mở trang ' + text;
    };

    new MutationObserver(announce).observe(title, { childList: true, characterData: true, subtree: true });
  }

  /* --------------------------------------------------------------------------
     9. KÊNH TRÒ CHUYỆN — SỬA ARIA KHÔNG HỢP LỆ
     --------------------------------------------------------------------------
     `role="tablist"` yêu cầu các con phải là `role="tab"` và có `tabpanel` đi
     kèm. Ở đây chúng chỉ là nút lọc, nên đúng ngữ nghĩa là một nhóm nút bật/tắt.
     -------------------------------------------------------------------------- */

  function fixChannelAria() {
    const bar = $('chat-channels-bar');
    if (!bar) return;

    if (bar.getAttribute('role') === 'tablist') {
      bar.setAttribute('role', 'group');
      bar.setAttribute('aria-label', 'Chọn kênh trao đổi');
    }

    for (const chip of bar.querySelectorAll('.channel-chip')) {
      chip.setAttribute('aria-pressed', chip.classList.contains('active') ? 'true' : 'false');
      const name = (chip.textContent || '').trim();
      if (name) chip.setAttribute('aria-label', 'Kênh ' + name);
    }
  }

  /* --------------------------------------------------------------------------
     10. BỌC BẢNG ĐỂ CUỘN NGANG
     --------------------------------------------------------------------------
     Bảng nhiều cột trên điện thoại làm vỡ bố cục trang. Bọc trong một khối
     cuộn ngang để trang giữ nguyên khung nhìn.
     -------------------------------------------------------------------------- */

  let wrappingTables = false;

  function wrapTables() {
    const content = $('content');
    if (!content || wrappingTables) return;

    const tables = content.querySelectorAll('table');
    if (tables.length === 0) return;

    wrappingTables = true;
    try {
      for (const table of tables) {
        const parent = table.parentElement;
        if (!parent) continue;
        if (parent.classList.contains('v2-table-wrap')) continue;

        const wrap = document.createElement('div');
        wrap.className = 'v2-table-wrap';
        parent.insertBefore(wrap, table);
        wrap.append(table);
      }
    } finally {
      wrappingTables = false;
    }
  }

  /* --------------------------------------------------------------------------
     11. BẢNG LỆNH NHANH TOÀN CỤC (Ctrl/⌘ + K COMMAND PALETTE)
     --------------------------------------------------------------------------
     Tìm và nhảy tức thì tới bất kỳ trang quản trị, mở Hồ sơ 360° theo @tên,
     tra cứu nhanh phiếu phối hợp theo từ khóa / #mã, hoặc chạy thao tác nhanh.
     -------------------------------------------------------------------------- */

  function installCommandPalette() {
    const dialog = $('v2-cmd-palette');
    const input = $('v2-cmd-input');
    const list = $('v2-cmd-results');
    const closeBtn = $('v2-cmd-close');
    const triggerBtn = $('v2-cmd-trigger');
    if (!dialog || !input || !list) return;
    if (dialog.dataset.v2CmdBound === '1') return;
    dialog.dataset.v2CmdBound = '1';

    let selectedIdx = 0;
    let ticketSearchTimer = null;
    let remoteSeq = 0;
    let remoteTickets = [];
    let remoteUsers = [];

    function pageTitle(page) {
      try {
        if (typeof names !== 'undefined' && names[page]) return names[page];
      } catch (e) { /* bỏ qua */ }
      return SHORT_LABEL[page] || page;
    }

    function navCount(page) {
      const s = getState();
      return (s && s.navCounts && Number(s.navCounts[page])) || 0;
    }

    function openPalette() {
      const user = currentUser();
      if (!user || user.mustChange) return;
      if (typeof closeMobileNav === 'function') closeMobileNav();
      input.value = '';
      remoteTickets = [];
      remoteUsers = [];
      selectedIdx = 0;
      renderResults();
      if (!dialog.open) dialog.showModal();
      requestAnimationFrame(() => {
        input.focus();
        input.select();
      });
    }

    function closePalette() {
      if (dialog.open) dialog.close();
    }

    function buildItems() {
      const user = currentUser();
      if (!user) return [];
      const allowed = typeof getAllowedPages === 'function' ? getAllowedPages(user) : [];
      const raw = input.value.trim();
      const q = stripDiacritics(raw);
      const team = user.role === 'admin' ? 'admin' : (user.team || 'support');
      const canMember360 = user.role === 'admin' || team === 'support' || team === 'finance';
      const groups = [];

      // 1. Mở nhanh theo @tên hoặc #mã
      const directItems = [];
      if (raw.length >= 2) {
        const cleanMember = raw.replace(/^[@#]/, '').trim();
        if (canMember360 && !raw.startsWith('#') && /^[a-zA-Z0-9_.-]{2,40}$/.test(cleanMember)) {
          directItems.push({
            icon: '🔍',
            title: 'Mở Hồ sơ 360° @' + cleanMember,
            desc: 'Xem điểm uy tín, bài viết, phiếu và ví xu thành viên',
            hint: '360°',
            run: () => typeof openMember360Modal === 'function' && openMember360Modal(cleanMember)
          });
        }
        if (allowed.includes('users') && !raw.startsWith('#')) {
          directItems.push({
            icon: '👥',
            title: 'Tìm thành viên "' + cleanMember + '"',
            desc: 'Mở danh sách thành viên và lọc theo từ khóa',
            hint: 'Thành viên',
            run: () => {
              const s = getState();
              if (s) s.userQueryPrefill = cleanMember;
              if (typeof load === 'function') load('users');
            }
          });
        }
      }
      if (directItems.length) groups.push({ label: 'Tra cứu trực tiếp', items: directItems });

      // 2. Kết quả thành viên tìm từ máy chủ
      if (remoteUsers.length) {
        groups.push({
          label: 'Thành viên khớp từ khóa',
          items: remoteUsers.map((u) => ({
            icon: '👤',
            title: `${u.name || u.username} (@${u.username})`,
            desc: `Uy tín ${Number.isInteger(u.reputation_score) ? u.reputation_score : 100}/100 · ${u.suspended ? 'Đang đình chỉ' : 'Hoạt động'}`,
            hint: 'Mở 360°',
            run: () => typeof openMember360Modal === 'function' && openMember360Modal(u.username)
          }))
        });
      }

      // 3. Kết quả phiếu phối hợp từ máy chủ
      if (remoteTickets.length) {
        groups.push({
          label: 'Phiếu phối hợp liên quan',
          items: remoteTickets.map((t) => ({
            icon: '📋',
            title: `#${String(t.id || '').slice(0, 8).toUpperCase()} · ${t.subject}`,
            desc: (t.member ? t.member + ' · ' : '') + (t.status || ''),
            hint: 'Mở phiếu',
            run: () => typeof openTicket === 'function' && openTicket(t.id)
          }))
        });
      }

      // 4. Chuyển trang nhanh theo quyền
      const pageItems = [];
      for (const page of allowed) {
        const title = pageTitle(page);
        const hay = stripDiacritics(title + ' ' + (SHORT_LABEL[page] || '') + ' ' + page);
        if (q === '' || hay.includes(q)) {
          const count = navCount(page);
          pageItems.push({
            icon: '◫',
            title,
            desc: count > 0 ? `Có ${count} việc đang chờ xử lý` : 'Đi tới mục quản trị',
            hint: count > 0 ? String(count) + ' chờ' : 'Trang',
            run: () => typeof load === 'function' && load(page)
          });
        }
      }
      if (pageItems.length) groups.push({ label: 'Điều hướng nhanh', items: pageItems });

      // 5. Thao tác nhanh
      const actions = [
        {
          icon: '➕',
          title: 'Tiếp nhận & tạo phiếu phối hợp mới',
          desc: 'Chuyển yêu cầu sang Hỗ trợ, Tài chính, Kỹ thuật hoặc Admin',
          hint: 'Tạo mới',
          show: allowed.includes('tickets'),
          run: () => {
            if (typeof load !== 'function') return;
            load('tickets').then(() => {
              setTimeout(() => {
                const c = $('content');
                if (c && typeof newTicket === 'function') newTicket(c);
              }, 40);
            });
          }
        },
        {
          icon: '💬',
          title: 'Bật / Tắt Trao đổi liên bộ phận',
          desc: 'Nhắn tin nội bộ và đính kèm mã phiếu giữa 4 bộ phận',
          hint: 'Chat',
          show: true,
          run: () => {
            const chat = $('chat-drawer');
            if (chat && !chat.hidden && typeof closeChatDrawer === 'function') closeChatDrawer();
            else if (typeof openChatDrawer === 'function') openChatDrawer();
          }
        },
        {
          icon: document.documentElement.getAttribute('data-theme') === 'dark' ? '☀️' : '🌙',
          title: document.documentElement.getAttribute('data-theme') === 'dark'
            ? 'Chuyển sang giao diện Sáng'
            : 'Chuyển sang giao diện Tối',
          desc: 'Tùy chỉnh hiển thị dễ nhìn cho mắt',
          hint: 'Giao diện',
          show: true,
          run: toggleTheme
        },
        {
          icon: '↻',
          title: 'Làm mới dữ liệu trang hiện tại',
          desc: 'Tải lại trạng thái mới nhất từ máy chủ',
          hint: 'Tải lại',
          show: true,
          run: () => $('refresh')?.click()
        }
      ].filter((a) => a.show && (q === '' || stripDiacritics(a.title + ' ' + a.desc).includes(q)));

      if (actions.length) groups.push({ label: 'Thao tác nhanh', items: actions });
      return groups;
    }

    function renderResults() {
      const groups = buildItems();
      list.replaceChildren();
      const flat = [];

      for (const g of groups) {
        const header = document.createElement('div');
        header.className = 'v2-cmd-group';
        header.textContent = g.label;
        list.append(header);

        for (const item of g.items) {
          const idx = flat.length;
          flat.push(item);

          const btn = document.createElement('button');
          btn.type = 'button';
          btn.className = 'v2-cmd-item' + (idx === selectedIdx ? ' is-selected' : '');
          btn.setAttribute('role', 'option');
          btn.setAttribute('aria-selected', idx === selectedIdx ? 'true' : 'false');

          const left = document.createElement('div');
          left.className = 'v2-cmd-item-main';
          const ico = document.createElement('span');
          ico.className = 'v2-cmd-item-ico';
          ico.setAttribute('aria-hidden', 'true');
          ico.textContent = item.icon || '•';
          const txt = document.createElement('div');
          txt.className = 'v2-cmd-item-text';
          const titleEl = document.createElement('b');
          titleEl.textContent = item.title;
          const descEl = document.createElement('small');
          descEl.textContent = item.desc || '';
          txt.append(titleEl, descEl);
          left.append(ico, txt);

          const right = document.createElement('span');
          right.className = 'v2-cmd-item-hint';
          right.textContent = item.hint || '';

          btn.append(left, right);
          btn.addEventListener('click', () => {
            closePalette();
            item.run();
          });
          btn.addEventListener('mouseenter', () => {
            selectedIdx = idx;
            for (const elBtn of list.querySelectorAll('.v2-cmd-item')) {
              const active = elBtn === btn;
              elBtn.classList.toggle('is-selected', active);
              elBtn.setAttribute('aria-selected', active ? 'true' : 'false');
            }
          });
          list.append(btn);
        }
      }

      if (flat.length === 0) {
        selectedIdx = 0;
        const emptyEl = document.createElement('div');
        emptyEl.className = 'v2-cmd-empty';
        emptyEl.textContent = 'Không tìm thấy trang, thành viên hoặc phiếu nào khớp.';
        list.append(emptyEl);
      } else if (selectedIdx >= flat.length) {
        selectedIdx = 0;
        const firstBtn = list.querySelector('.v2-cmd-item');
        if (firstBtn) {
          firstBtn.classList.add('is-selected');
          firstBtn.setAttribute('aria-selected', 'true');
        }
      }
    }

    function scheduleRemoteLookup() {
      clearTimeout(ticketSearchTimer);
      const raw = input.value.trim();
      const clean = raw.replace(/^[@#]/, '').trim();
      if (clean.length < 2 || typeof api !== 'function') {
        remoteTickets = [];
        remoteUsers = [];
        renderResults();
        return;
      }
      const seq = ++remoteSeq;
      const user = currentUser();
      const allowed = typeof getAllowedPages === 'function' ? getAllowedPages(user) : [];
      ticketSearchTimer = setTimeout(async () => {
        const tasks = [];
        if (allowed.includes('tickets')) {
          tasks.push(
            api('tickets?q=' + encodeURIComponent(clean))
              .then((res) => (Array.isArray(res?.tickets) ? res.tickets.slice(0, 5) : []))
              .catch(() => [])
          );
        } else {
          tasks.push(Promise.resolve([]));
        }
        if (allowed.includes('users') && !raw.startsWith('#')) {
          tasks.push(
            api('users?q=' + encodeURIComponent(clean))
              .then((res) => (Array.isArray(res?.users) ? res.users.slice(0, 4) : []))
              .catch(() => [])
          );
        } else {
          tasks.push(Promise.resolve([]));
        }
        const [ticketsRes, usersRes] = await Promise.all(tasks);
        if (seq !== remoteSeq || !dialog.open) return;
        remoteTickets = ticketsRes;
        remoteUsers = usersRes;
        renderResults();
      }, 220);
    }

    input.addEventListener('input', () => {
      selectedIdx = 0;
      renderResults();
      scheduleRemoteLookup();
    });

    input.addEventListener('keydown', (e) => {
      const items = [...list.querySelectorAll('.v2-cmd-item')];
      if (e.key === 'Escape') {
        e.preventDefault();
        closePalette();
        return;
      }
      if (!items.length) return;
      if (e.key === 'ArrowDown') {
        e.preventDefault();
        selectedIdx = (selectedIdx + 1) % items.length;
      } else if (e.key === 'ArrowUp') {
        e.preventDefault();
        selectedIdx = (selectedIdx - 1 + items.length) % items.length;
      } else if (e.key === 'Enter') {
        e.preventDefault();
        const chosen = items[selectedIdx] || items[0];
        if (chosen) chosen.click();
        return;
      } else {
        return;
      }
      items.forEach((btn, i) => {
        const active = i === selectedIdx;
        btn.classList.toggle('is-selected', active);
        btn.setAttribute('aria-selected', active ? 'true' : 'false');
        if (active) btn.scrollIntoView({ block: 'nearest' });
      });
    });

    if (closeBtn) closeBtn.addEventListener('click', closePalette);
    if (triggerBtn) triggerBtn.addEventListener('click', openPalette);
    dialog.addEventListener('click', (e) => {
      if (e.target === dialog) closePalette();
    });

    document.addEventListener('keydown', (e) => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault();
        if (dialog.open) closePalette();
        else openPalette();
      }
    });
  }

  /* --------------------------------------------------------------------------
     KHỞI ĐỘNG
     -------------------------------------------------------------------------- */

  function boot() {
    installSkipLink();
    installContentA11y();
    installDrawerA11y();
    fixChannelAria();
    buildNavGroups();
    syncNavState();
    installNavFilter();
    installCommandPalette();
    installPageAnnouncer();
    wrapTables();

    // Nút đổi giao diện sáng/tối, đặt cạnh cụm công cụ ở đầu trang.
    const tools = document.querySelector('.header-tools');
    if (tools && !$('v2-theme-toggle')) {
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.id = 'v2-theme-toggle';
      btn.className = 'v2-theme-toggle';
      btn.addEventListener('click', toggleTheme);
      tools.insertBefore(btn, tools.firstChild);
      applyTheme(document.documentElement.getAttribute('data-theme') || preferredTheme());
    }

    // Theo dõi thay đổi trạng thái điều hướng do admin.js gây ra.
    const nav = $('navigation');
    if (nav) {
      let queued = false;
      const schedule = () => {
        if (queued) return;
        queued = true;
        requestAnimationFrame(() => {
          queued = false;
          syncNavState();
        });
      };
      new MutationObserver(schedule).observe(nav, {
        subtree: true,
        attributes: true,
        attributeFilter: ['class', 'hidden', 'disabled']
      });
    }

    // Ô tìm nhanh chỉ nên xuất hiện sau khi biết người dùng thấy bao nhiêu mục.
    const workspace = $('workspace');
    if (workspace) {
      new MutationObserver(() => {
        if (!workspace.hidden) installNavFilter();
      }).observe(workspace, { attributes: true, attributeFilter: ['hidden'] });
    }

    // Theo dõi nội dung để bọc bảng và đồng bộ kênh trò chuyện.
    const content = $('content');
    if (content) {
      new MutationObserver(() => {
        wrapTables();
      }).observe(content, { childList: true });
    }

    const channels = $('chat-channels-bar');
    if (channels) {
      new MutationObserver(fixChannelAria).observe(channels, {
        subtree: true,
        attributes: true,
        attributeFilter: ['class']
      });
    }

    // Nếu người dùng đã đăng nhập trước khi lớp này chạy (ví dụ tải lại trang
    // trong lúc phiên còn hiệu lực), dựng lại thanh điều hướng đáy cho đúng.
    const ws = $('workspace');
    if (ws && !ws.hidden && typeof window.renderMobileBottomNav === 'function') {
      const user = currentUser();
      if (user) {
        try {
          const pages = typeof getAllowedPages === 'function' ? getAllowedPages(user) : [];
          window.renderMobileBottomNav(pages, user.mustChange);
        } catch (e) { /* giữ nguyên thanh đáy do admin.js dựng */ }
      }
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
