const $ = id => document.getElementById(id), state = { user: null, page: 'overview', revision: 0, ticketId: null };
const names = {
  overview: 'Tổng quan',
  tickets: 'Phiếu phối hợp',
  reputation: 'Điểm uy tín & Vi phạm',
  users: 'Thành viên',
  reports: 'Báo cáo',
  resets: 'Khôi phục tài khoản',
  wallet: 'Tặng xu & Bù giao dịch',
  finance: 'Tài chính & đối soát',
  operations: 'Kỹ thuật & hệ thống',
  content: 'Quản lý nội dung',
  team: 'Nhân sự & phân quyền',
  activity: 'Nhật ký thao tác',
  password: 'Đổi mật khẩu'
};
const shortNames = {
  overview: 'Tổng quan',
  tickets: 'Phiếu xử lý',
  reputation: 'Uy tín',
  users: 'Thành viên',
  reports: 'Báo cáo',
  resets: 'Khôi phục',
  wallet: 'Ví & Xu',
  finance: 'Đối soát',
  operations: 'Kỹ thuật',
  content: 'Nội dung',
  team: 'Nhân sự',
  activity: 'Nhật ký',
  password: 'Mật khẩu'
};
const descriptions = {
  overview: 'Trung tâm điều hành đa bộ phận: nắm bắt tức thời tình hình hệ thống, hàng chờ liên phòng ban và tác vụ ưu tiên.',
  tickets: 'Tiếp nhận, xử lý trực tiếp, bàn giao liên bộ phận (Admin · Hỗ trợ · Tài chính · Kỹ thuật) và tra cứu 360° khách hàng.',
  reputation: 'Biểu phí trừ điểm mới thân thiện (khởi tạo 100/100 điểm), giám sát vi phạm AI và bảo vệ thành viên tử tế.',
  users: 'Tra cứu hồ sơ 360° thành viên, điểm uy tín, lịch sử giao dịch, cấp mật khẩu tạm hoặc đình chỉ/mở khóa.',
  reports: 'Xử lý báo cáo vi phạm kèm xem trực tiếp ảnh/video bài đăng, trừ điểm uy tín hoặc chuyển bộ phận chuyên trách.',
  resets: 'Xác minh chủ tài khoản trước khi cấp mật khẩu tạm dùng 1 lần.',
  team: 'Admin quản lý tài khoản nhân sự, phân bổ bộ phận (Hỗ trợ, Kỹ thuật, Tài chính) và kiểm soát phiên làm việc.',
  activity: 'Nhật ký kiểm toán (Audit Trail) bất biến ghi nhận mọi thao tác của Admin và các bộ phận.',
  password: 'Đổi mật khẩu bảo mật cho tài khoản nhân sự (hỗ trợ chữ HOA, chữ thường, số và ký tự đặc biệt).',
  finance: 'Đối soát sổ cái xu, doanh thu VND, lịch sử tặng quà và lập đề nghị bù xu trình Admin phê duyệt.',
  operations: 'Trung tâm điều hành Kỹ thuật (SRE & DevOps): giám sát tài nguyên, điều khiển AI Pipeline và nhật ký máy chủ.',
  content: 'Kiểm tra trực quan nội dung, hình ảnh và video bài đăng gần đây của thành viên.',
  wallet: 'Tách biệt chiến dịch xu tặng và bù xu mua; quy trình Maker-Checker 2 lớp do Admin phê duyệt ghi sổ.'
};

const el = (tag, text, cls) => {
  const n = document.createElement(tag);
  if (text !== undefined) n.textContent = String(text ?? '');
  if (cls) n.className = cls;
  return n;
};

function toast(message) {
  const n = $('notice');
  if (!n) return;
  n.textContent = message;
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => { n.textContent = ''; }, 6000);
}

async function api(path, data) {
  const r = await fetch('/api/console/' + path, {
    method: data === undefined ? 'GET' : 'POST',
    credentials: 'same-origin',
    cache: 'no-store',
    headers: data === undefined ? {} : { 'Content-Type': 'application/json' },
    body: data === undefined ? undefined : JSON.stringify(data)
  });
  const d = await r.json().catch(() => ({}));
  if (!r.ok) {
    if (r.status === 401 && path !== 'login' && path !== 'password') signedOut();
    throw Error(d.error || 'Không kết nối được máy chủ.');
  }
  return d;
}

function closeMobileNav() {
  document.body.classList.remove('mobile-nav-open');
  if ($('mobile-backdrop')) $('mobile-backdrop').hidden = true;
}

function openMobileNav() {
  document.body.classList.add('mobile-nav-open');
  if ($('mobile-backdrop')) $('mobile-backdrop').hidden = false;
}

function signedOut() {
  state.user = null;
  state.ticketId = null;
  state.revision++;
  closeMobileNav();
  $('workspace').hidden = true;
  $('login').hidden = false;
  $('content').replaceChildren();
  $('password').value = '';
  if ($('secret-dialog')?.open) $('secret-dialog').close();
  $('secret-value').value = '';
}

function getAllowedPages(user) {
  return user.role === 'admin'
    ? ['overview', 'tickets', 'reputation', 'users', 'reports', 'resets', 'wallet', 'finance', 'operations', 'content', 'team', 'activity']
    : user.team === 'finance'
      ? ['overview', 'tickets', 'wallet', 'finance', 'activity', 'password']
      : user.team === 'operations'
        ? ['overview', 'tickets', 'operations', 'activity', 'password']
        : ['overview', 'tickets', 'reputation', 'users', 'reports', 'resets', 'content', 'activity', 'password'];
}

function renderMobileBottomNav(pages, mustChange) {
  const bar = $('mobile-bottom-nav');
  if (!bar) return;
  bar.replaceChildren();
  const quickIcons = {
    overview: '◫',
    tickets: '📋',
    reputation: '⭐',
    users: '👥',
    reports: '⚑',
    wallet: '🪙',
    finance: '📊',
    operations: '💻',
    content: '📝',
    activity: '≡',
    password: '⚙'
  };
  const primaryPages = mustChange ? ['password'] : pages.slice(0, 4);
  for (const p of primaryPages) {
    const btn = el('button', undefined, 'mobile-nav-item');
    btn.type = 'button';
    btn.dataset.page = p;
    btn.append(el('span', quickIcons[p] || '•', 'mobile-nav-icon'), el('small', shortNames[p] || names[p]));
    btn.onclick = () => {
      closeMobileNav();
      load(p);
    };
    bar.append(btn);
  }
  const moreBtn = el('button', undefined, 'mobile-nav-item');
  moreBtn.type = 'button';
  moreBtn.append(el('span', '☰', 'mobile-nav-icon'), el('small', 'Menu'));
  moreBtn.onclick = () => {
    if (document.body.classList.contains('mobile-nav-open')) closeMobileNav();
    else openMobileNav();
  };
  bar.append(moreBtn);
}

function updateActiveNav(page) {
  for (const b of $('navigation').querySelectorAll('button')) {
    b.classList.toggle('active', b.dataset.page === page);
  }
  const bar = $('mobile-bottom-nav');
  if (bar) {
    for (const b of bar.querySelectorAll('button[data-page]')) {
      b.classList.toggle('active', b.dataset.page === page);
    }
  }
}

function signedIn(user) {
  state.user = user;
  $('login').hidden = true;
  $('workspace').hidden = false;
  closeMobileNav();
  const team = user.role === 'admin' ? 'admin' : user.team || 'support';
  document.body.setAttribute('data-portal', team);
  if ($('portal-badge')) $('portal-badge').textContent = team.toUpperCase();
  $('identity').textContent = user.name || user.username;
  $('role-name').textContent = user.role === 'admin' ? 'Admin cấp cao nhất' : user.team === 'finance' ? 'Bộ phận Tài chính' : user.team === 'operations' ? 'Bộ phận Kỹ thuật' : 'Hỗ trợ & Kiểm duyệt';
  $('role-label').textContent = user.role === 'admin' ? 'ADMIN WORKSPACE' : user.team === 'finance' ? 'FINANCE WORKSPACE' : user.team === 'operations' ? 'OPERATIONS WORKSPACE' : 'SUPPORT WORKSPACE';

  const pages = getAllowedPages(user);
  for (const n of $('navigation').querySelectorAll('button')) n.hidden = !pages.includes(n.dataset.page);
  $('team-nav').hidden = user.role !== 'admin';
  $('password-nav').hidden = user.role !== 'support';
  for (const n of $('navigation').querySelectorAll('button')) n.disabled = user.mustChange && n.dataset.page !== 'password';
  renderMobileBottomNav(pages, user.mustChange);
  load(user.mustChange ? 'password' : 'overview');
}

async function confirmAction(title, message) {
  const d = $('confirm-dialog');
  $('confirm-title').textContent = title;
  $('confirm-message').textContent = message;
  d.returnValue = 'cancel';
  d.showModal();
  return new Promise(resolve => d.addEventListener('close', () => resolve(d.returnValue === 'confirm'), { once: true }));
}

function secret(data) {
  $('secret-user').textContent = '@' + data.username;
  $('secret-value').value = data.temporaryPassword;
  $('secret-dialog').showModal();
}
$('secret-close').onclick = () => { $('secret-dialog').close(); $('secret-value').value = ''; };
$('secret-dialog').addEventListener('close', () => { $('secret-value').value = ''; });
$('copy-secret').onclick = async () => {
  try {
    await navigator.clipboard.writeText($('secret-value').value);
    toast('Đã sao chép mật khẩu tạm.');
  } catch {
    $('secret-value').select();
    toast('Hãy sao chép mật khẩu đang được bôi đen.');
  }
};

function button(text, fn, cls) {
  const b = el('button', text, cls);
  b.type = 'button';
  b.onclick = async () => {
    b.disabled = true;
    try { await fn(); } catch (e) { toast(e.message); } finally { b.disabled = false; }
  };
  return b;
}
function badge(text, cls = '') { return el('span', text, 'badge ' + cls); }
function date(value) { return value ? new Date(Number(value)).toLocaleString('vi-VN') : '—'; }
function empty(root, message) { root.append(el('div', message, 'empty')); }

function table(root, head, rows) {
  if (!rows.length) { empty(root, 'Chưa có dữ liệu phù hợp.'); return; }
  const wrap = el('div', undefined, 'table-wrap'), t = el('table'), tr = el('tr');
  head.forEach(x => tr.append(el('th', x)));
  const h = el('thead'); h.append(tr); t.append(h);
  const body = el('tbody');
  for (const row of rows) {
    const line = el('tr');
    for (let i = 0; i < row.length; i++) {
      const item = row[i];
      const cell = el('td');
      if (head[i]) cell.setAttribute('data-label', head[i]);
      cell.append(item instanceof Node ? item : document.createTextNode(String(item ?? '—')));
      line.append(cell);
    }
    body.append(line);
  }
  t.append(body); wrap.append(t); root.append(wrap);
}

async function mutate(path, data, title, message) {
  if (!await confirmAction(title, message)) return;
  const result = await api(path, data);
  if (result.temporaryPassword) secret(result); else toast('Đã cập nhật.');
  await load(state.page);
}

function makePasswordInputWithToggle(placeholder = 'Nhập mật khẩu...', auto = 'current-password', minLen = 0) {
  const wrap = el('div', undefined, 'password-field-wrap');
  const input = el('input');
  input.type = 'password';
  input.autocomplete = auto;
  input.required = true;
  input.maxLength = 128;
  input.placeholder = placeholder;
  if (minLen > 0) input.minLength = minLen;
  const toggle = el('button', '👁️ Hiện', 'password-toggle-btn');
  toggle.type = 'button';
  toggle.setAttribute('aria-label', 'Hiện hoặc ẩn mật khẩu');
  toggle.onclick = () => {
    const show = input.type === 'password';
    input.type = show ? 'text' : 'password';
    toggle.textContent = show ? '🙈 Ẩn' : '👁️ Hiện';
    input.focus();
  };
  wrap.append(input, toggle);
  return { wrap, input, toggle };
}

async function load(page) {
  if (!state.user) return;
  state.ticketId = null;
  state.page = page;
  closeMobileNav();
  const rev = ++state.revision;
  $('page-title').textContent = names[page] || page;
  $('page-description').textContent = descriptions[page] || '';
  updateActiveNav(page);
  const root = el('div', 'Đang tải dữ liệu…', 'muted');
  $('content').replaceChildren(root);
  try {
    await render(page, root, rev);
    if (rev !== state.revision) root.remove();
  } catch (e) {
    if (rev === state.revision) {
      root.replaceChildren();
      empty(root, e.message);
      root.append(button('Thử lại', () => load(page)));
    }
  }
}

async function render(page, root, rev) {
  if (page === 'wallet') {
    if (typeof window.renderWalletTools !== 'function') {
      await new Promise((resolve, reject) => {
        const s = document.createElement('script');
        s.src = '/admin/wallet-tools.js?v=20261109c';
        s.onload = resolve;
        s.onerror = () => reject(new Error('Chưa tải được tệp /admin/wallet-tools.js'));
        document.head.append(s);
      });
    }
    if (typeof window.renderWalletTools === 'function') {
      return window.renderWalletTools({ root, api, el, button, badge, table, empty, toast, confirmAction, me: state.user, refresh: () => load('wallet'), date });
    }
    throw new Error('Chức năng Tặng xu & Bù giao dịch chưa sẵn sàng.');
  }
  if (page === 'reputation') return renderReputationPage(root, rev);
  if (page === 'content') return renderContentPage(root, rev);
  if (['tickets', 'finance', 'operations'].includes(page)) return extraRender(page, root, rev);

  if (page === 'password') {
    root.replaceChildren();
    const form = el('form', undefined, 'card password-form');
    form.append(
      el('h3', state.user.mustChange ? '🔐 Đổi mật khẩu tạm để bắt đầu làm việc' : '🔐 Đổi mật khẩu tài khoản'),
      el('p', 'Mật khẩu có phân biệt chữ HOA, chữ thường, chữ số và ký tự đặc biệt. Bấm vào biểu tượng 👁️ Hiện để kiểm tra chính xác trước khi lưu.', 'muted')
    );
    const inputs = {};
    for (const [key, label, auto, minL] of [
      ['current', 'Mật khẩu hiện tại', 'current-password', 0],
      ['password', 'Mật khẩu mới (ít nhất 12 ký tự, phân biệt HOA/thường)', 'new-password', 12],
      ['repeat', 'Nhập lại mật khẩu mới', 'new-password', 12]
    ]) {
      const l = el('label', label);
      const { wrap, input } = makePasswordInputWithToggle('Nhập ' + label.toLowerCase() + '...', auto, minL);
      l.append(wrap);
      form.append(l);
      inputs[key] = input;
    }
    const submit = el('button', 'Lưu mật khẩu mới', 'primary');
    submit.type = 'submit';
    form.append(submit);
    form.onsubmit = async e => {
      e.preventDefault();
      if (inputs.password.value !== inputs.repeat.value) { toast('Mật khẩu nhập lại không khớp.'); return; }
      submit.disabled = true;
      try {
        await api('password', { current: inputs.current.value, password: inputs.password.value });
        signedOut();
        toast('Đã đổi mật khẩu thành công. Vui lòng đăng nhập lại.');
      } catch (e) { toast(e.message); } finally { submit.disabled = false; }
    };
    root.append(form);
    return;
  }

  if (page === 'overview') {
    const isFin = state.user.team === 'finance', isOps = state.user.team === 'operations', isAdmin = state.user.role === 'admin', isSup = state.user.team === 'support';
    const [d, queue, activity, finData, repData, opsData] = await Promise.all([
      api('overview'),
      api('tickets'),
      api('activity'),
      (isAdmin || isFin) ? api('finance').catch(() => null) : Promise.resolve(null),
      (isAdmin || isSup) ? api('reputation/overview').catch(() => null) : Promise.resolve(null),
      (isAdmin || isOps) ? api('operations').catch(() => null) : Promise.resolve(null)
    ]);
    if (rev !== state.revision) return;
    root.replaceChildren();

    const welcome = el('div', undefined, 'welcome-banner');
    const copy = el('div');
    const bannerHeading = isAdmin
      ? 'Trung tâm Điều hành Cấp cao (Executive Command Center)'
      : isFin
        ? 'Trung tâm Tài chính & Đối soát Sổ cái (Treasury & Ledger)'
        : isOps
          ? 'Trung tâm Kỹ thuật & Vận hành Hạ tầng (SRE & DevOps)'
          : 'Trung tâm Chăm sóc Cộng đồng & Kiểm duyệt (Trust & Safety)';
    const bannerDesc = isAdmin
      ? 'Giám sát liên thông 4 bộ phận, phê duyệt đối soát xu, điều phối phiếu khẩn cấp và kiểm soát toàn diện hệ sinh thái Kinnect.'
      : isFin
        ? 'Tra cứu sổ cái xu/VND, kiểm tra yêu cầu từ Hỗ trợ và lập đề nghị bù xu mua trình Admin phê duyệt ghi sổ.'
        : isOps
          ? 'Giám sát tài nguyên máy chủ, cổng Cloudflare Tunnel, hàng chờ AI và xử lý phiếu kỹ thuật từ các bộ phận.'
          : 'Tiếp nhận phản ánh của thành viên, kiểm duyệt bài đăng/ảnh/video, bảo vệ điểm uy tín (100đ) và phối hợp liên bộ phận.';

    copy.append(
      el('p', new Date().toLocaleDateString('vi-VN', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }), 'eyebrow'),
      el('h2', bannerHeading),
      el('p', bannerDesc)
    );
    const bannerBtns = el('div', undefined, 'actions');
    bannerBtns.append(
      button(isFin ? '+ Lập đề nghị bù xu' : '+ Tạo phiếu phối hợp', () => isFin ? load('wallet') : newTicket(root), 'primary')
    );
    if (isAdmin && d.pendingWalletOps > 0) {
      bannerBtns.append(button(`🪙 Duyệt ví chờ (${d.pendingWalletOps})`, () => load('wallet'), 'warn-btn'));
    }
    welcome.append(copy, bannerBtns);
    root.append(welcome);

    if (isFin && finData) {
      metricCards(root, [
        ['Bút toán ghi sổ', Number(finData.totals.entries).toLocaleString('vi-VN')],
        ['Giá trị ghi sổ (VND)', Number(finData.totals.net_vnd).toLocaleString('vi-VN')],
        ['Đề nghị chờ Admin duyệt', finData.pendingWalletOps ?? d.pendingWalletOps ?? 0],
        ['Phiếu tài chính đang mở', (queue.summary.open || 0) + (queue.summary.in_progress || 0)]
      ]);
    } else if (isOps && opsData) {
      metricCards(root, [
        ['Uptime máy chủ', Math.floor((opsData.uptime || 0) / 60) + ' phút'],
        ['Bộ nhớ RAM', (opsData.memoryMb || 0) + ' MB'],
        ['Hàng chờ AI', opsData.ai?.queue || 0],
        ['Phiếu kỹ thuật mở', (queue.summary.open || 0) + (queue.summary.in_progress || 0)]
      ]);
    } else if (isAdmin) {
      metricCards(root, [
        ['Tổng thành viên', Number(d.users || 0).toLocaleString('vi-VN')],
        ['Phiếu phối hợp đang mở', (queue.summary.open || 0) + (queue.summary.in_progress || 0) + (queue.summary.waiting || 0)],
        ['Báo cáo & Khôi phục chờ', Number(d.reports || 0) + Number(d.resets || 0)],
        ['Đề nghị ví chờ duyệt', Number(d.pendingWalletOps || 0)]
      ]);
    } else {
      metricCards(root, [
        ['Báo cáo cần xử lý', d.reports || 0],
        ['Yêu cầu khôi phục MK', d.resets || 0],
        ['Phiếu mới tiếp nhận', queue.summary.open || 0],
        ['Phiếu đang xử lý', queue.summary.in_progress || 0]
      ]);
    }

    // Ma trận Phối hợp Liên Bộ phận (Enterprise Cross-Department Matrix)
    const dq = d.departmentQueues || {};
    const matrixCard = el('section', undefined, 'card');
    const matrixHead = el('div', undefined, 'section-bar');
    matrixHead.append(
      el('h3', '🏢 Ma trận Vận hành & Phối hợp Liên Bộ phận (4 Phân hệ)'),
      button('Mở trung tâm phiếu →', () => load('tickets'), 'link-button')
    );
    matrixCard.append(matrixHead);
    const matrixGrid = el('div', undefined, 'dept-matrix-grid');
    const deptItems = [
      {
        key: 'admin',
        icon: '🛡️',
        title: 'Ban Quản trị (Admin)',
        domain: 'admin.kinnect.io.vn',
        stats: `${dq.admin?.open || 0} phiếu chờ · ${d.pendingWalletOps || 0} duyệt ví`,
        desc: 'Phê duyệt bù xu/tặng xu, phân công nhân sự, quyết định khiếu nại cấp cao.',
        actionLabel: isAdmin ? 'Xử lý phiếu Admin' : 'Trình phiếu lên Admin',
        onClick: () => isAdmin ? load('tickets') : newTicket(root, 'admin')
      },
      {
        key: 'support',
        icon: '🎧',
        title: 'Hỗ trợ & Kiểm duyệt',
        domain: 'hotro.kinnect.io.vn',
        stats: `${dq.support?.open || 0} phiếu · ${d.reports || 0} báo cáo · ${d.resets || 0} cấp MK`,
        desc: 'Tuyến đầu tiếp nhận khách hàng, kiểm duyệt nội dung/ảnh và bảo vệ điểm uy tín 100đ.',
        actionLabel: (isAdmin || isSup) ? 'Mở Báo cáo & Hỗ trợ' : 'Chuyển phiếu sang Hỗ trợ',
        onClick: () => (isAdmin || isSup) ? load('reports') : newTicket(root, 'support')
      },
      {
        key: 'finance',
        icon: '💳',
        title: 'Tài chính & Đối soát',
        domain: 'taichinh.kinnect.io.vn',
        stats: `${dq.finance?.open || 0} phiếu · ${finData ? Number(finData.totals.entries).toLocaleString('vi-VN') + ' bút toán' : 'Sổ cái xu'}`,
        desc: 'Đối soát giao dịch nạp xu, kiểm tra biến động ví và lập đề nghị bù xu mua.',
        actionLabel: (isAdmin || isFin) ? 'Mở Đối soát & Ví' : 'Yêu cầu Tài chính đối soát',
        onClick: () => (isAdmin || isFin) ? load('finance') : newTicket(root, 'finance')
      },
      {
        key: 'operations',
        icon: '⚙️',
        title: 'Kỹ thuật & Hệ thống',
        domain: 'kythuat.kinnect.io.vn',
        stats: `${dq.operations?.open || 0} phiếu · ${opsData ? opsData.memoryMb + ' MB RAM' : 'SRE & AI'}`,
        desc: 'Giám sát máy chủ, cơ sở dữ liệu, Cloudflare Tunnel và hàng chờ AI.',
        actionLabel: (isAdmin || isOps) ? 'Mở Trung tâm Kỹ thuật' : 'Báo sự cố cho Kỹ thuật',
        onClick: () => (isAdmin || isOps) ? load('operations') : newTicket(root, 'operations')
      }
    ];
    for (const item of deptItems) {
      const box = el('div', undefined, 'dept-matrix-card dept-' + item.key);
      const topRow = el('div', undefined, 'dept-matrix-top');
      topRow.append(el('span', item.icon + ' ' + item.title, 'dept-matrix-title'), badge(item.domain));
      box.append(
        topRow,
        el('b', item.stats, 'dept-matrix-stat'),
        el('p', item.desc, 'muted'),
        button(item.actionLabel + ' →', item.onClick, 'dept-matrix-btn')
      );
      matrixGrid.append(box);
    }
    matrixCard.append(matrixGrid);
    root.append(matrixCard);

    const grid = el('div', undefined, 'dashboard-grid'), cases = el('section', undefined, 'card'), heading = el('div', undefined, 'section-bar');
    heading.append(el('h3', '📋 Hàng chờ Phiếu Phối hợp Cần Xử lý'), button('Xem tất cả (' + queue.summary.total + ') →', () => load('tickets'), 'link-button'));
    cases.append(heading);
    table(cases, ['Yêu cầu', 'Khách hàng', 'Bộ phận', 'Trạng thái', 'Thao tác'], queue.tickets.slice(0, 6).map(t => [
      button(t.subject, () => openTicket(t.id), 'link-button'),
      t.member ? button('@' + t.member.replace(/^@/, ''), () => openMember360Modal(t.member), 'link-button') : '—',
      teamNames[t.team] || t.team,
      badge(statusNames[t.status], t.status === 'resolved' ? 'good' : t.status === 'in_progress' ? 'info' : 'warn'),
      button('Xử lý ngay →', () => openTicket(t.id), 'primary')
    ]));

    const recent = el('section', undefined, 'card');
    recent.append(el('h3', '⚡ Nhật ký Phối hợp Thời gian thực'));
    if (!activity.entries.length) recent.append(el('p', 'Chưa có hoạt động mới.', 'muted'));
    for (const item of activity.entries.slice(0, 6)) {
      const entry = el('div', undefined, 'activity-item');
      entry.append(
        el('b', '@' + item.actor),
        el('span', (actionNames[item.action] || item.action) + (item.target ? ' · ' + item.target : '')),
        el('small', date(item.created))
      );
      recent.append(entry);
    }
    grid.append(cases, recent);
    root.append(grid);

    const shortcuts = el('div', undefined, 'quick-actions');
    shortcuts.append(button('📋 Mở hàng chờ phối hợp', () => load('tickets'), 'primary'));
    if (isAdmin) {
      shortcuts.append(
        button('⭐ Điểm uy tín & Vi phạm', () => load('reputation')),
        button('🪙 Tặng xu & Bù giao dịch', () => load('wallet')),
        button('👥 Hồ sơ thành viên 360°', () => load('users')),
        button('🛡️ Quản lý nhân sự', () => load('team')),
        button('⚑ Xem báo cáo vi phạm', () => load('reports'))
      );
    } else if (isFin) {
      shortcuts.append(
        button('🪙 Lập đề nghị bù xu', () => load('wallet')),
        button('📊 Tra cứu và đối soát sổ cái', () => load('finance'))
      );
    } else if (isOps) {
      shortcuts.append(button('💻 Điều khiển Hệ thống & AI', () => load('operations')));
    } else {
      shortcuts.append(
        button('⭐ Điểm uy tín & Vi phạm', () => load('reputation')),
        button('⚑ Xử lý báo cáo nội dung', () => load('reports')),
        button('↺ Cấp mật khẩu khôi phục', () => load('resets')),
        button('👥 Tra cứu thành viên 360°', () => load('users'))
      );
    }
    root.append(shortcuts);
    return;
  }

  if (page === 'users') {
    root.replaceChildren();
    const form = el('form', undefined, 'toolbar');
    const label = el('label', 'Tìm thành viên'), search = el('input');
    search.placeholder = 'Tên đăng nhập (@username) hoặc tên hiển thị...';
    label.append(search);

    const sl = el('label', 'Trạng thái'), select = el('select');
    for (const [k, v] of [['all', 'Tất cả'], ['active', 'Hoạt động'], ['suspended', 'Đình chỉ'], ['admin', 'Admin']]) {
      const o = el('option', v); o.value = k; select.append(o);
    }
    sl.append(select);

    const scoreLabel = el('label', 'Hạng uy tín'), scoreSelect = el('select');
    for (const [k, v] of [['all', 'Tất cả điểm số'], ['excellent', 'Chuẩn mực (≥90đ)'], ['good', 'Khá (70–89đ)'], ['warning', 'Cảnh báo (50–69đ)'], ['restricted', 'Nguy hiểm (<50đ)']]) {
      const o = el('option', v); o.value = k; scoreSelect.append(o);
    }
    scoreLabel.append(scoreSelect);

    const submit = el('button', 'Tìm kiếm', 'primary');
    submit.type = 'submit';
    form.append(label, sl, scoreLabel, submit);
    const results = el('div');
    root.append(form, results);

    let query = 0;
    const draw = async () => {
      const q = ++query;
      results.replaceChildren(el('p', 'Đang tải danh sách thành viên…', 'muted'));
      try {
        const d = await api('users?q=' + encodeURIComponent(search.value) + '&state=' + select.value + '&score=' + scoreSelect.value);
        if (q !== query || rev !== state.revision) return;
        results.replaceChildren(el('p', `Hiển thị ${d.users.length} / ${d.total} thành viên (mặc định 100/100 điểm uy tín khi chưa vi phạm)`, 'count'));
        table(results, ['Thành viên', 'Điểm uy tín', 'Vai trò', 'Trạng thái', 'Ngày tạo', 'Thao tác phối hợp'], d.users.map(u => {
          const name = el('div');
          const nameBtn = button(u.name || u.username, () => openMember360Modal(u.username), 'link-button');
          name.append(nameBtn, el('small', '@' + u.username));
          const score = Number.isInteger(u.reputation_score) ? u.reputation_score : 100;
          const scoreBadge = badge(score + '/100 điểm', score >= 90 ? 'good' : score >= 70 ? 'info' : score >= 50 ? 'warn' : 'danger');
          scoreBadge.style.cursor = 'pointer';
          scoreBadge.title = 'Bấm để xem & điều chỉnh hồ sơ uy tín';
          scoreBadge.onclick = () => showUserReputation(u.id);

          const actWrap = el('div', undefined, 'actions');
          actWrap.append(
            button('🔍 Hồ sơ 360°', () => openMember360Modal(u.username)),
            button('📋 Tạo phiếu', () => {
              load('tickets').then(() => {
                setTimeout(() => newTicket($('content'), state.user.team, { member: '@' + u.username, subject: 'Hỗ trợ thành viên @' + u.username }), 80);
              });
            })
          );
          if (state.user.role === 'admin' || state.user.team === 'finance') {
            actWrap.append(button('🪙 Cấp/Bù xu', () => {
              window.__WALLET_PREFILL = { kind: state.user.role === 'admin' ? 'gift' : 'paid_correction', username: u.username, title: 'Hỗ trợ xu cho @' + u.username };
              load('wallet');
            }));
          }
          if (u.role === 'user') {
            actWrap.append(button(u.suspended ? '🟢 Khôi phục' : '🚫 Đình chỉ', () => mutate('moderate', { action: u.suspended ? 'restore-user' : 'suspend-user', target: u.id }, u.suspended ? 'Khôi phục thành viên?' : 'Đình chỉ thành viên?', '@' + u.username), u.suspended ? '' : 'danger'));
          }
          return [
            name,
            scoreBadge,
            u.role === 'admin' ? badge('Admin', 'info') : 'Thành viên',
            badge(u.suspended ? 'Đình chỉ' : 'Hoạt động', u.suspended ? 'warn' : 'good'),
            date(u.created),
            actWrap
          ];
        }));
      } catch (e) { results.replaceChildren(el('p', e.message, 'error')); }
    };
    form.onsubmit = e => { e.preventDefault(); draw(); };
    select.onchange = draw;
    scoreSelect.onchange = draw;
    await draw();
    return;
  }

  if (page === 'reports') {
    const d = await api('reports');
    if (rev !== state.revision) return;
    root.replaceChildren();
    if (!d.reports.length) { empty(root, 'Chưa có báo cáo vi phạm nào.'); return; }
    for (const r of d.reports) {
      const card = el('article', undefined, 'card'), head = el('div', undefined, 'report-head');
      const authorLabel = r.subject?.username ? ` · Tác giả: @${r.subject.username}` : '';
      head.append(
        el('h3', `⚑ Báo cáo ${r.target_type.toUpperCase()}${authorLabel} · ${date(r.created)}`),
        badge(r.status === 'open' ? 'Đang mở xử lý' : 'Đã đóng', r.status === 'open' ? 'warn' : 'good')
      );
      card.append(head, el('p', 'Lý do báo cáo: ' + (r.reason || 'Không có mô tả')));
      if (r.subject) {
        card.append(el('p', r.subject.body || r.subject.username || '(Nội dung đính kèm bên dưới)', 'report-text'));
        if (r.subject.has_media && r.subject.media_url) {
          const mediaBox = el('div', undefined, 'post-media-box');
          mediaBox.style.maxWidth = '420px';
          mediaBox.style.marginBottom = '12px';
          if (r.subject.media_type?.startsWith('video/')) {
            const vid = el('video', undefined, 'post-video-thumb');
            vid.src = r.subject.media_url;
            vid.controls = true;
            mediaBox.append(vid);
          } else {
            const img = el('img', undefined, 'post-media-thumb');
            img.src = r.subject.media_url;
            img.alt = 'Ảnh bài đăng bị báo cáo';
            img.onclick = () => openPostDetailModal(r.subject);
            mediaBox.append(img);
          }
          card.append(mediaBox);
        }
      }
      const actions = el('div', undefined, 'actions');
      if (r.subject && ['post', 'short'].includes(r.target_type)) {
        actions.append(
          button(r.subject.hidden ? '👁️ Hiện lại nội dung' : '🚫 Ẩn nội dung vi phạm', () => mutate('moderate', { action: (r.subject.hidden ? 'show-' : 'hide-') + r.target_type, target: r.target_id }, 'Thay đổi hiển thị nội dung?', 'Thao tác được ghi vào nhật ký.'))
        );
      }
      if (r.subject?.username) {
        actions.append(
          button('🔍 Hồ sơ 360° @' + r.subject.username, () => openMember360Modal(r.subject.username)),
          button('⭐ Điểm uy tín', () => showUserReputation(r.subject.userId || r.subject.username))
        );
      }
      actions.append(
        button('💳 Chuyển Tài chính', () => newTicket(root, 'finance', {
          member: r.subject?.username ? '@' + r.subject.username : '',
          subject: 'Đối soát giao dịch từ báo cáo #' + r.id.slice(0, 6),
          description: `Báo cáo (${r.target_type}): ${r.reason || ''}\nNội dung: ${r.subject?.body || ''}`
        })),
        button('💻 Báo Kỹ thuật', () => newTicket(root, 'operations', {
          member: r.subject?.username ? '@' + r.subject.username : '',
          subject: 'Kiểm tra kỹ thuật từ báo cáo #' + r.id.slice(0, 6),
          description: `Báo cáo (${r.target_type}): ${r.reason || ''}`
        }))
      );
      if (r.status === 'open') {
        actions.append(button('✔ Đóng báo cáo', () => mutate('moderate', { action: 'close-report', target: r.id }, 'Đóng báo cáo?', 'Đánh dấu báo cáo này đã được xử lý.'), 'primary'));
      }
      card.append(actions);
      root.append(card);
    }
    return;
  }

  if (page === 'resets') {
    const d = await api('resets');
    if (rev !== state.revision) return;
    root.replaceChildren();
    if (!d.requests.length) { empty(root, 'Không có yêu cầu khôi phục mật khẩu nào.'); return; }
    for (const r of d.requests) {
      const card = el('article', undefined, 'card');
      const head = el('div', undefined, 'report-head');
      head.append(el('h3', '@' + r.username), badge(r.status === 'open' ? 'Chờ xử lý' : r.status, r.status === 'open' ? 'warn' : 'good'));
      card.append(head, el('p', 'Liên hệ xác minh: ' + r.contact), el('p', r.note || 'Không có ghi chú', 'report-text'), el('small', date(r.created)));
      const actions = el('div', undefined, 'actions');
      actions.append(button('🔍 Xem Hồ sơ 360°', () => openMember360Modal(r.username)));
      if (r.status === 'open') {
        if (r.user_id && r.role === 'user') {
          actions.append(button('🔑 Cấp mật khẩu tạm (1 lần)', () => mutate('resets', { id: r.id, action: 'reset' }, 'Đã xác minh chủ tài khoản?', 'Mật khẩu cũ bị thay thế và các phiên đăng nhập cũ bị thu hồi. Chỉ gửi mật khẩu mới riêng cho đúng chủ tài khoản.'), 'primary'));
        }
        actions.append(button('Bỏ qua yêu cầu', () => mutate('resets', { id: r.id, action: 'dismiss' }, 'Bỏ qua yêu cầu?', 'Yêu cầu sẽ được đánh dấu đã bỏ qua.')));
      }
      card.append(actions);
      root.append(card);
    }
    return;
  }

  if (page === 'team') {
    const d = await api('team');
    if (rev !== state.revision) return;
    root.replaceChildren();
    const card = el('div', undefined, 'card');
    card.append(
      el('h3', '🛡️ Thêm nhân sự phụ trách bộ phận'),
      el('p', 'Tài khoản nhân sự sẽ được cấp mật khẩu tạm dùng 1 lần và tự động phân quyền theo đúng cổng bộ phận (Hỗ trợ · Kỹ thuật · Tài chính).', 'muted')
    );
    const form = el('form', undefined, 'staff-form'), un = el('input'), name = el('input');
    form.noValidate = true;
    un.required = name.required = true;
    un.maxLength = 30;
    un.autocomplete = 'off';
    un.autocapitalize = 'none';
    un.spellcheck = false;
    un.placeholder = 'Ví dụ: tuan_cskh hoặc Tuan_CSKH';
    un.title = 'Tên đăng nhập từ 3–30 ký tự (hỗ trợ nhập chữ HOA/thường, hệ thống tự chuẩn hóa)';
    name.maxLength = 80;
    name.placeholder = 'Nguyễn Văn Tuấn';
    for (const [text, input] of [['Tên đăng nhập', un], ['Tên hiển thị', name]]) {
      const l = el('label', text); l.append(input); form.append(l);
    }
    const teamLabel = el('label', 'Bộ phận công tác'), teamSelect = selectOptions([['support', 'Hỗ trợ & Kiểm duyệt'], ['operations', 'Bộ phận Kỹ thuật'], ['finance', 'Bộ phận Tài chính']]);
    teamLabel.append(teamSelect); form.append(teamLabel);
    const create = el('button', '+ Tạo tài khoản nhân sự', 'primary');
    create.type = 'submit';
    form.append(create);
    form.onsubmit = async e => {
      e.preventDefault();
      const cleanUser = un.value.trim().replace(/^@/, '').toLowerCase().replace(/[^a-z0-9_]/g, '');
      if (cleanUser.length < 3) {
        toast('Tên đăng nhập cần tối thiểu 3 ký tự (chữ cái, số hoặc gạch dưới)');
        un.focus();
        return;
      }
      if (!name.value.trim()) {
        toast('Vui lòng nhập tên hiển thị nhân sự');
        name.focus();
        return;
      }
      await mutate('team', { action: 'create', username: cleanUser, name: name.value.trim(), team: teamSelect.value }, 'Tạo tài khoản nhân sự?', `Tạo tài khoản @${cleanUser} thuộc ${teamNames[teamSelect.value]}.`).catch(e => toast(e.message));
    };
    card.append(form);
    root.append(card);
    table(root, ['Nhân viên', 'Bộ phận', 'Trạng thái', 'Mật khẩu', 'Thao tác'], d.staff.map(s => {
      const who = el('div', s.name); who.append(el('small', '@' + s.username));
      const actions = el('div', undefined, 'actions');
      actions.append(
        button(s.suspended ? '🟢 Mở khóa' : '🚫 Khóa', () => mutate('team', { action: s.suspended ? 'restore' : 'suspend', id: s.id }, s.suspended ? 'Mở khóa nhân viên?' : 'Khóa nhân viên?', s.suspended ? 'Cho phép đăng nhập lại.' : 'Thu hồi ngay mọi phiên quản trị của nhân viên này.')),
        button('🔑 Đặt lại mật khẩu', () => mutate('team', { action: 'reset', id: s.id }, 'Đặt lại mật khẩu nhân sự?', 'Thu hồi mọi phiên hiện có và cấp mật khẩu tạm mới.'))
      );
      const group = selectOptions([['support', 'Hỗ trợ & Kiểm duyệt'], ['operations', 'Bộ phận Kỹ thuật'], ['finance', 'Bộ phận Tài chính']], s.team || 'support');
      group.setAttribute('aria-label', 'Nhóm của ' + s.username);
      group.onchange = () => mutate('team', { action: 'move', id: s.id, team: group.value }, 'Chuyển bộ phận nhân sự?', 'Mọi phiên hiện tại sẽ được thu hồi để áp dụng quyền mới.').catch(e => toast(e.message)).finally(() => { group.value = s.team || 'support'; });
      return [who, group, badge(s.suspended ? 'Đã khóa' : 'Hoạt động', s.suspended ? 'warn' : 'good'), s.must_change ? badge('Cần đổi MK tạm', 'warn') : badge('Đã kích hoạt', 'good'), actions];
    }));
    return;
  }

  if (page === 'activity') {
    const d = await api('activity');
    if (rev !== state.revision) return;
    root.replaceChildren();
    table(root, ['Thời gian', 'Người thao tác', 'Hành động', 'Đối tượng'], d.entries.map(e => [date(e.created), '@' + e.actor, actionNames[e.action] || e.action, e.target || '—']));
  }
}

// ----------------------------------------------------
// HỒ SƠ KHÁCH HÀNG 360° (CUSTOMER 360° DOSSIER MODAL)
// ----------------------------------------------------
async function openMember360Modal(query) {
  const clean = String(query || '').trim().replace(/^@/, '');
  if (!clean) return;
  let modal = $('member-360-modal');
  if (!modal) {
    modal = el('dialog', undefined, 'post-modal-dialog member-360-dialog');
    modal.id = 'member-360-modal';
    document.body.append(modal);
  }
  modal.replaceChildren(el('p', 'Đang tải Hồ sơ 360° của @' + clean + '…', 'muted'));
  if (!modal.open) modal.showModal();

  try {
    const d = await api('member-360/' + encodeURIComponent(clean));
    const u = d.user;
    const rep = d.dossier?.reputation || { score: 100, tierLabel: 'Chuẩn mực (100/100)', canGoLive: true, canPost: true, canComment: true };
    modal.replaceChildren();

    const topBar = el('div', undefined, 'rep-dossier-header');
    const titleBox = el('div');
    titleBox.append(
      el('p', 'HỒ SƠ THÀNH VIÊN 360° (CROSS-DEPARTMENT DOSSIER)', 'eyebrow'),
      el('h3', `${u.name || u.username} (@${u.username})`),
      el('small', `ID: ${u.id} · Tham gia: ${date(u.created)} · Vai trò: ${u.role === 'admin' ? 'Admin' : 'Thành viên'}`)
    );
    const rightBadges = el('div', undefined, 'score-gauge');
    rightBadges.append(
      el('b', rep.score),
      el('span', '/ 100 uy tín'),
      el('div', undefined, 'post-badges')
    );
    rightBadges.lastChild.style.marginTop = '6px';
    rightBadges.lastChild.append(
      badge(u.suspended ? 'Đang đình chỉ' : 'Hoạt động', u.suspended ? 'danger' : 'good'),
      badge(rep.tierLabel || 'Chuẩn mực', rep.score >= 90 ? 'good' : rep.score >= 70 ? 'info' : 'warn')
    );
    topBar.append(titleBox, rightBadges);
    modal.append(topBar);

    // Thanh thao tác nhanh liên bộ phận
    const quickBar = el('div', undefined, 'actions rep-actions');
    quickBar.append(
      button('⭐ Cộng / Khôi phục điểm', async () => {
        await openAdjustDialog(u.id, u.username, 'restore');
        openMember360Modal(u.username);
      }, 'primary'),
      button('⭐ Trừ điểm vi phạm', async () => {
        await openAdjustDialog(u.id, u.username, 'deduct');
        openMember360Modal(u.username);
      }, 'danger')
    );
    if (state.user.role === 'admin' || state.user.team === 'finance') {
      quickBar.append(button('🪙 Tặng / Bù xu', () => {
        modal.close();
        window.__WALLET_PREFILL = { kind: state.user.role === 'admin' ? 'gift' : 'paid_correction', username: u.username, title: 'Điều chỉnh xu cho @' + u.username };
        load('wallet');
      }));
    }
    quickBar.append(
      button('📋 Tạo phiếu phối hợp', () => {
        modal.close();
        load('tickets').then(() => {
          setTimeout(() => newTicket($('content'), state.user.team, { member: '@' + u.username, subject: 'Hỗ trợ khách hàng @' + u.username }), 80);
        });
      })
    );
    if (u.role === 'user') {
      quickBar.append(
        button(u.suspended ? '🟢 Mở khóa tài khoản' : '🚫 Đình chỉ tài khoản', async () => {
          if (!await confirmAction(u.suspended ? 'Khôi phục tài khoản?' : 'Đình chỉ tài khoản?', '@' + u.username)) return;
          await api('moderate', { action: u.suspended ? 'restore-user' : 'suspend-user', target: u.id });
          toast('Đã cập nhật trạng thái tài khoản @' + u.username);
          openMember360Modal(u.username);
        }, u.suspended ? '' : 'danger')
      );
    }
    modal.append(quickBar);

    // Tóm tắt 4 chỉ số của thành viên
    const statsGrid = el('div', undefined, 'metrics member-360-metrics');
    statsGrid.append(
       (() => { const c = el('div', undefined, 'metric'); c.append(el('span', 'Điểm uy tín'), el('b', rep.score + '/100')); return c; })(),
       (() => { const c = el('div', undefined, 'metric'); c.append(el('span', 'Bài đăng gần đây'), el('b', (d.posts?.length || 0) + ' bài')); return c; })(),
       (() => { const c = el('div', undefined, 'metric'); c.append(el('span', 'Phiếu hỗ trợ'), el('b', (d.tickets?.length || 0) + ' phiếu')); return c; })(),
       (() => { const c = el('div', undefined, 'metric'); c.append(el('span', 'Giao dịch xu ghi sổ'), el('b', d.wallet ? Number(d.wallet.totalCoins || 0).toLocaleString('vi-VN') + ' xu' : 'Theo phân quyền')); return c; })()
    );
    modal.append(statsGrid);

    if (d.tickets?.length) {
      const tSec = el('div', undefined, 'rep-sub-section');
      tSec.append(el('h4', '📋 Phiếu Phối hợp Liên quan (' + d.tickets.length + ')'));
      table(tSec, ['Tiêu đề phiếu', 'Bộ phận', 'Trạng thái', 'Cập nhật', 'Mở'], d.tickets.slice(0, 5).map(t => [
        t.subject,
        teamNames[t.team] || t.team,
        badge(statusNames[t.status] || t.status, t.status === 'resolved' ? 'good' : 'warn'),
        date(t.updated),
        button('Mở phiếu →', () => { modal.close(); openTicket(t.id); }, 'link-button')
      ]));
      modal.append(tSec);
    }

    if (d.wallet?.entries?.length) {
      const wSec = el('div', undefined, 'rep-sub-section');
      wSec.append(el('h4', '💳 Sổ cái Giao dịch Xu Gần đây (' + d.wallet.entries.length + ')'));
      table(wSec, ['Thời gian', 'Loại', 'Số xu', 'Giá trị VND', 'Mã tham chiếu'], d.wallet.entries.slice(0, 5).map(e => [
        date(e.created),
        e.kind,
        Number(e.coins).toLocaleString('vi-VN') + ' xu',
        Number(e.net_vnd).toLocaleString('vi-VN') + ' đ',
        e.reference || '—'
      ]));
      modal.append(wSec);
    }

    if (d.posts?.length) {
      const pSec = el('div', undefined, 'rep-sub-section');
      pSec.append(el('h4', '📝 Bài đăng Gần đây (' + d.posts.length + ')'));
      table(pSec, ['Thời gian', 'Nội dung', 'Đính kèm', 'Trạng thái', 'Thao tác'], d.posts.slice(0, 5).map(p => [
        date(p.created),
        (p.body || '').slice(0, 80) || '(Chỉ có ảnh/video)',
        p.has_media ? badge(p.media_type?.startsWith('video/') ? '🎬 Video' : '🖼️ Ảnh', 'good') : '—',
        badge(p.hidden ? 'Đã ẩn' : 'Đang hiện', p.hidden ? 'warn' : 'good'),
        button('Xem bài', () => { modal.close(); openPostDetailModal({ ...p, username: u.username, name: u.name, user_id: u.id }); })
      ]));
      modal.append(pSec);
    }

    const footer = el('div', undefined, 'dialog-actions');
    const closeBtn = el('button', 'Đóng hồ sơ', 'primary');
    closeBtn.type = 'button';
    closeBtn.onclick = () => modal.close();
    footer.append(closeBtn);
    modal.append(footer);
  } catch (err) {
    modal.replaceChildren(
      el('h3', 'Không tìm thấy hồ sơ'),
      el('p', err.message, 'error'),
      button('Đóng', () => modal.close(), 'primary')
    );
  }
}

// ----------------------------------------------------
// MÀN HÌNH CHUYÊN BIỆT: ĐIỂM UY TÍN & BIỂU PHÍ MỚI
// ----------------------------------------------------
async function renderReputationPage(root, rev) {
  root.replaceChildren();
  const [overview, violationsData] = await Promise.all([
    api('reputation/overview'),
    api('reputation/violations')
  ]);
  if (rev !== state.revision) return;

  const banner = el('div', undefined, 'welcome-banner rep-banner');
  const bannerCopy = el('div');
  bannerCopy.append(
    el('p', 'KINNECT TRUST & SAFETY · CHÍNH SÁCH MỚI', 'eyebrow'),
    el('h2', 'Hệ Thống Điểm Uy Tín Thành Viên (Trừ Rất Ít Điểm)'),
    el('p', 'Mỗi thành viên có 100 điểm uy tín ban đầu. Cơ chế trừ rất nhẹ nhằm mục đích giáo dục & nhắc nhở thân thiện, bảo vệ tối đa thành viên tử tế.')
  );
  banner.append(bannerCopy);
  root.append(banner);

  metricCards(root, [
    ['🟢 Chuẩn mực (90–100đ)', overview.tiers.excellent + ' tài khoản'],
    ['🟡 Khá (70–89đ)', overview.tiers.good + ' tài khoản'],
    ['🟠 Cảnh báo (50–69đ)', overview.tiers.warning + ' (chặn Live)'],
    ['🔴 Tạm khóa (<50đ)', overview.tiers.restricted + ' (hạn chế)']
  ]);

  const policyCard = el('section', undefined, 'card policy-card');
  const policyHead = el('div', undefined, 'section-bar');
  policyHead.append(el('h3', 'Biểu Phí Trừ Điểm Mới (Trừ Rất Ít Điểm – Giáo Dục & Nhắc Nhở)'));
  policyCard.append(policyHead);

  const policyTableWrap = el('div', undefined, 'table-wrap');
  const pt = el('table'), pthead = el('thead'), pttr = el('tr');
  ['Trường hợp vi phạm', 'Mức trừ CŨ', 'Mức trừ MỚI', 'Biện pháp xử lý của AI'].forEach(h => pttr.append(el('th', h)));
  pthead.append(pttr); pt.append(pthead);

  const ptbody = el('tbody');
  for (const item of overview.policy) {
    const row = el('tr');
    if (item.new.includes('0 điểm')) row.className = 'policy-row-safe';
    else if (['-2 điểm', '-3 điểm', '-5 điểm'].includes(item.new)) row.className = 'policy-row-mild';
    else row.className = 'policy-row-severe';

    const caseCell = el('td', item.case); caseCell.style.fontWeight = '600';
    const oldCell = el('td', item.old); oldCell.style.textDecoration = 'line-through'; oldCell.style.color = '#a094ab';
    const newCell = el('td', item.new); newCell.style.fontWeight = '700';
    const actionCell = el('td', item.action);

    row.append(caseCell, oldCell, newCell, actionCell);
    ptbody.append(row);
  }
  pt.append(ptbody); policyTableWrap.append(pt); policyCard.append(policyTableWrap);
  root.append(policyCard);

  const lookupCard = el('section', undefined, 'card');
  lookupCard.append(el('h3', 'Tra cứu & Quản lý Điểm Từng Thành Viên'));
  const lookupToolbar = el('form', undefined, 'toolbar');
  const lookupInput = el('input');
  lookupInput.placeholder = 'Nhập tên đăng nhập (@username) hoặc ID thành viên...';
  lookupInput.required = true;
  field(lookupToolbar, 'Tìm thành viên', lookupInput);
  const lookupBtn = el('button', 'Tra cứu hồ sơ', 'primary');
  lookupBtn.type = 'submit';
  lookupToolbar.append(lookupBtn);
  lookupCard.append(lookupToolbar);

  const dossierContainer = el('div', undefined, 'rep-dossier-area');
  lookupCard.append(dossierContainer);
  root.append(lookupCard);

  lookupToolbar.onsubmit = async e => {
    e.preventDefault();
    const query = lookupInput.value.trim().replace(/^@/, '');
    if (!query) return;
    dossierContainer.replaceChildren(el('p', 'Đang tải hồ sơ uy tín…', 'muted'));
    try {
      let dossier;
      try {
        dossier = await api('reputation/user/' + encodeURIComponent(query));
      } catch {
        const uRes = await api('users?q=' + encodeURIComponent(query));
        const targetUser = uRes.users?.find(u => u.username.toLowerCase() === query.toLowerCase() || u.id === query) || uRes.users?.[0];
        if (!targetUser) throw new Error('Không tìm thấy thành viên: ' + query);
        dossier = await api('reputation/user/' + targetUser.id);
      }
      renderDossierView(dossierContainer, dossier);
    } catch (err) {
      dossierContainer.replaceChildren(el('p', err.message, 'error'));
    }
  };

  const violationsCard = el('section', undefined, 'card');
  const vHead = el('div', undefined, 'section-bar');
  vHead.append(el('h3', 'Lịch Sử Vi Phạm AI Gần Nhất (' + overview.violationsCount + ' lượt ghi nhận)'));
  violationsCard.append(vHead);

  if (!violationsData.violations.length) {
    empty(violationsCard, 'Chưa có vi phạm nào được ghi nhận gần đây.');
  } else {
    table(violationsCard, ['Thời gian', 'Thành viên', 'Loại vi phạm', 'Điểm trừ', 'Bằng chứng / Lý do AI', 'Thao tác'], violationsData.violations.map(v => {
      const who = el('div', v.name || v.username); who.append(el('small', '@' + v.username));
      const vName = violationsData.violationTypes[v.violation_type]?.name || v.violation_type;
      const penaltyBadge = badge('-' + v.deducted_points + ' điểm', 'warn');
      const reasonEl = el('div', v.ai_reason, 'cell-content');
      if (v.ai_evidence) reasonEl.append(el('small', 'Bằng chứng: ' + v.ai_evidence));
      return [
        date(v.created),
        who,
        badge(vName),
        penaltyBadge,
        reasonEl,
        button('Xem hồ sơ', () => showUserReputation(v.user_id))
      ];
    }));
  }
  root.append(violationsCard);
}

function renderDossierView(container, dossier) {
  container.replaceChildren();
  const rep = dossier.reputation;
  const card = el('div', undefined, 'rep-dossier-card');

  const header = el('div', undefined, 'rep-dossier-header');
  const profileInfo = el('div');
  profileInfo.append(
    el('h3', rep.name + ' (@' + rep.username + ')'),
    badge(rep.tierLabel, rep.score >= 90 ? 'good' : rep.score >= 70 ? 'info' : rep.score >= 50 ? 'warn' : 'danger')
  );

  const scoreGauge = el('div', undefined, 'score-gauge');
  scoreGauge.append(el('b', rep.score), el('span', '/ 100 điểm'));
  header.append(profileInfo, scoreGauge);
  card.append(header);

  if (!dossier.violations?.length) {
    const cleanNotice = el('div', '✨ Thành viên chuẩn mực: Điểm uy tín khởi tạo 100/100 điểm, tài khoản hoàn toàn trong sạch chưa có vi phạm nào.', 'information');
    cleanNotice.style.margin = '14px 0 0 0';
    cleanNotice.style.background = '#f2fbf6';
    cleanNotice.style.borderColor = '#c6ebd6';
    cleanNotice.style.color = '#1e7545';
    cleanNotice.style.fontWeight = '600';
    card.append(cleanNotice);
  }

  const gates = el('div', undefined, 'rep-gates');
  gates.append(
    el('div', (rep.canGoLive ? '✔' : '✖') + ' Phát Live Stream', rep.canGoLive ? 'gate-active' : 'gate-blocked'),
    el('div', (rep.canPost ? '✔' : '✖') + ' Đăng Bài Viết', rep.canPost ? 'gate-active' : 'gate-blocked'),
    el('div', (rep.canComment ? '✔' : '✖') + ' Đăng Bình Luận', rep.canComment ? 'gate-active' : 'gate-blocked')
  );
  card.append(gates);

  const actionRow = el('div', undefined, 'actions rep-actions');
  actionRow.append(
    button('+ Khôi phục / Cộng điểm', () => openAdjustDialog(rep.userId, rep.username, 'restore'), 'primary'),
    button('- Trừ điểm vi phạm', () => openAdjustDialog(rep.userId, rep.username, 'deduct'), 'danger'),
    button('🔍 Xem Hồ sơ 360°', () => openMember360Modal(rep.username))
  );
  card.append(actionRow);

  const logSection = el('div', undefined, 'rep-sub-section');
  logSection.append(el('h4', 'Lịch sử Biến động Điểm Uy tín (Gần nhất)'));
  if (!rep.logs || !rep.logs.length) {
    logSection.append(el('p', 'Chưa có biến động điểm nào.', 'muted'));
  } else {
    table(logSection, ['Thời gian', 'Biến động', 'Điểm sau đổi', 'Lý do & Căn cứ', 'Người thực hiện'], rep.logs.map(l => [
      date(l.created),
      badge((l.points_delta > 0 ? '+' : '') + l.points_delta + ' điểm', l.points_delta > 0 ? 'good' : 'warn'),
      el('b', l.points_after + ' điểm'),
      l.reason,
      l.actor
    ]));
  }
  card.append(logSection);

  if (dossier.violations && dossier.violations.length) {
    const vSection = el('div', undefined, 'rep-sub-section');
    vSection.append(el('h4', 'Các Lần Vi Phạm Đã Ghi Nhận (' + dossier.violations.length + ')'));
    table(vSection, ['Thời gian', 'Loại vi phạm', 'Mức phạt', 'Chi tiết AI'], dossier.violations.map(v => [
      date(v.created),
      v.violationName,
      '-' + v.deducted_points + ' điểm',
      v.ai_reason
    ]));
    card.append(vSection);
  }

  container.append(card);
}

async function openAdjustDialog(userId, username, action) {
  const isRestore = action === 'restore';
  const points = prompt(isRestore ? `Nhập số điểm cần KHÔI PHỤC cho @${username} (1–100):` : `Nhập số điểm muốn TRỪ của @${username} (1–100):`, isRestore ? '10' : '5');
  if (points === null) return null;
  const numPoints = parseInt(points, 10);
  if (!Number.isInteger(numPoints) || numPoints < 1 || numPoints > 100) {
    toast('Số điểm phải là số nguyên từ 1 đến 100.');
    return null;
  }
  const reason = prompt('Nhập lý do điều chỉnh điểm (ít nhất 5 ký tự):', isRestore ? 'Đã giải quyết khiếu nại thành công' : 'Vi phạm chuẩn mực ứng xử');
  if (!reason || reason.trim().length < 5) {
    toast('Lý do phải có ít nhất 5 ký tự.');
    return null;
  }
  try {
    const res = await api('reputation/adjust', {
      userId,
      action,
      points: numPoints,
      reason: reason.trim()
    });
    toast(isRestore ? `Đã khôi phục +${numPoints} điểm cho @${username}` : `Đã trừ -${numPoints} điểm của @${username}`);
    const area = document.querySelector('.rep-dossier-area');
    if (area && res.dossier) renderDossierView(area, res.dossier);
    else if (state.page !== 'tickets') load(state.page);
    return res;
  } catch (err) {
    toast(err.message);
    return null;
  }
}

async function showUserReputation(userId) {
  state.page = 'reputation';
  updateActiveNav('reputation');
  $('page-title').textContent = names.reputation;
  $('page-description').textContent = descriptions.reputation;
  const root = el('div', 'Đang tải hồ sơ uy tín…', 'muted');
  $('content').replaceChildren(root);
  await renderReputationPage(root, ++state.revision);
  try {
    const dossier = await api('reputation/user/' + encodeURIComponent(userId));
    const area = root.querySelector('.rep-dossier-area');
    if (area) {
      renderDossierView(area, dossier);
      area.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }
  } catch (err) {
    toast(err.message);
  }
}

// ----------------------------------------------------
// ĐĂNG NHẬP, NÚT HIỆN MẬT KHẨU & ĐIỀU HƯỚNG MOBILE
// ----------------------------------------------------
if ($('toggle-password') && $('password')) {
  $('toggle-password').onclick = () => {
    const pw = $('password');
    const isHidden = pw.type === 'password';
    pw.type = isHidden ? 'text' : 'password';
    $('toggle-password').textContent = isHidden ? '🙈 Ẩn' : '👁️ Hiện';
    pw.focus();
  };
  const checkCaps = e => {
    const caps = $('caps-warning');
    if (!caps || typeof e.getModifierState !== 'function') return;
    caps.hidden = !e.getModifierState('CapsLock');
  };
  $('password').addEventListener('keydown', checkCaps);
  $('password').addEventListener('keyup', checkCaps);
  $('password').addEventListener('blur', () => { if ($('caps-warning')) $('caps-warning').hidden = true; });
}

if ($('mobile-menu-btn')) {
  $('mobile-menu-btn').onclick = () => {
    if (document.body.classList.contains('mobile-nav-open')) closeMobileNav();
    else openMobileNav();
  };
}
if ($('mobile-menu-close')) $('mobile-menu-close').onclick = closeMobileNav;
if ($('mobile-backdrop')) $('mobile-backdrop').onclick = closeMobileNav;

$('login-form').onsubmit = async e => {
  e.preventDefault();
  const b = e.target.querySelector('button[type="submit"]') || e.target.querySelector('button.primary');
  if (b) b.disabled = true;
  $('login-error').textContent = '';
  try {
    const cleanUsername = $('username').value.trim().replace(/^@/, '').toLowerCase();
    const d = await api('login', { username: cleanUsername, password: $('password').value });
    $('password').value = '';
    if ($('password').type === 'text') {
      $('password').type = 'password';
      if ($('toggle-password')) $('toggle-password').textContent = '👁️ Hiện';
    }
    signedIn(d.user);
  } catch (e) {
    $('login-error').textContent = e.message;
  } finally {
    if (b) b.disabled = false;
  }
};

$('logout').onclick = async () => { try { await api('logout', {}); signedOut(); } catch (e) { toast(e.message); } };
$('refresh').onclick = () => state.ticketId ? openTicket(state.ticketId) : load(state.page);
for (const b of $('navigation').querySelectorAll('button')) b.onclick = () => load(b.dataset.page);

// Department visual detection
const support = location.hostname === 'hotro.kinnect.io.vn', finance = location.hostname === 'taichinh.kinnect.io.vn', operations = location.hostname === 'kythuat.kinnect.io.vn';
const portalKey = finance ? 'finance' : operations ? 'operations' : support ? 'support' : 'admin';
document.body.setAttribute('data-portal', portalKey);

$('portal-label').textContent = finance ? 'CỔNG BỘ PHẬN TÀI CHÍNH' : operations ? 'CỔNG BỘ PHẬN KỸ THUẬT' : support ? 'CỔNG HỖ TRỢ & KIỂM DUYỆT' : 'CỔNG ADMIN CẤP CAO NHẤT';
$('portal-note').textContent = finance || support || operations ? 'Đăng nhập bằng tài khoản nhân sự do Admin cấp.' : 'Đăng nhập bằng tài khoản Admin Kinnect.';
document.title = finance ? 'Kinnect · Bộ phận Tài chính' : operations ? 'Kinnect · Bộ phận Kỹ thuật' : support ? 'Kinnect · Hỗ trợ & Kiểm duyệt' : 'Kinnect · Quản trị Cấp cao';

if ($('portal-art-title')) {
  $('portal-art-title').innerHTML = finance ? 'Minh bạch sổ cái.<br>Đối soát chính xác.' : operations ? 'Hệ thống tin cậy.<br>Giám sát thời gian thực.' : support ? 'Chăm sóc cộng đồng.<br>Tiếp nhận & Hỗ trợ.' : 'Quản trị tối cao.<br>An ninh & Phê duyệt.';
}
if ($('portal-art-desc')) {
  $('portal-art-desc').textContent = finance ? 'Tra soát giao dịch nạp xu, điều chỉnh sai sót và bảo toàn doanh thu nền tảng.' : operations ? 'Theo dõi chỉ số máy chủ, trạng thái dịch vụ AI và khắc phục sự cố ứng dụng.' : support ? 'Không gian tuyến đầu giải đáp thắc mắc, xử lý khiếu nại và giữ gìn môi trường văn minh.' : 'Khu vực quản trị điều hành, phân quyền nhân sự và kiểm soát toàn bộ hệ sinh thái Kinnect.';
}

api('me').then(d => signedIn(d.user)).catch(() => {});

const teamNames = { admin: 'Admin Cấp cao', support: 'Hỗ trợ & Kiểm duyệt', operations: 'Bộ phận Kỹ thuật', finance: 'Bộ phận Tài chính' },
  statusNames = { open: 'Mới tiếp nhận', in_progress: 'Đang xử lý', waiting: 'Chờ phản hồi', resolved: 'Hoàn tất' },
  priorityNames = { low: 'Thấp', normal: 'Bình thường', high: 'Cao', urgent: 'Khẩn cấp' };

function selectOptions(options, value) {
  const s = el('select');
  for (const [k, v] of options) {
    const o = el('option', v); o.value = k; s.append(o);
  }
  if (value !== undefined) s.value = value;
  return s;
}
function field(form, title, input) { const l = el('label', title); l.append(input); form.append(l); return input; }
function metricCards(root, items) {
  const row = el('div', undefined, 'metrics');
  for (const [label, value] of items) {
    const c = el('div', undefined, 'metric');
    c.append(el('span', label), el('b', value));
    row.append(c);
  }
  root.append(row);
}

async function extraRender(page, root, rev) {
  if (page === 'tickets') {
    const data = await api('tickets');
    if (rev !== state.revision) return;
    root.replaceChildren();
    metricCards(root, [
      ['Tất cả phiếu', data.summary.total],
      ['Mới tiếp nhận', data.summary.open],
      ['Đang xử lý', data.summary.in_progress],
      ['Hoàn tất', data.summary.resolved]
    ]);

    const top = el('div', undefined, 'section-bar');
    top.append(el('h3', '📋 Hàng chờ Phối hợp Liên Bộ phận'), button('+ Tiếp nhận & Điều phối yêu cầu', () => newTicket(root), 'primary'));
    root.append(top);

    const form = el('form', undefined, 'toolbar'), search = el('input');
    search.placeholder = 'Tìm tiêu đề, nội dung hoặc @khách_hàng…';
    const status = selectOptions([['all', 'Tất cả trạng thái'], ...Object.entries(statusNames)]);
    field(form, 'Tìm kiếm', search);
    field(form, 'Trạng thái', status);
    const filterBtn = el('button', 'Lọc danh sách', 'primary');
    filterBtn.type = 'submit';
    form.append(filterBtn);
    root.append(form);
    const results = el('div');
    root.append(results);

    let query = 0;
    const draw = async (initial) => {
      const q = ++query;
      try {
        const d = initial || await api('tickets?q=' + encodeURIComponent(search.value) + (status.value === 'all' ? '' : '&state=' + status.value));
        if (q !== query || rev !== state.revision) return;
        results.replaceChildren(el('p', `Hiển thị ${d.tickets.length} / ${d.total} phiếu phối hợp`, 'count'));
        table(results, ['Mã & Yêu cầu', 'Khách hàng', 'Ưu tiên', 'Bộ phận xử lý', 'Phụ trách', 'Trạng thái', 'Thao tác'], d.tickets.map(t => {
          const titleCell = el('div');
          titleCell.append(
            button(t.subject, () => openTicket(t.id), 'link-button'),
            el('small', '#' + t.id.slice(0, 8).toUpperCase() + ' · ' + date(t.updated))
          );
          const memberCell = t.member
            ? button('@' + t.member.replace(/^@/, ''), () => openMember360Modal(t.member), 'link-button')
            : '—';
          return [
            titleCell,
            memberCell,
            badge(priorityNames[t.priority], ['urgent', 'high'].includes(t.priority) ? 'warn' : ''),
            teamNames[t.team] || t.team,
            t.assigneeUsername ? '@' + t.assigneeUsername : 'Chưa gán',
            badge(statusNames[t.status], t.status === 'resolved' ? 'good' : t.status === 'in_progress' ? 'info' : 'warn'),
            button('Xử lý →', () => openTicket(t.id), 'primary')
          ];
        }));
      } catch (e) { toast(e.message); }
    };
    form.onsubmit = e => { e.preventDefault(); draw(); };
    status.onchange = () => draw();
    await draw(data);
    return;
  }

  if (page === 'finance') {
    const d = await api('finance');
    if (rev !== state.revision) return;
    root.replaceChildren();
    metricCards(root, [
      ['Bút toán ghi sổ', Number(d.totals.entries).toLocaleString('vi-VN')],
      ['Giá trị ghi sổ (VND)', Number(d.totals.net_vnd).toLocaleString('vi-VN')],
      ['Doanh thu nền tảng (VND)', Number(d.totals.platform_vnd || 0).toLocaleString('vi-VN')],
      ['Đề nghị ví chờ duyệt', Number(d.pendingWalletOps || 0).toLocaleString('vi-VN')]
    ]);
    root.append(el('p', 'Sổ cái đối soát tập trung. Mọi yêu cầu cộng/bù xu mua cho thành viên đều được lập qua công cụ Ví & Xu và cần Admin phê duyệt ghi sổ.', 'information'));

    const topActions = el('div', undefined, 'actions');
    topActions.style.marginBottom = '16px';
    topActions.append(
      button('🪙 Mở công cụ Tặng xu & Bù giao dịch', () => load('wallet'), 'primary'),
      button('📋 Tạo phiếu đối soát trình Admin', () => newTicket(root, 'admin'), '')
    );
    root.append(topActions);

    const toolbar = el('form', undefined, 'toolbar'), search = el('input');
    search.placeholder = 'Tên tài khoản (@username) hoặc mã tham chiếu giao dịch...';
    const kindSelect = selectOptions([
      ['all', 'Tất cả bút toán'],
      ['coin_purchase', 'Nạp xu mua (coin_purchase)'],
      ['gift_transfer', 'Tặng quà Live / Bài viết'],
      ['admin_trial', 'Xu tặng / Khuyến mại']
    ], 'all');
    field(toolbar, 'Tra cứu giao dịch', search);
    field(toolbar, 'Loại bút toán', kindSelect);
    const searchBtn = el('button', 'Tra cứu', 'primary');
    searchBtn.type = 'submit';
    toolbar.append(searchBtn);
    root.append(toolbar);
    const results = el('div');
    root.append(results);

    let query = 0;
    const draw = async (initial) => {
      const q = ++query;
      try {
        const data = initial || await api('finance?q=' + encodeURIComponent(search.value) + '&kind=' + encodeURIComponent(kindSelect.value));
        if (q !== query || rev !== state.revision) return;
        results.replaceChildren();
        table(results, ['Thời gian', 'Tài khoản', 'Loại', 'Xu', 'VND', 'Tham chiếu', 'Thao tác đối soát'], data.entries.map(e => {
          const act = el('div', undefined, 'actions');
          if (e.username) {
            act.append(
              button('🔍 Hồ sơ 360°', () => openMember360Modal(e.username)),
              button('🪙 Bù xu', () => {
                window.__WALLET_PREFILL = {
                  kind: 'paid_correction',
                  username: e.username,
                  reference: e.reference || ('TX-' + e.id),
                  title: 'Đối soát bù xu giao dịch cho @' + e.username,
                  reason: `Đối soát từ bút toán ${e.reference || e.id} (${e.coins} xu)`
                };
                load('wallet');
              })
            );
          }
          return [
            date(e.created),
            e.username ? button('@' + e.username, () => openMember360Modal(e.username), 'link-button') : '—',
            badge(e.kind),
            Number(e.coins).toLocaleString('vi-VN') + ' xu',
            Number(e.net_vnd).toLocaleString('vi-VN') + ' đ',
            e.reference || '—',
            act
          ];
        }));
      } catch (e) { toast(e.message); }
    };
    toolbar.onsubmit = e => { e.preventDefault(); draw(); };
    kindSelect.onchange = () => draw();
    await draw(d);
    return;
  }

  if (page === 'operations') {
    await renderOperationsPage(root, rev);
    return;
  }

  if (page === 'content') return renderContentPage(root, rev);
}

// ----------------------------------------------------
// BỘ PHẬN KỸ THUẬT & HẠ TẦNG (SRE & DEVOPS CONSOLE)
// ----------------------------------------------------
async function renderOperationsPage(root, rev) {
  const d = await api('operations');
  if (rev !== state.revision) return;
  root.replaceChildren();

  const banner = el('div', undefined, 'ops-banner' + (d.maintenanceMode ? ' maintenance' : ''));
  const bLeft = el('div');
  bLeft.append(
    el('p', 'KINNECT SRE & OPERATIONS COMMAND CENTER', 'eyebrow'),
    el('h2', d.maintenanceMode ? '⚠️ HỆ THỐNG ĐANG Ở CHẾ ĐỘ BẢO TRÌ' : '🟢 HỆ THỐNG HOẠT ĐỘNG BÌNH THƯỜNG (OPERATIONAL)'),
    el('p', `Máy chủ: ${d.platform} · Cổng dịch vụ: 4 Ingress Hosts (Admin, Hỗ trợ, Kỹ thuật, Tài chính) · Bộ nhớ heap: ${d.memoryDetail?.heapUsed || 0} MB`, 'muted')
  );
  const bRight = el('div', undefined, 'header-tools');
  bRight.append(
    badge(d.maintenanceMode ? 'ĐANG BẢO TRÌ' : 'HOẠT ĐỘNG 100%', d.maintenanceMode ? 'warn' : 'good')
  );
  banner.append(bLeft, bRight);
  root.append(banner);

  const hours = Math.floor(d.uptime / 3600);
  const mins = Math.floor((d.uptime % 3600) / 60);
  metricCards(root, [
    ['Uptime Máy chủ', `${hours}h ${mins}m`],
    ['Bộ nhớ RAM (RSS)', `${d.memoryMb} MB`],
    ['Cơ sở dữ liệu', `${d.database?.sizeMb || 0} MB (${d.database?.tables || 0} bảng)`],
    ['Hàng chờ AI', `${d.ai?.queue || 0} việc (${d.ai?.failed || 0} lỗi)`]
  ]);

  const controlsGrid = el('div', undefined, 'ops-controls-grid');

  const p1 = el('div', undefined, 'ops-panel');
  p1.append(
    el('h3', '⚡ Điều khiển Cụm Dịch vụ & Server'),
    el('p', `Tiến trình: Node.js (PID: ${d.services?.server?.pid || '3000'}) · Port: 3000 · SFU: Port 7885`, 'muted')
  );
  const btnGroup1 = el('div', undefined, 'ops-btn-group');
  btnGroup1.append(
    button(d.maintenanceMode ? '🟢 Tắt Bảo trì (Mở App)' : '⚠️ Bật Chế độ Bảo trì', async () => {
      const res = await api('operations/action', { action: 'toggle-maintenance' });
      toast(res.message);
      load('operations');
    }, d.maintenanceMode ? 'success-btn ops-btn' : 'warn-btn ops-btn'),
    button('🔄 Khởi động lại Server', async () => {
      if (!await confirmAction('Khởi động lại dịch vụ máy chủ?', 'Các kết nối sẽ tự động kết nối lại sau vài giây.')) return;
      const res = await api('operations/action', { action: 'restart-server' });
      toast(res.message);
      setTimeout(() => load('operations'), 2000);
    }, 'ops-btn'),
    button('🧹 Dọn dẹp RAM & Cache', async () => {
      const res = await api('operations/action', { action: 'purge-cache' });
      toast(res.message);
      load('operations');
    }, 'ops-btn')
  );
  p1.append(btnGroup1);

  const p2 = el('div', undefined, 'ops-panel');
  p2.append(
    el('h3', '🗄️ Quản trị & Tối ưu Cơ sở dữ liệu'),
    el('p', `SQLite Engine · ${d.database?.tables || 0} Bảng · ${d.database?.users || 0} Thành viên · ${d.database?.violations || 0} Vi phạm ghi nhận`, 'muted')
  );
  const btnGroup2 = el('div', undefined, 'ops-btn-group');
  btnGroup2.append(
    button('⚡ Tối ưu CSDL (Vacuum & Optimize)', async () => {
      const res = await api('operations/action', { action: 'optimize-db' });
      toast(res.message);
      load('operations');
    }, 'ops-btn'),
    button('🔍 Kiểm tra Toàn vẹn (Integrity Check)', async () => {
      const res = await api('operations/action', { action: 'check-integrity' });
      toast(res.message);
    }, 'ops-btn')
  );
  p2.append(btnGroup2);

  const p3 = el('div', undefined, 'ops-panel');
  p3.append(
    el('h3', '🤖 Điều khiển Động cơ Trí tuệ Nhân tạo (AI)'),
    el('p', `Kiểm duyệt tự động: ${d.ai?.moderation ? 'BẬT' : 'TẮT'} · Trợ lý AI Hỗ trợ: ${d.ai?.support ? 'BẬT' : 'TẮT'} · Trạng thái: ${d.ai?.ready ? 'Sẵn sàng' : 'Chưa cấu hình'}`, 'muted')
  );
  const btnGroup3 = el('div', undefined, 'ops-btn-group');
  btnGroup3.append(
    button(d.ai?.moderation ? 'Tắt Kiểm duyệt AI' : 'Bật Kiểm duyệt AI', async () => {
      const res = await api('operations/action', { action: 'toggle-ai-moderation' });
      toast(res.message);
      load('operations');
    }, d.ai?.moderation ? 'warn-btn ops-btn' : 'success-btn ops-btn'),
    button(d.ai?.support ? 'Tắt Trợ lý AI' : 'Bật Trợ lý AI', async () => {
      const res = await api('operations/action', { action: 'toggle-ai-support' });
      toast(res.message);
      load('operations');
    }, d.ai?.support ? 'warn-btn ops-btn' : 'success-btn ops-btn'),
    button('⚠️ Xả hàng chờ AI bị tắc', async () => {
      const res = await api('operations/action', { action: 'flush-ai-queue' });
      toast(res.message);
      load('operations');
    }, 'ops-btn')
  );
  p3.append(btnGroup3);

  controlsGrid.append(p1, p2, p3);
  root.append(controlsGrid);

  const logsPanel = el('div', undefined, 'card');
  const lHeader = el('div', undefined, 'section-bar');
  lHeader.append(
    el('h3', '📜 Nhật ký Hệ thống Thời gian thực (Live System Logs)'),
    button('Làm mới Logs ↻', () => drawLogs(), 'link-button')
  );
  const terminal = el('div', undefined, 'ops-terminal-wrap');
  terminal.textContent = 'Đang tải nhật ký...';
  logsPanel.append(lHeader, terminal);
  root.append(logsPanel);

  async function drawLogs() {
    try {
      const res = await api('operations/logs');
      terminal.replaceChildren();
      if (!res.logs || !res.logs.length) {
        terminal.textContent = 'Chưa có dữ liệu nhật ký mới.';
        return;
      }
      for (const item of res.logs) {
        const line = el('div', undefined, 'ops-log-line');
        const tag = el('span', `[${item.service.toUpperCase()}]`, 'ops-log-tag ' + item.service + (item.level === 'error' ? ' error' : ''));
        const time = el('span', new Date(item.time).toLocaleTimeString('vi-VN'), 'muted');
        const msg = el('span', item.msg);
        line.append(tag, time, msg);
        terminal.append(line);
      }
      terminal.scrollTop = terminal.scrollHeight;
    } catch (e) {
      terminal.textContent = 'Không tải được nhật ký: ' + e.message;
    }
  }
  drawLogs();

  const jobsCard = el('div', undefined, 'card');
  jobsCard.append(el('h3', '📋 Tác vụ AI Gần nhất (AI Jobs Pipeline)'));
  table(jobsCard, ['Thời gian', 'Loại tác vụ', 'Trạng thái', 'Số lần thử'], d.jobs.map(j => [date(j.created), j.kind, j.state, j.attempts]));
  root.append(jobsCard);
}

// ----------------------------------------------------
// QUẢN LÝ NỘI DUNG & XEM ẢNH/VIDEO BÀI ĐĂNG CHI TIẾT
// ----------------------------------------------------
async function renderContentPage(root, rev) {
  root.replaceChildren();

  const toolbar = el('form', undefined, 'content-toolbar');
  const searchInput = el('input');
  searchInput.placeholder = 'Tìm nội dung bài đăng, tác giả (@username)...';
  field(toolbar, 'Tìm kiếm bài đăng', searchInput);

  const filterSelect = selectOptions([
    ['all', 'Tất cả bài viết'],
    ['media', 'Chỉ bài có Ảnh / Video'],
    ['active', 'Đang hiển thị'],
    ['hidden', 'Đã bị ẩn']
  ], 'all');
  field(toolbar, 'Bộ lọc trạng thái & đính kèm', filterSelect);

  const searchBtn = el('button', 'Tìm kiếm', 'primary');
  searchBtn.type = 'submit';
  toolbar.append(searchBtn);
  root.append(toolbar);

  const container = el('div');
  root.append(container);

  const fetchAndRender = async () => {
    container.replaceChildren(el('p', 'Đang tải danh sách bài viết và ảnh đính kèm…', 'muted'));
    const q = searchInput.value.trim();
    const filter = filterSelect.value;
    try {
      const d = await api('content?q=' + encodeURIComponent(q) + '&filter=' + encodeURIComponent(filter));
      if (rev !== state.revision) return;
      container.replaceChildren();

      if (!d.posts || !d.posts.length) {
        empty(container, 'Không có bài đăng nào phù hợp.');
        return;
      }

      container.append(el('p', `Hiển thị ${d.posts.length} bài đăng gần nhất:`, 'count'));

      const grid = el('div', undefined, 'posts-grid');
      for (const p of d.posts) {
        const card = el('div', undefined, 'post-item-card');

        const header = el('div', undefined, 'post-header-meta');
        const authorBox = el('div', undefined, 'post-author-info');
        authorBox.append(
          el('b', p.name || p.username),
          el('small', '@' + p.username + ' · ' + date(p.created))
        );

        const badgesBox = el('div', undefined, 'post-badges');
        badgesBox.append(
          badge(p.hidden ? 'Đã ẩn' : 'Đang hiện', p.hidden ? 'warn' : 'good'),
          badge(p.visibility === 'public' ? 'Công khai' : p.visibility === 'private' ? 'Riêng tư' : 'Bạn bè', 'info')
        );
        if (p.has_media) {
          badgesBox.append(badge(p.media_type?.startsWith('video/') ? '🎬 Video' : '🖼️ Có ảnh', 'good'));
        }
        header.append(authorBox, badgesBox);
        card.append(header);

        if (p.body) {
          card.append(el('div', p.body, 'post-body-text'));
        }

        if (p.has_media && p.media_url) {
          const mediaBox = el('div', undefined, 'post-media-box');
          if (p.media_type?.startsWith('video/')) {
            const vid = el('video', undefined, 'post-video-thumb');
            vid.src = p.media_url;
            vid.controls = true;
            vid.preload = 'metadata';
            mediaBox.append(vid);
          } else {
            const img = el('img', undefined, 'post-media-thumb');
            img.src = p.media_url;
            img.alt = 'Ảnh bài đăng';
            img.loading = 'lazy';
            img.title = 'Bấm để xem ảnh lớn chi tiết';
            img.onclick = () => openPostDetailModal(p);
            mediaBox.append(img);
          }
          card.append(mediaBox);
        }

        const footer = el('div', undefined, 'post-footer-actions');
        const viewBtn = button('👁️ Xem chi tiết', () => openPostDetailModal(p));
        const toggleBtn = button(
          p.hidden ? 'Hiện bài' : 'Ẩn bài',
          async () => {
            await mutate('moderate', { action: p.hidden ? 'show-post' : 'hide-post', target: p.id }, 'Thay đổi hiển thị bài viết?', 'Thao tác sẽ được ghi vào nhật ký.');
            fetchAndRender();
          },
          p.hidden ? '' : 'danger'
        );
        const dossierBtn = button('🔍 Hồ sơ 360°', () => openMember360Modal(p.username));

        const actionGroup = el('div', undefined, 'actions');
        actionGroup.append(viewBtn, toggleBtn, dossierBtn);
        footer.append(actionGroup);
        card.append(footer);

        grid.append(card);
      }
      container.append(grid);
    } catch (err) {
      container.replaceChildren(el('p', err.message, 'error'));
    }
  };

  toolbar.onsubmit = e => {
    e.preventDefault();
    fetchAndRender();
  };
  filterSelect.onchange = () => fetchAndRender();
  await fetchAndRender();
}

function openPostDetailModal(p) {
  let modal = $('post-detail-modal');
  if (!modal) {
    modal = el('dialog', undefined, 'post-modal-dialog');
    modal.id = 'post-detail-modal';
    document.body.append(modal);
  }
  modal.replaceChildren();

  const title = el('h3', 'Chi tiết bài đăng của ' + (p.name || p.username));
  const meta = el('p', `Tác giả: @${p.username} | Thời gian: ${date(p.created)} | Quyền hiển thị: ${p.visibility || 'public'}`);
  meta.className = 'muted';
  modal.append(title, meta);

  if (p.body) {
    const textTitle = el('p', 'NỘI DUNG VĂN BẢN:', 'eyebrow');
    const fullText = el('div', p.body, 'post-body-text');
    fullText.style.maxHeight = '220px';
    modal.append(textTitle, fullText);
  }

  if (p.has_media && p.media_url) {
    const mediaTitle = el('p', p.media_type?.startsWith('video/') ? 'TỆP VIDEO ĐÍNH KÈM:' : 'ẢNH GỐC ĐÍNH KÈM (BẤM VÀO ẢNH ĐỂ MỞ KÍCH THƯỚC ĐẦY ĐỦ):', 'eyebrow');
    modal.append(mediaTitle);
    if (p.media_type?.startsWith('video/')) {
      const vid = el('video', undefined, 'modal-full-video');
      vid.src = p.media_url;
      vid.controls = true;
      modal.append(vid);
    } else {
      const a = el('a');
      a.href = p.media_url;
      a.target = '_blank';
      a.title = 'Mở ảnh kích thước đầy đủ trong tab mới';
      const img = el('img', undefined, 'modal-full-img');
      img.src = p.media_url;
      img.alt = 'Ảnh bài đăng';
      a.append(img);
      modal.append(a);
    }
  }

  const actions = el('div', undefined, 'dialog-actions');
  const hideBtn = button(
    p.hidden ? 'Hiện bài' : 'Ẩn bài viết',
    async () => {
      await mutate('moderate', { action: p.hidden ? 'show-post' : 'hide-post', target: p.id }, 'Thay đổi hiển thị bài viết?', 'Thao tác sẽ được ghi sổ.');
      modal.close();
      load(state.page);
    },
    p.hidden ? '' : 'danger'
  );
  const repBtn = button('🔍 Hồ sơ 360° @' + p.username, () => {
    modal.close();
    openMember360Modal(p.username);
  });
  const closeBtn = el('button', 'Đóng', 'primary');
  closeBtn.type = 'button';
  closeBtn.onclick = () => modal.close();

  actions.append(hideBtn, repBtn, closeBtn);
  modal.append(actions);
  modal.showModal();
}

// ----------------------------------------------------
// TIẾP NHẬN PHIẾU MỚI & PHÂN TÍCH ĐIỀU PHỐI BẰNG AI
// ----------------------------------------------------
function newTicket(root, defaultTeam, prefill = {}) {
  const existing = root.querySelector('.ticket-create');
  if (existing) existing.remove();

  const form = el('form', undefined, 'card ticket-create');
  form.append(
    el('h3', '📋 Tiếp nhận & Điều phối Phiếu Phối hợp Liên Bộ phận'),
    el('p', 'Nhập yêu cầu của khách hàng hoặc đề nghị phối hợp. Bạn có thể bấm "🤖 AI Phân tích & Gợi ý" để tự động phân loại bộ phận và mức độ ưu tiên.', 'muted')
  );

  const subject = el('input');
  subject.required = true;
  subject.maxLength = 180;
  subject.placeholder = 'Ví dụ: Khách hàng nạp xu chưa vào ví / Khiếu nại điểm uy tín...';
  if (prefill.subject) subject.value = prefill.subject;
  field(form, 'Tiêu đề yêu cầu', subject);

  const description = el('textarea');
  description.required = true;
  description.maxLength = 6000;
  description.rows = 4;
  description.placeholder = 'Mô tả chi tiết tình huống, mã giao dịch (nếu có) và các bước đã kiểm tra...';
  if (prefill.description) description.value = prefill.description;
  field(form, 'Mô tả chi tiết & căn cứ', description);

  const member = el('input');
  member.maxLength = 80;
  member.placeholder = 'Ví dụ: @vuanh97nd (không bắt buộc)';
  if (prefill.member) member.value = prefill.member;
  field(form, 'Tài khoản thành viên liên quan', member);

  const aiInsightBox = el('div', undefined, 'information');
  aiInsightBox.hidden = true;
  form.append(aiInsightBox);

  const row = el('div', undefined, 'form-grid'),
    team = selectOptions(Object.entries(teamNames), defaultTeam || state.user.team),
    priority = selectOptions(Object.entries(priorityNames), prefill.priority || 'normal');
  field(row, 'Chuyển đến bộ phận', team);
  field(row, 'Mức độ ưu tiên', priority);
  form.append(row);

  const actions = el('div', undefined, 'actions'),
    submit = el('button', 'Tạo phiếu & gửi bộ phận', 'primary');
  submit.type = 'submit';
  const aiBtn = button('🤖 AI Phân tích & Gợi ý điều phối', async () => {
    if (!subject.value.trim() && !description.value.trim()) {
      toast('Hãy nhập tiêu đề hoặc mô tả để AI phân tích.');
      return;
    }
    const res = await api('tickets/ai-classify', {
      subject: subject.value,
      description: description.value,
      member: member.value
    });
    team.value = res.recommendedTeam || team.value;
    priority.value = res.recommendedPriority || priority.value;
    aiInsightBox.hidden = false;
    aiInsightBox.textContent = `🤖 AI Gợi ý: Chuyển [${teamNames[res.recommendedTeam] || res.recommendedTeam}] · Ưu tiên [${priorityNames[res.recommendedPriority] || res.recommendedPriority}] · SLA mục tiêu: ${res.slaTargetMinutes || 60} phút. (${res.summary || ''})`;
  });
  actions.append(submit, aiBtn, button('Hủy', () => form.remove()));
  form.append(actions);

  form.onsubmit = async e => {
    e.preventDefault();
    submit.disabled = true;
    try {
      const d = await api('tickets', {
        subject: subject.value,
        description: description.value,
        member: member.value,
        team: team.value,
        priority: priority.value
      });
      toast('Đã tạo và chuyển phiếu thành công.');
      await openTicket(d.ticket.id);
    } catch (e) { toast(e.message); } finally { submit.disabled = false; }
  };
  root.prepend(form);
  subject.focus();
}

// ----------------------------------------------------
// MÀN HÌNH XỬ LÝ PHIẾU TOÀN DIỆN (TICKET WORKBENCH)
// ----------------------------------------------------
async function openTicket(id) {
  state.page = 'tickets';
  state.ticketId = id;
  closeMobileNav();
  const rev = ++state.revision;
  updateActiveNav('tickets');
  $('page-title').textContent = 'Xử lý Phiếu Phối hợp';
  $('page-description').textContent = 'Thao tác xử lý 1 chạm, đối soát 360° khách hàng và bàn giao liên bộ phận nhịp nhàng.';
  const root = el('div', 'Đang tải chi tiết phiếu…', 'muted');
  $('content').replaceChildren(root);

  try {
    const [d, teamRes] = await Promise.all([
      api('tickets/' + encodeURIComponent(id)),
      state.user.role === 'admin' ? api('team').catch(() => ({ staff: [] })) : Promise.resolve({ staff: [] })
    ]);
    if (rev !== state.revision) return;
    const t = d.ticket;
    root.className = '';
    root.replaceChildren();

    const topNav = el('div', undefined, 'ticket-top-bar');
    topNav.append(
      button('← Về hàng chờ phiếu', () => load('tickets')),
      el('span', `Mã phiếu: #${t.id.slice(0, 8).toUpperCase()} · Phiên bản #${t.version}`, 'muted')
    );
    root.append(topNav);

    // 1. Thanh Thao Tác Nhanh 1 Chạm (1-Click Quick Status & Resolution Bar)
    const quickBar = el('div', undefined, 'card ticket-quick-bar');
    const quickInfo = el('div');
    quickInfo.append(
      el('p', 'TRẠNG THÁI & XỬ LÝ NHANH 1 CHẠM', 'eyebrow'),
      el('div', undefined, 'post-badges')
    );
    quickInfo.lastChild.append(
      badge('Trạng thái: ' + statusNames[t.status], t.status === 'resolved' ? 'good' : t.status === 'in_progress' ? 'info' : 'warn'),
      badge('Bộ phận: ' + (teamNames[t.team] || t.team)),
      badge('Ưu tiên: ' + (priorityNames[t.priority] || t.priority), ['urgent', 'high'].includes(t.priority) ? 'warn' : '')
    );
    const quickBtns = el('div', undefined, 'actions');

    const quickProcess = async (newStatus, defaultMsg) => {
      const res = await api('tickets/' + t.id + '/events', {
        action: 'process',
        status: newStatus,
        message: defaultMsg,
        version: t.version
      });
      toast('Đã chuyển trạng thái phiếu sang: ' + statusNames[res.ticket.status]);
      await openTicket(id);
    };

    if (t.status !== 'resolved') {
      if (t.status !== 'in_progress') {
        quickBtns.append(button('▶ Tiếp nhận & Đang xử lý', () => quickProcess('in_progress', `${state.user.name || state.user.username} đã tiếp nhận và đang trực tiếp xử lý phiếu.`), 'primary'));
      }
      if (t.status !== 'waiting') {
        quickBtns.append(button('⏳ Chờ phản hồi / đối soát', () => quickProcess('waiting', 'Đang chờ thông tin phản hồi hoặc kết quả kiểm tra liên bộ phận.')));
      }
      quickBtns.append(button('✔ Xử lý xong & Hoàn tất phiếu', () => quickProcess('resolved', 'Đã giải quyết hoàn tất yêu cầu trên phiếu phối hợp.'), 'success-btn ops-btn'));
    } else if (state.user.role === 'admin') {
      quickBtns.append(button('↺ Mở lại phiếu để xử lý tiếp', () => quickProcess('open', 'Admin mở lại phiếu để tiếp tục xử lý.'), 'warn-btn ops-btn'));
    }
    quickBar.append(quickInfo, quickBtns);
    root.append(quickBar);

    const layout = el('div', undefined, 'ticket-layout'),
      left = el('div'),
      right = el('div'),
      card = el('article', undefined, 'card');

    card.append(
      el('p', 'NỘI DUNG YÊU CẦU #' + t.id.slice(0, 8).toUpperCase(), 'eyebrow'),
      el('h2', t.subject),
      el('p', t.description, 'report-text'),
      el('small', 'Khởi tạo bởi ' + (d.events[0]?.actor_name || t.created_by) + ' · ' + date(t.created))
    );
    left.append(card);

    // 2. Trung tâm Thao tác Trực tiếp Khách hàng ngay trong Phiếu (In-Ticket Customer 360° Action Center)
    const memberCard = el('div', undefined, 'card customer-action-card');
    const cleanMember = (t.member || '').trim().replace(/^@/, '');
    if (cleanMember) {
      memberCard.append(el('p', 'KHÁCH HÀNG LIÊN QUAN TRÊN PHIẾU', 'eyebrow'), el('p', 'Đang tải thông tin @' + cleanMember + '…', 'muted'));
      left.append(memberCard);
      api('member-360/' + encodeURIComponent(cleanMember)).then(m360 => {
        if (rev !== state.revision) return;
        const u = m360.user;
        const rep = m360.dossier?.reputation || { score: 100, tierLabel: 'Chuẩn mực' };
        memberCard.replaceChildren();
        const mHead = el('div', undefined, 'rep-dossier-header');
        const mInfo = el('div');
        mInfo.append(
          el('p', 'TRUNG TÂM XỬ LÝ KHÁCH HÀNG TRỰC TIẾP', 'eyebrow'),
          el('h3', `${u.name || u.username} (@${u.username})`),
          el('small', `Điểm uy tín: ${rep.score}/100 (${rep.tierLabel}) · Bài đăng: ${m360.posts?.length || 0} · Giao dịch xu: ${m360.wallet ? Number(m360.wallet.totalCoins || 0).toLocaleString('vi-VN') + ' xu' : '—'}`)
        );
        mHead.append(mInfo, badge(u.suspended ? 'Đang đình chỉ' : 'Đang hoạt động', u.suspended ? 'danger' : 'good'));
        memberCard.append(mHead);

        const mActions = el('div', undefined, 'actions');
        mActions.style.marginTop = '14px';
        mActions.append(
          button('🔍 Mở Hồ sơ 360°', () => openMember360Modal(u.username), 'primary'),
          button('⭐ Cộng / Trừ điểm uy tín', async () => {
            const act = confirm('Bấm OK để KHÔI PHỤC (+ điểm) hoặc Cancel để TRỪ điểm vi phạm của @' + u.username) ? 'restore' : 'deduct';
            const adjusted = await openAdjustDialog(u.id, u.username, act);
            if (adjusted) {
              await api('tickets/' + t.id + '/events', {
                action: 'process',
                status: 'in_progress',
                message: `Đã điều chỉnh điểm uy tín (${act === 'restore' ? 'Khôi phục' : 'Trừ điểm'}) cho @${u.username}. Điểm hiện tại: ${adjusted.dossier?.reputation?.score ?? 100}/100.`,
                version: t.version
              }).catch(() => {});
              await openTicket(id);
            }
          })
        );
        if (state.user.role === 'admin' || state.user.team === 'finance') {
          mActions.append(button('🪙 Tặng / Bù xu ngay', () => {
            window.__WALLET_PREFILL = {
              kind: 'paid_correction',
              username: u.username,
              ticketId: t.id,
              title: `Xử lý phiếu #${t.id.slice(0, 8).toUpperCase()}: ${t.subject}`,
              reason: `Thực hiện theo phiếu phối hợp #${t.id} cho thành viên @${u.username}`
            };
            load('wallet');
          }));
        }
        if (u.role === 'user') {
          mActions.append(
            button(u.suspended ? '🟢 Mở khóa tài khoản' : '🚫 Đình chỉ tài khoản', async () => {
              if (!await confirmAction(u.suspended ? 'Mở khóa tài khoản?' : 'Đình chỉ tài khoản?', '@' + u.username)) return;
              await api('moderate', { action: u.suspended ? 'restore-user' : 'suspend-user', target: u.id });
              await api('tickets/' + t.id + '/events', {
                action: 'process',
                status: 'in_progress',
                message: `${u.suspended ? 'Đã mở khóa khôi phục' : 'Đã đình chỉ'} tài khoản @${u.username} ngay trên phiếu.`,
                version: t.version
              }).catch(() => {});
              toast('Đã cập nhật trạng thái tài khoản @' + u.username);
              await openTicket(id);
            }, u.suspended ? '' : 'danger')
          );
        }
        memberCard.append(mActions);
      }).catch(() => {
        memberCard.replaceChildren(
          el('p', 'KHÁCH HÀNG LIÊN QUAN: ' + t.member, 'eyebrow'),
          button('🔍 Tìm kiếm thành viên "' + cleanMember + '"', () => openMember360Modal(cleanMember))
        );
      });
    }

    // 3. Lịch sử phối hợp
    const history = el('div', undefined, 'card timeline');
    history.append(el('h3', '📜 Lịch sử Phối hợp Liên Bộ phận'), el('p', `Hiển thị ${d.events.length} / ${d.eventTotal || d.events.length} cập nhật`, 'count'));
    for (const event of d.events) {
      const item = el('div', undefined, 'timeline-item');
      item.append(
        el('b', event.actor_name || event.actor),
        el('small', (teamNames[event.actor_team] || event.actor_team) + ' · ' + date(event.created)),
        el('p', event.message || ({
          create: 'Tiếp nhận yêu cầu mới',
          note: 'Thêm ghi chú xử lý',
          transfer: 'Bàn giao bộ phận',
          status: 'Cập nhật trạng thái',
          assign: 'Phân công nhân sự',
          process: 'Xử lý & cập nhật phiếu'
        }[event.action] || event.action))
      );
      const eventBadges = el('div', undefined, 'post-badges');
      if (event.after?.team && (!event.before || event.after.team !== event.before.team)) {
        eventBadges.append(badge('↪ ' + (teamNames[event.after.team] || event.after.team), 'info'));
      }
      if (event.after?.status && (!event.before || event.after.status !== event.before.status)) {
        eventBadges.append(badge(statusNames[event.after.status] || event.after.status, event.after.status === 'resolved' ? 'good' : 'warn'));
      }
      if (eventBadges.childNodes.length) item.append(eventBadges);
      history.append(item);
    }
    left.append(history);

    // 4. Khung Trách nhiệm & Biểu mẫu Xử lý / Điều phối Hợp nhất (Unified Dispatch & Processing Workbench)
    const info = el('div', undefined, 'card');
    info.append(
      el('h3', '🏢 Trách nhiệm & Bộ phận tham gia'),
      el('p', 'Bộ phận đang phụ trách: ' + (teamNames[t.team] || t.team)),
      el('p', 'Nhân viên phụ trách: ' + (t.assigneeUsername ? '@' + t.assigneeUsername : 'Chưa gán cụ thể (toàn bộ phận cùng xử lý)')),
      el('p', 'Các bộ phận tham gia: ' + (t.participantTeams || [t.team]).map(k => teamNames[k] || k).join(' · ')),
      el('small', 'Cập nhật lần cuối: ' + date(t.updated))
    );
    right.append(info);

    if (t.status !== 'resolved' || state.user.role === 'admin') {
      const form = el('form', undefined, 'card ticket-process-form');
      form.append(
        el('h3', '⚡ Xử lý, Phân công & Bàn giao Phiếu'),
        el('p', 'Cập nhật trạng thái, chuyển bộ phận, gán nhân sự và ghi chú kết quả xử lý chỉ trong 1 bước.', 'muted')
      );

      // Chuyển nhanh sang bộ phận khác bằng 1 chạm
      const handoffWrap = el('div', undefined, 'handoff-pills');
      handoffWrap.append(el('small', 'Chuyển nhanh sang bộ phận:'));
      const handoffBtns = el('div', undefined, 'actions');

      const defaultNextStatus = t.status === 'open' ? 'in_progress' : t.status;
      const status = selectOptions(Object.entries(statusNames), defaultNextStatus);
      const priority = selectOptions(Object.entries(priorityNames), t.priority);
      const team = selectOptions(Object.entries(teamNames), t.team);
      const staff = selectOptions([['', '— Không gán riêng (Để cả bộ phận xử lý) —']]);
      const message = el('textarea');
      message.rows = 4;
      message.maxLength = 4000;
      message.placeholder = 'Nhập kết quả xử lý, nội dung phản hồi hoặc yêu cầu phối hợp cho bộ phận tiếp nhận...';

      const staffList = (teamRes.staff || []).filter(p => !p.suspended);
      if (state.user.role === 'admin') {
        for (const person of staffList) {
          const deptTag = person.team === 'finance' ? '[Tài chính]' : person.team === 'operations' ? '[Kỹ thuật]' : '[Hỗ trợ]';
          const o = el('option', `${deptTag} ${person.name} (@${person.username})`);
          o.value = person.id;
          o.dataset.team = person.team;
          staff.append(o);
        }
        staff.value = t.assignee || '';
        staff.onchange = () => {
          const selectedStaff = staffList.find(p => p.id === staff.value);
          if (selectedStaff && team.value !== selectedStaff.team) {
            team.value = selectedStaff.team;
            toast(`Đã tự động chọn bộ phận [${teamNames[selectedStaff.team]}] theo nhân sự @${selectedStaff.username}.`);
          }
        };
      }

      for (const [deptKey, deptLabel] of [
        ['support', '↪ Giao Hỗ trợ'],
        ['finance', '↪ Giao Tài chính'],
        ['operations', '↪ Giao Kỹ thuật'],
        ['admin', '↪ Trình Admin']
      ]) {
        if (deptKey === t.team) continue;
        handoffBtns.append(button(deptLabel, () => {
          team.value = deptKey;
          if (deptKey === 'admin') staff.value = '';
          if (!message.value.trim()) {
            message.value = `Bàn giao phiếu sang [${teamNames[deptKey]}] để phối hợp xử lý tiếp.`;
          }
          message.focus();
        }));
      }
      handoffWrap.append(handoffBtns);
      form.append(handoffWrap);

      const gridRow = el('div', undefined, 'form-grid');
      field(gridRow, 'Trạng thái xử lý', status);
      field(gridRow, 'Mức độ ưu tiên', priority);
      form.append(gridRow);

      field(form, 'Bộ phận phụ trách', team);
      if (state.user.role === 'admin') {
        field(form, 'Phân công nhân viên cụ thể (tự động chuyển về bộ phận của nhân viên)', staff);
      }

      // Mẫu câu phản hồi nhanh
      const templatesWrap = el('div', undefined, 'quick-reply-chips');
      templatesWrap.append(el('small', 'Mẫu ghi chú nhanh:'));
      const chipRow = el('div', undefined, 'actions');
      for (const [chipLabel, chipText, chipStatus] of [
        ['✔ Đã kiểm tra & xử lý xong', 'Đã kiểm tra đầy đủ và xử lý hoàn tất yêu cầu cho thành viên.', 'resolved'],
        ['💳 Đề nghị Tài chính đối soát', 'Đã xác minh thông tin ban đầu. Đề nghị Bộ phận Tài chính kiểm tra sổ cái và đối soát xu cho thành viên.', 'in_progress'],
        ['💻 Đề nghị Kỹ thuật kiểm tra log', 'Đề nghị Bộ phận Kỹ thuật kiểm tra nhật ký máy chủ / trạng thái dịch vụ liên quan.', 'in_progress'],
        ['⭐ Đã khôi phục uy tín', 'Đã rà soát nội dung hợp lệ và khôi phục điểm uy tín 100/100 cho thành viên.', 'resolved']
      ]) {
        chipRow.append(button(chipLabel, () => {
          message.value = chipText;
          if (chipStatus) status.value = chipStatus;
          if (chipLabel.includes('Tài chính')) team.value = 'finance';
          if (chipLabel.includes('Kỹ thuật')) team.value = 'operations';
        }));
      }
      templatesWrap.append(chipRow);
      form.append(templatesWrap);

      field(form, 'Nội dung xử lý / Ghi chú bàn giao', message);

      const submit = el('button', '💾 Lưu & Thực thi xử lý phiếu', 'primary');
      submit.type = 'submit';
      form.append(submit);

      form.onsubmit = async e => {
        e.preventDefault();
        submit.disabled = true;
        try {
          const autoMsg = message.value.trim() || (
            status.value !== t.status
              ? `Cập nhật trạng thái phiếu sang [${statusNames[status.value]}].`
              : team.value !== t.team
                ? `Bàn giao phiếu sang [${teamNames[team.value]}].`
                : 'Cập nhật thông tin xử lý phiếu.'
          );
          await api('tickets/' + t.id + '/events', {
            action: 'process',
            status: status.value,
            priority: priority.value,
            team: team.value,
            ...(state.user.role === 'admin' ? { assignee: staff.value || null } : {}),
            message: autoMsg,
            version: t.version
          });
          toast('Đã lưu và cập nhật phiếu thành công.');
          await openTicket(id);
        } catch (e) { toast(e.message); } finally { submit.disabled = false; }
      };
      right.append(form);
    } else {
      right.append(el('p', 'Phiếu đã hoàn tất. Chỉ Admin có thể mở lại.', 'information'));
    }

    layout.append(left, right);
    root.append(layout);
  } catch (e) {
    if (rev === state.revision) {
      root.replaceChildren();
      empty(root, e.message);
    }
  }
}

const actionNames = {
  login: 'Đăng nhập hệ thống',
  'create-support': 'Tạo tài khoản nhân sự',
  'suspend-support': 'Khóa nhân sự',
  'restore-support': 'Mở khóa nhân sự',
  'reset-support-password': 'Đặt lại mật khẩu nhân sự',
  'move-team:support': 'Chuyển nhân sự sang Hỗ trợ',
  'move-team:operations': 'Chuyển nhân sự sang Kỹ thuật',
  'move-team:finance': 'Chuyển nhân sự sang Tài chính',
  'change-password': 'Đổi mật khẩu',
  'suspend-user': 'Đình chỉ thành viên',
  'restore-user': 'Khôi phục thành viên',
  'hide-post': 'Ẩn bài viết',
  'show-post': 'Hiện bài viết',
  'hide-short': 'Ẩn video ngắn',
  'show-short': 'Hiện video ngắn',
  'close-report': 'Đóng báo cáo vi phạm',
  'dismiss-reset': 'Bỏ qua yêu cầu khôi phục',
  'reset-user-password': 'Cấp mật khẩu tạm thành viên',
  'wallet-preview:gift': 'Tạo chiến dịch xu tặng',
  'wallet-preview:paid_correction': 'Lập đề nghị bù xu mua',
  'wallet-confirm': 'Admin phê duyệt ghi sổ ví',
  'wallet-reject': 'Từ chối đề nghị điều chỉnh ví',
  'reputation-restore': 'Khôi phục điểm uy tín',
  'reputation-deduct': 'Trừ điểm uy tín vi phạm',
  'ai-dispatch-ticket': 'AI điều phối phiếu tự động'
};

const iconPaths = {
  overview: ['M3 3h7v7H3z', 'M14 3h7v7h-7z', 'M3 14h7v7H3z', 'M14 14h7v7h-7z'],
  tickets: ['M4 4h16v16H4z', 'M8 8h8M8 12h6M8 16h4'],
  reputation: ['M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z'],
  users: ['M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2', 'M16 3a4 4 0 0 1 0 8', 'M22 21v-2a4 4 0 0 0-3-3.87', 'M9 3a4 4 0 1 0 0 8 4 4 0 0 0 0-8'],
  reports: ['M4 22V3', 'M4 3h14l-3 5 3 5H4'],
  resets: ['M3 11a9 9 0 1 1 3 8', 'M3 4v7h7', 'M12 7v5l3 2'],
  wallet: ['M3 6h18v14H3z', 'M3 6l14-4v4', 'M16 12h5v4h-5z'],
  finance: ['M3 6h18v14H3z', 'M3 6l14-4v4', 'M16 12h5v4h-5z'],
  operations: ['M3 4h18v6H3z', 'M3 14h18v6H3z', 'M7 7h.01M7 17h.01'],
  content: ['M4 3h16v18H4z', 'M8 7h8M8 11h8M8 15h5'],
  team: ['M12 3l8 4v5c0 5-4 8-8 10-4-2-8-5-8-10V7z', 'M9 12l2 2 4-4'],
  activity: ['M4 5h16M4 12h16M4 19h16'],
  password: ['M5 10h14v11H5z', 'M8 10V6a4 4 0 0 1 8 0v4']
};

for (const b of $('navigation').querySelectorAll('button')) {
  const page = b.dataset.page;
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('viewBox', '0 0 24 24');
  svg.setAttribute('aria-hidden', 'true');
  for (const d of iconPaths[page] || []) {
    const p = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    p.setAttribute('d', d);
    svg.append(p);
  }
  b.replaceChildren(svg, document.createTextNode(names[page]));
}
