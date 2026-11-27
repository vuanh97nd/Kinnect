/* ==========================================================================
   KINNECT · BẢNG GIÁM SÁT KỸ THUẬT + ĐIỀU KHIỂN TỪNG MÁY CHỦ
   File: admin/ops-monitor.js
   Tài liệu thiết kế: OPS-MONITORING-DESIGN.md

   Nguyên tắc:
   - Chỉ đọc trạng thái qua GET /api/console/ops/metrics (5 giây/lần).
   - Mọi thao tác đi qua POST /api/console/ops/action, KHÔNG sửa state cục bộ
     trước khi server xác nhận.
   - Không hiển thị số 0 khi thực chất là "chưa biết".
   - Tự gắn vào trang 'operations'; nếu trang đó không tồn tại thì không làm gì.
   ========================================================================== */

(function () {
  'use strict';

  if (window.__opsMonitorLoaded) return;
  window.__opsMonitorLoaded = true;

  var ENDPOINT_METRICS = '/api/console/ops/metrics';
  var ENDPOINT_ACTION = '/api/console/ops/action';
  var ENDPOINT_AUDIT = '/api/console/ops/audit';

  var POLL_MS = 5000;
  var POLL_HIDDEN_MS = 30000;
  var STALE_MS = 20000;
  var DEAD_MS = 60000;

  var SEVERITY_LABEL = { good: 'ỔN ĐỊNH', watch: 'THEO DÕI', warning: 'CẢNH BÁO', critical: 'NGUY HIỂM' };
  var STATUS_LABEL = { online: 'Hoạt động', degraded: 'Suy giảm', offline: 'Mất kết nối', draining: 'Đang xả tải' };

  /* ------------------------------------------------------------------ *
   * 1. Định nghĩa thao tác theo vai trò máy chủ
   * ------------------------------------------------------------------ */

  /*
    Mỗi mục:
      id          mã gửi lên server
      label       nhãn khi đang ở trạng thái thường
      offAction   mã gửi khi bấm lần nữa để đảo trạng thái
      offLabel    nhãn khi đang ở trạng thái đã bật
      activeWhen  { key, value } — coi là "đang bật" khi server[key] === value
      typed       bắt gõ đúng tên server mới cho chạy
      adminOnly   chỉ role admin
      note        mô tả hậu quả, hiện trong hộp xác nhận
  */
  var ACTIONS = {
    app: [
      {
        id: 'drain',
        label: 'Ngừng nhận traffic',
        offAction: 'undrain',
        offLabel: 'Mở lại nhận traffic',
        activeWhen: { key: 'acceptingNew', value: false },
        note: 'Kết nối hiện có vẫn giữ nguyên; chỉ dừng nhận kết nối mới.'
      },
      {
        id: 'purge-cache',
        label: 'Xả cache & RAM',
        note: 'Giải phóng bộ nhớ đệm; vài yêu cầu đầu tiên có thể chậm hơn.'
      },
      {
        id: 'scale-out',
        label: 'Thêm node',
        note: 'Bật thêm một tiến trình cùng vai trò và đưa vào cụm cân bằng tải.'
      },
      {
        id: 'restart',
        label: 'Khởi động lại',
        typed: true,
        note: 'Toàn bộ phiên trên máy chủ này sẽ ngắt trong khoảng 8 giây.'
      }
    ],
    sfu: [
      {
        id: 'drain',
        label: 'Ngừng nhận peer mới',
        offAction: 'undrain',
        offLabel: 'Nhận peer trở lại',
        activeWhen: { key: 'acceptingNew', value: false },
        note: 'Peer đang kết nối không bị ngắt; chỉ chặn peer mới.'
      },
      {
        id: 'throttle-media',
        label: 'Hạ bitrate 720p',
        offAction: 'restore-media',
        offLabel: 'Khôi phục chất lượng',
        activeWhen: { key: 'mediaThrottled', value: true },
        note: 'Giảm khoảng 18% băng thông media, chất lượng video giảm.'
      },
      {
        id: 'restart',
        label: 'Khởi động lại SFU',
        typed: true,
        note: 'Mọi cuộc gọi đang chạy trên node này sẽ ngắt và phải kết nối lại.'
      }
    ],
    turn: [
      {
        id: 'failover',
        label: 'Chuyển relay dự phòng',
        offAction: 'failback',
        offLabel: 'Quay lại relay chính',
        activeWhen: { key: 'onStandby', value: true },
        typed: true,
        adminOnly: true,
        note: 'Toàn bộ lưu lượng relay chuyển sang máy chủ dự phòng.'
      },
      {
        id: 'restart',
        label: 'Khởi động lại relay',
        typed: true,
        note: 'Các phiên đang relay qua node này sẽ ngắt tạm thời.'
      }
    ],
    db: [
      { id: 'optimize', label: 'Tối ưu (VACUUM)', note: 'Thu gọn tệp dữ liệu; có thể khoá ghi trong vài giây.' },
      { id: 'integrity-check', label: 'Kiểm tra toàn vẹn', note: 'Quét toàn bộ bảng, không sửa dữ liệu.' },
      {
        id: 'switch-replica',
        label: 'Chuyển bản sao đọc',
        offAction: 'switch-primary',
        offLabel: 'Quay lại máy chính',
        activeWhen: { key: 'onReplica', value: true },
        typed: true,
        adminOnly: true,
        note: 'Chuyển truy vấn đọc sang bản sao; dữ liệu có thể trễ vài giây.'
      }
    ],
    ai: [
      {
        id: 'pause',
        label: 'Tạm dừng nhận job',
        offAction: 'resume',
        offLabel: 'Tiếp tục nhận job',
        activeWhen: { key: 'paused', value: true },
        note: 'Job mới xếp hàng chờ; kiểm duyệt và trợ lý AI tạm ngừng xử lý.'
      },
      { id: 'flush-queue', label: 'Xả hàng chờ', note: 'Xoá các job đang tắc để giải phóng hàng chờ.' }
    ],
    gateway: [
      { id: 'purge-cache', label: 'Xả cache biên', note: 'Toàn bộ nội dung đệm tại biên bị làm mới.' },
      {
        id: 'toggle-maintenance',
        label: 'Bật chế độ bảo trì',
        offAction: 'toggle-maintenance',
        offLabel: 'Tắt chế độ bảo trì',
        activeWhen: { key: 'maintenance', value: true },
        typed: true,
        adminOnly: true,
        note: 'Người dùng cuối thấy trang bảo trì; toàn bộ cổng quản trị vẫn truy cập được.'
      }
    ]
  };

  /* ------------------------------------------------------------------ *
   * 2. Tiện ích
   * ------------------------------------------------------------------ */

  function mk(tag, className, text) {
    var node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined && text !== null) node.textContent = String(text);
    return node;
  }

  function num(value) {
    return typeof value === 'number' && isFinite(value) ? value : null;
  }

  function fmtInt(value) {
    var n = num(value);
    if (n === null) return '—';
    return Math.round(n).toLocaleString('vi-VN');
  }

  function fmtOne(value) {
    var n = num(value);
    if (n === null) return '—';
    return n.toLocaleString('vi-VN', { minimumFractionDigits: 1, maximumFractionDigits: 1 });
  }

  function fmtPct(value) {
    var n = num(value);
    if (n === null) return '—';
    return fmtOne(n) + '%';
  }

  function fmtMb(value) {
    var n = num(value);
    if (n === null) return '—';
    if (n >= 1024) return fmtOne(n / 1024) + ' GB';
    return Math.round(n) + ' MB';
  }

  function fmtDuration(seconds) {
    var s = num(seconds);
    if (s === null) return '—';
    var d = Math.floor(s / 86400);
    var h = Math.floor((s % 86400) / 3600);
    var m = Math.floor((s % 3600) / 60);
    if (d > 0) return d + ' ngày ' + h + ' giờ';
    if (h > 0) return h + ' giờ ' + m + ' phút';
    return m + ' phút';
  }

  function fmtEta(seconds) {
    var s = num(seconds);
    if (s === null) return null;
    if (s <= 0) return 'đã chạm ngưỡng';
    if (s < 60) return 'khoảng ' + Math.max(1, Math.round(s)) + ' giây';
    var m = Math.floor(s / 60);
    var rem = Math.round(s % 60);
    if (m < 60) return 'khoảng ' + m + ' phút' + (rem ? ' ' + rem + ' giây' : '');
    return 'khoảng ' + Math.floor(m / 60) + ' giờ ' + (m % 60) + ' phút';
  }

  function levelOf(utilPct) {
    var u = num(utilPct);
    if (u === null) return 'unknown';
    if (u >= 88) return 'critical';
    if (u >= 75) return 'warning';
    if (u >= 60) return 'watch';
    return 'good';
  }

  function toneFor(level) {
    if (level === 'critical') return 'danger';
    if (level === 'warning') return 'warn';
    return '';
  }

  function showToast(message) {
    if (typeof window.toast === 'function') {
      try { window.toast(message); return; } catch (e) { /* rơi xuống dưới */ }
    }
    console.log('[ops-monitor]', message);
  }

  function appState() {
    // admin.js khai báo `const state = ...` ở phạm vi script, KHÔNG phải
    // window.state. Phải đọc bằng định danh trần; nếu không có thì mới thử window.
    try {
      if (typeof state !== 'undefined' && state) return state;
    } catch (e) { /* bỏ qua */ }
    try {
      if (typeof window !== 'undefined' && window.state) return window.state;
    } catch (e) { /* bỏ qua */ }
    return null;
  }

  function currentUser() {
    var s = appState();
    return s && s.user ? s.user : null;
  }

  function canUseAction(def, user) {
    if (!def.adminOnly) return true;
    return !!user && user.role === 'admin';
  }

  function canSeeDashboard(user) {
    if (!user) return false;
    return user.role === 'admin' || user.team === 'operations';
  }

  /* ------------------------------------------------------------------ *
   * 3. Gọi API
   * ------------------------------------------------------------------ */

  function fetchJson(url, options) {
    var opts = options || {};
    opts.cache = 'no-store';
    opts.credentials = 'same-origin';
    opts.headers = Object.assign({ Accept: 'application/json' }, opts.headers || {});
    if (opts.body) opts.headers['Content-Type'] = 'application/json';
    if (typeof AbortSignal !== 'undefined' && AbortSignal.timeout) {
      opts.signal = AbortSignal.timeout(10000);
    }
    return fetch(url, opts).then(function (response) {
      return response.json().catch(function () { return {}; }).then(function (body) {
        if (!response.ok) {
          var err = new Error(body.message || ('Máy chủ trả về ' + response.status));
          err.status = response.status;
          err.body = body;
          throw err;
        }
        return body;
      });
    });
  }

  function loadMetrics() {
    return fetchJson(ENDPOINT_METRICS);
  }

  function sendAction(serverId, action, confirmToken, reason) {
    return fetchJson(ENDPOINT_ACTION, {
      method: 'POST',
      body: JSON.stringify({
        serverId: serverId,
        action: action,
        confirmToken: confirmToken || null,
        params: reason ? { reason: reason } : {}
      })
    });
  }

  function loadAudit() {
    return fetchJson(ENDPOINT_AUDIT);
  }

  /* ------------------------------------------------------------------ *
   * 4. Hộp thoại xác nhận
   * ------------------------------------------------------------------ */

  function typedConfirm(server, actionLabel, note) {
    return new Promise(function (resolve) {
      if (typeof HTMLDialogElement === 'undefined') {
        var typed = window.prompt(
          actionLabel + ' — ' + server.name + '\n\n' + note +
          '\n\nGõ đúng mã máy chủ "' + server.id + '" để xác nhận:'
        );
        resolve(typed === server.id);
        return;
      }

      var dialog = mk('dialog');
      dialog.setAttribute('aria-labelledby', 'om-confirm-title');
      dialog.style.cssText = 'max-width:440px;width:calc(100% - 32px);border:1px solid var(--v2-line,#e4dff0);border-radius:14px;padding:0;background:var(--v2-surface,#fff);color:var(--v2-ink,#1d1729);';

      var form = mk('form');
      form.method = 'dialog';
      form.style.cssText = 'display:grid;gap:12px;padding:20px;';

      var title = mk('h4', null, actionLabel + ' — ' + server.name);
      title.id = 'om-confirm-title';
      title.style.cssText = 'margin:0;font-size:16px;font-weight:750;';

      var body = mk('p', null, note);
      body.style.cssText = 'margin:0;font-size:13px;line-height:1.55;color:var(--v2-ink-2,#4a3f5c);';

      var hint = mk('p');
      hint.style.cssText = 'margin:0;font-size:12.5px;color:var(--v2-ink-3,#655877);';
      hint.append(document.createTextNode('Gõ đúng mã '));
      var code = mk('b', null, server.id);
      code.style.cssText = 'font-family:ui-monospace,Consolas,monospace;';
      hint.append(code, document.createTextNode(' để xác nhận:'));

      var input = mk('input');
      input.type = 'text';
      input.autocomplete = 'off';
      input.spellcheck = false;
      input.setAttribute('aria-label', 'Mã máy chủ để xác nhận');
      input.style.cssText = 'width:100%;padding:10px 12px;font-size:14px;border:1.5px solid var(--v2-line-strong,#9a8fb0);border-radius:8px;background:var(--v2-surface,#fff);color:inherit;font-family:ui-monospace,Consolas,monospace;';

      var actions = mk('div');
      actions.style.cssText = 'display:flex;gap:8px;justify-content:flex-end;margin-top:4px;';

      var cancel = mk('button', null, 'Huỷ');
      cancel.type = 'button';
      cancel.style.cssText = 'min-height:42px;padding:9px 16px;border-radius:8px;border:1.5px solid var(--v2-line-strong,#9a8fb0);background:transparent;color:inherit;font-weight:650;font-size:13px;cursor:pointer;';

      var confirm = mk('button', null, 'Xác nhận');
      confirm.type = 'button';
      confirm.disabled = true;
      confirm.style.cssText = 'min-height:42px;padding:9px 16px;border-radius:8px;border:1.5px solid #a32020;background:#a32020;color:#fff;font-weight:700;font-size:13px;cursor:pointer;opacity:.45;';

      function sync() {
        var ok = input.value.trim() === server.id;
        confirm.disabled = !ok;
        confirm.style.opacity = ok ? '1' : '.45';
        confirm.style.cursor = ok ? 'pointer' : 'not-allowed';
      }

      input.addEventListener('input', sync);
      cancel.addEventListener('click', function () { dialog.close('cancel'); });
      confirm.addEventListener('click', function () { if (!confirm.disabled) dialog.close('ok'); });

      dialog.addEventListener('close', function () {
        var accepted = dialog.returnValue === 'ok';
        if (dialog.parentNode) dialog.parentNode.removeChild(dialog);
        resolve(accepted);
      });

      actions.append(cancel, confirm);
      form.append(title, body, hint, input, actions);
      dialog.append(form);
      document.body.append(dialog);
      dialog.showModal();
      setTimeout(function () { try { input.focus(); } catch (e) {} }, 30);
    });
  }

  /* ------------------------------------------------------------------ *
   * 5. Vẽ sparkline
   * ------------------------------------------------------------------ */

  function sparkline(series, level) {
    var svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('class', 'ops-mon-spark');
    svg.setAttribute('viewBox', '0 0 100 34');
    svg.setAttribute('preserveAspectRatio', 'none');
    svg.setAttribute('role', 'img');

    var values = Array.isArray(series) ? series.filter(function (v) { return typeof v === 'number' && isFinite(v); }) : [];
    if (values.length < 2) {
      svg.setAttribute('aria-label', 'Chưa đủ dữ liệu để vẽ xu hướng');
      return svg;
    }

    var color = level === 'critical' ? 'var(--om-danger)'
      : level === 'warning' ? 'var(--om-warn)'
      : level === 'watch' ? '#b98a12'
      : 'var(--om-good)';

    var min = Math.min.apply(null, values);
    var max = Math.max.apply(null, values);
    var span = max - min;

    var points = values.map(function (value, index) {
      var x = (index / (values.length - 1)) * 100;
      var y;
      if (span < 0.05) {
        var micro = Math.sin((index * 1.15) + (min * 0.7)) * 2.2;
        y = 20 - micro;
      } else {
        y = 26 - ((value - min) / span) * 18;
      }
      return [Math.round(x * 100) / 100, Math.round(y * 100) / 100];
    });

    var linePoints = points.map(function (p) { return p[0] + ',' + p[1]; }).join(' ');
    var areaPoints = '0,34 ' + linePoints + ' 100,34';

    var area = document.createElementNS('http://www.w3.org/2000/svg', 'polygon');
    area.setAttribute('class', 'om-spark-area');
    area.setAttribute('points', areaPoints);
    area.setAttribute('fill', color);
    svg.append(area);

    var line = document.createElementNS('http://www.w3.org/2000/svg', 'polyline');
    line.setAttribute('class', 'om-spark-line');
    line.setAttribute('points', linePoints);
    line.setAttribute('stroke', color);
    svg.append(line);

    svg.setAttribute('aria-label',
      'Xu hướng tải 60 giây: thấp nhất ' + fmtOne(min) + '%, cao nhất ' + fmtOne(max) +
      '%, hiện tại ' + fmtOne(values[values.length - 1]) + '%');
    return svg;
  }

  /* ------------------------------------------------------------------ *
   * 6. Vẽ các khối
   * ------------------------------------------------------------------ */

  function renderKpis(host, data) {
    var totals = data.totals || {};
    host.replaceChildren();

    var ccu = num(totals.ccu);
    var capacity = num(totals.capacityTotal);
    var loadPct = num(totals.avgUtilPct);
    var online = num(totals.serversOnline);
    var total = num(totals.serversTotal);

    var items = [
      {
        label: 'Người đang dùng',
        value: ccu === null ? '—' : fmtInt(ccu),
        note: capacity ? 'trên ' + fmtInt(capacity) + ' chỗ' : 'chưa rõ năng lực',
        tone: levelOf(loadPct) === 'critical' ? 'danger' : levelOf(loadPct) === 'warning' ? 'warn' : 'good'
      },
      {
        label: 'Phiên kết nối',
        value: num(totals.activeSessions) === null ? '—' : fmtInt(totals.activeSessions),
        note: ccu ? fmtOne(totals.activeSessions / Math.max(1, ccu)) + ' kết nối / người' : (totals.activeSessions ? totals.activeSessions + ' phiên quản trị đang mở' : 'chưa có kết nối nào'),
        tone: ''
      },
      {
        label: 'Tải trung bình',
        value: loadPct === null ? '—' : fmtOne(loadPct),
        suffix: loadPct === null ? '' : '%',
        note: loadPct === null ? 'chưa rõ' : (loadPct >= 88 ? 'vượt ngưỡng an toàn' : loadPct >= 75 ? 'tiến gần ngưỡng' : 'trong vùng an toàn'),
        tone: toneFor(levelOf(loadPct))
      },
      {
        label: 'Máy chủ trực tuyến',
        value: online === null ? '—' : fmtInt(online),
        suffix: total === null ? '' : '/' + fmtInt(total),
        note: online !== null && total !== null && online < total ? (total - online) + ' máy chủ cần xử lý' : 'tất cả đều phản hồi',
        tone: online !== null && total !== null && online < total ? 'danger' : 'good'
      }
    ];

    items.forEach(function (item) {
      var card = mk('div', 'ops-mon-kpi');
      if (item.tone) card.dataset.tone = item.tone;

      var label = mk('span', 'ops-mon-kpi-label', item.label);
      var value = mk('div', 'ops-mon-kpi-value', item.value);
      if (item.suffix) value.append(mk('small', null, item.suffix));
      var note = mk('span', 'ops-mon-kpi-note', item.note);

      card.append(label, value, note);
      host.append(card);
    });
  }

  function renderAlerts(host, data) {
    host.replaceChildren();
    var alerts = Array.isArray(data.alerts) ? data.alerts : [];

    if (!alerts.length) {
      var calm = mk('div', 'ops-mon-alert');
      calm.dataset.sev = 'good';
      var calmTag = mk('span', 'ops-mon-alert-tag', SEVERITY_LABEL.good);
      var calmBody = mk('div', 'ops-mon-alert-body');
      calmBody.append(
        mk('div', 'ops-mon-alert-title', 'Không có dấu hiệu quá tải trong 15 phút tới'),
        mk('div', 'ops-mon-alert-detail',
          'Mô hình dự báo đã kiểm tra ' + (Array.isArray(data.servers) ? data.servers.length : 0) +
          ' máy chủ và không thấy xu hướng tăng đáng kể.')
      );
      calm.append(calmTag, calmBody);
      host.append(calm);
      return;
    }

    alerts.forEach(function (alert) {
      var sev = ['watch', 'warning', 'critical', 'good'].indexOf(alert.severity) >= 0 ? alert.severity : 'watch';
      var card = mk('div', 'ops-mon-alert');
      card.dataset.sev = sev;

      var tag = mk('span', 'ops-mon-alert-tag', SEVERITY_LABEL[sev]);
      var body = mk('div', 'ops-mon-alert-body');

      var title = mk('div', 'ops-mon-alert-title', alert.title || 'Cảnh báo hệ thống');
      body.append(title);

      if (alert.detail) body.append(mk('div', 'ops-mon-alert-detail', alert.detail));

      var etaText = fmtEta(alert.etaSec);
      if (etaText) {
        var eta = mk('span', 'ops-mon-alert-eta', 'Dự báo: ' + etaText);
        var detailLine = mk('div', 'ops-mon-alert-detail');
        detailLine.append(eta);
        if (typeof alert.confidence === 'number') {
          detailLine.append(document.createTextNode(' · độ tin cậy ' + Math.round(alert.confidence * 100) + '%'));
        }
        body.append(detailLine);
      }

      if (alert.recommendation) {
        body.append(mk('div', 'ops-mon-alert-rec', alert.recommendation));
      }

      card.append(tag, body);
      host.append(card);
    });
  }

  function renderActionBar(server, user, onRun) {
    var defs = ACTIONS[server.role] || [];
    if (!defs.length) return null;

    var bar = mk('div', 'ops-mon-acts');
    var safe = mk('div', 'ops-mon-acts-safe');
    var risky = mk('div', 'ops-mon-acts-risky');

    defs.forEach(function (def) {
      var allowed = canUseAction(def, user);
      var active = def.activeWhen ? server[def.activeWhen.key] === def.activeWhen.value : false;
      var isDanger = !!def.typed;

      var btn = mk('button', isDanger ? 'ops-mon-act is-danger' : 'ops-mon-act',
        active ? def.offLabel : def.label);
      btn.type = 'button';
      btn.dataset.action = active ? (def.offAction || def.id) : def.id;
      btn.dataset.server = server.id;

      if (!allowed) {
        btn.disabled = true;
        btn.title = 'Chỉ Admin cấp cao được thực hiện thao tác này.';
      } else if (server.status === 'offline') {
        btn.disabled = true;
        btn.title = 'Máy chủ đang mất kết nối, không thể gửi lệnh.';
      } else {
        btn.addEventListener('click', function () { onRun(server, def, btn); });
      }

      (isDanger ? risky : safe).append(btn);
    });

    if (safe.childNodes.length) bar.append(safe);
    if (risky.childNodes.length) bar.append(risky);
    return bar;
  }

  function renderCards(host, data, user, onRun) {
    host.replaceChildren();
    var servers = Array.isArray(data.servers) ? data.servers : [];
    if (!servers.length) {
      host.append(mk('div', 'ops-mon-kpi-note', 'Chưa có máy chủ nào báo về.'));
      return;
    }

    servers.forEach(function (server) {
      var util = num(server.utilPct);
      var level = levelOf(util);

      var card = mk('article', 'ops-mon-card');
      card.dataset.server = server.id;
      if (server.status === 'offline') card.dataset.health = 'offline';
      else if (level === 'critical' || level === 'warning' || server.status === 'degraded') card.dataset.health = 'degraded';

      /* --- đầu thẻ --- */
      var head = mk('div', 'ops-mon-card-head');
      var nameBox = mk('div');
      var name = mk('h4', 'ops-mon-card-name', server.name || server.id);
      var meta = mk('p', 'ops-mon-card-meta',
        [server.id, server.region, server.role].filter(Boolean).join(' · '));
      nameBox.append(name, meta);

      var statusKey = server.status === 'offline' ? 'offline'
        : (level === 'critical' || level === 'warning' || server.status === 'degraded') ? 'degraded'
        : 'online';
      var status = mk('span', 'ops-mon-status', STATUS_LABEL[server.status] || server.status || '—');
      status.dataset.s = statusKey;

      head.append(nameBox, status);

      /* --- số người đang dùng --- */
      var users = mk('div', 'ops-mon-users');
      users.append(
        mk('b', null, num(server.activeUsers) === null ? '—' : fmtInt(server.activeUsers)),
        mk('span', null, '/ ' + (num(server.capacity) === null ? '—' : fmtInt(server.capacity)) + ' người')
      );

      /* --- sparkline --- */
      var spark = sparkline(server.series, level);

      /* --- thanh tải --- */
      var bar = mk('div', 'ops-mon-bar');
      bar.dataset.level = level;
      bar.setAttribute('role', 'progressbar');
      bar.setAttribute('aria-valuemin', '0');
      bar.setAttribute('aria-valuemax', '100');
      bar.setAttribute('aria-valuenow', util === null ? '0' : String(Math.round(util)));
      bar.setAttribute('aria-label', 'Mức sử dụng năng lực của ' + (server.name || server.id));
      var fill = mk('i');
      fill.style.width = (util === null ? 0 : Math.max(2, Math.min(100, util))) + '%';
      bar.append(fill);

      var barLabel = mk('div', 'ops-mon-bar-label');
      var headroom = num(server.headroomUsers);
      barLabel.append(
        mk('b', null, util === null ? 'Chưa rõ mức tải' : fmtPct(util) + ' năng lực'),
        mk('span', null, headroom === null ? '' : 'còn ' + fmtInt(headroom) + ' chỗ')
      );

      /* --- lưới thông số --- */
      var stats = mk('div', 'ops-mon-stats');

      function stat(label, value, tone) {
        var row = mk('div', 'ops-mon-stat');
        if (tone) row.dataset.tone = tone;
        row.append(mk('span', null, label), mk('b', null, value));
        stats.append(row);
      }

      var cpu = num(server.cpuPct);
      var memPct = num(server.memUsedMb) !== null && num(server.memTotalMb)
        ? (server.memUsedMb / server.memTotalMb) * 100 : null;

      stat('CPU', fmtPct(cpu), cpu >= 88 ? 'danger' : cpu >= 70 ? 'warn' : '');
      stat('RAM', memPct === null ? '—' : fmtPct(memPct) + ' · ' + fmtMb(server.memUsedMb),
        memPct >= 90 ? 'danger' : memPct >= 78 ? 'warn' : '');
      stat('Event loop', num(server.eventLoopLagMs) === null ? '—' : Math.round(server.eventLoopLagMs) + ' ms',
        server.eventLoopLagMs >= 120 ? 'danger' : server.eventLoopLagMs >= 50 ? 'warn' : '');
      stat('p95', num(server.p95Ms) === null ? '—' : Math.round(server.p95Ms) + ' ms',
        server.p95Ms >= 800 ? 'danger' : server.p95Ms >= 300 ? 'warn' : '');
      stat('Kết nối', fmtInt(server.conns));
      stat('Tải yêu cầu', num(server.rps) === null ? '—' : Math.round(server.rps) + ' req/s');
      stat('Tỉ lệ lỗi', num(server.errRate) === null ? '—' : fmtOne(server.errRate * 100) + '%',
        server.errRate >= 0.05 ? 'danger' : server.errRate >= 0.01 ? 'warn' : '');
      stat('Băng thông', (num(server.netInMbps) === null ? '—' : fmtOne(server.netInMbps) + ' ↓') +
        ' / ' + (num(server.netOutMbps) === null ? '—' : fmtOne(server.netOutMbps) + ' ↑'));
      stat('Ổ đĩa', num(server.diskPct) === null ? '—' : fmtPct(server.diskPct),
        server.diskPct >= 90 ? 'danger' : server.diskPct >= 75 ? 'warn' : '');
      stat('Hàng chờ', fmtInt(server.queueDepth),
        server.queueDepth >= 500 ? 'danger' : server.queueDepth >= 200 ? 'warn' : '');
      stat('Hoạt động liên tục', fmtDuration(server.uptimeSec));
      stat('Điểm sức khoẻ', num(server.healthScore) === null ? '—' : Math.round(server.healthScore) + '/100',
        server.healthScore < 60 ? 'danger' : server.healthScore < 80 ? 'warn' : '');

      card.append(head, users, spark, bar, barLabel, stats);

      var actions = renderActionBar(server, user, onRun);
      if (actions) card.append(actions);

      host.append(card);
    });
  }

  function renderTable(host, data) {
    host.replaceChildren();

    var wrap = mk('details', 'ops-mon-tablewrap');
    var summary = mk('summary', null,
      'Bảng thông số chi tiết · ' + (Array.isArray(data.servers) ? data.servers.length : 0) + ' máy chủ × 14 chỉ số');
    wrap.append(summary);

    var scroll = mk('div', 'ops-mon-scroll');
    var table = mk('table', 'ops-mon-table');

    var columns = [
      'Máy chủ', 'Vùng', 'Người dùng', 'Tải', 'CPU', 'RAM', 'Lag (ms)',
      'p95 (ms)', 'Kết nối', 'Req/s', 'Lỗi', '↓ Mbps', '↑ Mbps', 'Ổ đĩa', 'Uptime'
    ];

    var thead = mk('thead');
    var headRow = mk('tr');
    columns.forEach(function (label) { headRow.append(mk('th', null, label)); });
    thead.append(headRow);

    var tbody = mk('tbody');
    (data.servers || []).forEach(function (server) {
      var row = mk('tr');
      var util = num(server.utilPct);
      var level = levelOf(util);

      function cell(text, tone) {
        var td = mk('td', tone || null, text);
        return td;
      }

      var nameCell = mk('td');
      nameCell.append(mk('b', null, server.id));
      if (server.status !== 'online') {
        nameCell.append(mk('span', null, ' · ' + (STATUS_LABEL[server.status] || server.status)));
      }

      row.append(
        nameCell,
        cell(server.region || '—'),
        cell(num(server.activeUsers) === null ? '—' : fmtInt(server.activeUsers) + ' / ' + fmtInt(server.capacity)),
        cell(util === null ? '—' : fmtPct(util), level === 'critical' ? 'danger' : level === 'warning' ? 'warn' : level === 'watch' ? 'warn' : 'good'),
        cell(fmtPct(server.cpuPct), server.cpuPct >= 88 ? 'danger' : server.cpuPct >= 70 ? 'warn' : ''),
        cell(num(server.memUsedMb) === null ? '—' : fmtMb(server.memUsedMb) + ' / ' + fmtMb(server.memTotalMb)),
        cell(num(server.eventLoopLagMs) === null ? '—' : Math.round(server.eventLoopLagMs), server.eventLoopLagMs >= 120 ? 'danger' : server.eventLoopLagMs >= 50 ? 'warn' : ''),
        cell(num(server.p95Ms) === null ? '—' : Math.round(server.p95Ms), server.p95Ms >= 800 ? 'danger' : server.p95Ms >= 300 ? 'warn' : ''),
        cell(fmtInt(server.conns)),
        cell(num(server.rps) === null ? '—' : Math.round(server.rps)),
        cell(num(server.errRate) === null ? '—' : fmtOne(server.errRate * 100) + '%', server.errRate >= 0.05 ? 'danger' : server.errRate >= 0.01 ? 'warn' : ''),
        cell(num(server.netInMbps) === null ? '—' : fmtOne(server.netInMbps)),
        cell(num(server.netOutMbps) === null ? '—' : fmtOne(server.netOutMbps)),
        cell(fmtPct(server.diskPct), server.diskPct >= 90 ? 'danger' : server.diskPct >= 75 ? 'warn' : ''),
        cell(fmtDuration(server.uptimeSec))
      );
      tbody.append(row);
    });

    table.append(thead, tbody);
    scroll.append(table);
    wrap.append(scroll);
    host.append(wrap);
  }

  function renderAudit(host, entries) {
    host.replaceChildren();
    var wrap = mk('details', 'ops-mon-tablewrap');
    wrap.append(mk('summary', null, 'Nhật ký thao tác · ' + entries.length + ' lần gần nhất'));

    if (!entries.length) {
      var empty = mk('div');
      empty.style.cssText = 'padding:16px;font-size:12.5px;color:var(--om-ink-3);';
      empty.textContent = 'Chưa có thao tác nào được ghi nhận.';
      wrap.append(empty);
      host.append(wrap);
      return;
    }

    var scroll = mk('div', 'ops-mon-scroll');
    var table = mk('table', 'ops-mon-table');

    var thead = mk('thead');
    var headRow = mk('tr');
    ['Thời điểm', 'Người thực hiện', 'Máy chủ', 'Thao tác', 'Kết quả', 'Ghi chú'].forEach(function (label) {
      headRow.append(mk('th', null, label));
    });
    thead.append(headRow);

    var tbody = mk('tbody');
    entries.forEach(function (entry) {
      var row = mk('tr');
      var when = mk('td');
      when.style.textAlign = 'left';
      when.textContent = new Date(entry.ts).toLocaleString('vi-VN');

      var actor = mk('td');
      actor.style.textAlign = 'left';
      actor.textContent = entry.actor || '—';

      var target = mk('td');
      target.style.textAlign = 'left';
      target.textContent = entry.serverId || '—';

      var action = mk('td');
      action.style.textAlign = 'left';
      action.textContent = entry.action || '—';

      var result = mk('td', entry.result === 'ok' ? 'good' : 'danger');
      result.style.textAlign = 'left';
      result.textContent = entry.result === 'ok' ? 'Thành công' : entry.result === 'denied' ? 'Bị từ chối' : 'Thất bại';

      var note = mk('td');
      note.style.textAlign = 'left';
      note.textContent = entry.message || entry.reason || '';

      row.append(when, actor, target, action, result, note);
      tbody.append(row);
    });

    table.append(thead, tbody);
    scroll.append(table);
    wrap.append(scroll);
    host.append(wrap);
  }

  /* ------------------------------------------------------------------ *
   * 7. Khung chính
   * ------------------------------------------------------------------ */

  function buildShell() {
    var root = mk('section', 'ops-mon');
    root.id = 'ops-monitor';

    var head = mk('div', 'ops-mon-head');
    var headLeft = mk('div');
    var title = mk('h3', null, 'Giám sát hạ tầng thời gian thực');
    var sub = mk('p', 'ops-mon-sub',
      'Số người đang dùng, thông số từng máy chủ và dự báo quá tải. Cập nhật mỗi 5 giây.');
    headLeft.append(title, sub);

    var live = mk('span', 'ops-mon-live');
    live.dataset.state = 'live';
    live.setAttribute('role', 'status');
    live.setAttribute('aria-live', 'polite');
    var dot = mk('span', 'ops-mon-dot');
    var liveText = mk('span', null, 'Đang kết nối…');
    live.append(dot, liveText);

    head.append(headLeft, live);

    var kpis = mk('div', 'ops-mon-kpis');
    var alerts = mk('div', 'ops-mon-alerts');
    alerts.setAttribute('aria-live', 'polite');
    alerts.setAttribute('aria-atomic', 'false');

    var grid = mk('div', 'ops-mon-grid');
    var tableHost = mk('div');
    var auditHost = mk('div');

    root.append(head, kpis, alerts, grid, tableHost, auditHost);

    return {
      root: root,
      live: live,
      liveText: liveText,
      kpis: kpis,
      alerts: alerts,
      grid: grid,
      tableHost: tableHost,
      auditHost: auditHost
    };
  }

  function renderError(shell, message, onRetry) {
    shell.kpis.replaceChildren();
    shell.alerts.replaceChildren();
    shell.grid.replaceChildren();
    shell.tableHost.replaceChildren();
    shell.auditHost.replaceChildren();

    var box = mk('div', 'ops-mon-error');
    box.append(
      mk('strong', null, 'Không đọc được số liệu hạ tầng'),
      mk('span', null, message),
      mk('span', null, 'Dashboard không hiển thị số 0 thay cho dữ liệu thiếu — hãy thử lại.')
    );

    var retry = mk('button', null, 'Thử lại');
    retry.type = 'button';
    retry.addEventListener('click', onRetry);
    box.append(retry);

    shell.grid.append(box);
  }

  /* ------------------------------------------------------------------ *
   * 8. Vòng đời
   * ------------------------------------------------------------------ */

  var pollTimer = null;
  var activeShell = null;
  var lastGoodTs = null;
  var latest = null;
  var inFlight = false;

  function findLiveMount(content) {
    return document.getElementById('ops-live-mount') || (content && content.querySelector('#ops-live-mount')) || null;
  }

  function isLiveVisible(node) {
    if (!node || !node.isConnected) return false;
    return !node.closest('[hidden]');
  }

  function attach() {
    var content = document.getElementById('content');
    if (!content) return;

    var s = appState();
    var page = s ? s.page : null;
    if (page !== 'operations') return;

    var user = currentUser();
    if (!canSeeDashboard(user)) return;

    var mount = findLiveMount(content);
    var existing = document.getElementById('ops-monitor');
    if (existing) {
      if (mount && existing.parentElement !== mount) {
        mount.replaceChildren(existing);
      }
      return;
    }

    // Chờ trang operations dựng xong tab #ops-live-mount nếu đang hiện skeleton
    if (!mount && content.querySelector('.v2-skeleton-page')) return;

    var shell = buildShell();
    activeShell = shell;
    if (mount) mount.replaceChildren(shell.root);
    else content.prepend(shell.root);

    var skeleton = mk('div', 'ops-mon-skeleton');
    for (var i = 0; i < 3; i++) skeleton.append(mk('div'));
    shell.grid.append(skeleton);

    startPolling(shell);
  }

  function refresh(shell, force) {
    if (inFlight || !shell || !shell.root) return;
    if (!force && !isLiveVisible(shell.root)) {
      shell.live.dataset.state = 'stale';
      shell.liveText.textContent = 'Tạm dừng (tab đang ẩn)';
      return;
    }
    inFlight = true;

    loadMetrics().then(function (data) {
      latest = data;
      lastGoodTs = Date.now();

      shell.live.dataset.state = 'live';
      shell.liveText.textContent = 'Trực tiếp · ' + new Date().toLocaleTimeString('vi-VN');

      var user = currentUser();
      renderKpis(shell.kpis, data);
      renderAlerts(shell.alerts, data);
      renderCards(shell.grid, data, user, function (server, def, btn) {
        runAction(shell, server, def, btn);
      });
      renderTable(shell.tableHost, data);
      loadAudit().then(function (res) {
        renderAudit(shell.auditHost, Array.isArray(res.entries) ? res.entries : []);
      }).catch(function () {
        renderAudit(shell.auditHost, []);
      });
    }).catch(function (error) {
      if (latest) {
        // Đã từng có dữ liệu: giữ nguyên số cũ nhưng gắn nhãn.
        var age = Math.round((Date.now() - lastGoodTs) / 1000);
        shell.live.dataset.state = age > 60 ? 'dead' : 'stale';
        shell.liveText.textContent = age > 60
          ? 'Mất kết nối · ' + age + ' giây'
          : 'Số liệu cũ · ' + age + ' giây';
      } else {
        shell.live.dataset.state = 'dead';
        shell.liveText.textContent = 'Không kết nối được';
        renderError(shell, error.message || 'Lỗi mạng', function () {
          refresh(shell);
        });
      }
    }).then(function () {
      inFlight = false;
    });
  }

  var visibilityBound = false;

  function schedulePolling() {
    if (pollTimer) {
      clearInterval(pollTimer);
      pollTimer = null;
    }
    if (!activeShell || !activeShell.root || !activeShell.root.isConnected) return;
    var delay = document.hidden ? POLL_HIDDEN_MS : POLL_MS;
    pollTimer = setInterval(function () {
      if (!activeShell || !activeShell.root || !activeShell.root.isConnected) {
        clearInterval(pollTimer);
        pollTimer = null;
        return;
      }
      // Kể cả khi tab bị che khuất vẫn phải cập nhật số liệu; nếu không,
      // quay lại tab sẽ thấy dữ liệu cũ (ví dụ một server vừa hồi phục).
      refresh(activeShell);
    }, delay);
  }

  function startPolling(shell) {
    activeShell = shell;
    if (pollTimer) {
      clearInterval(pollTimer);
      pollTimer = null;
    }
    if (!activeShell || !activeShell.root || !activeShell.root.isConnected) return;
    refresh(activeShell);
    schedulePolling();

    if (!visibilityBound) {
      visibilityBound = true;
      document.addEventListener('visibilitychange', function () {
        if (!activeShell || !activeShell.root || !activeShell.root.isConnected) {
          if (pollTimer) {
            clearInterval(pollTimer);
            pollTimer = null;
          }
          return;
        }
        // Nhịp thay đổi theo trạng thái hiển thị; luôn dùng activeShell hiện tại
        // để tránh closure cũ làm hỏng polling sau khi re-mount.
        schedulePolling();
        if (!document.hidden) refresh(activeShell);
      });
    }
  }

  /* ------------------------------------------------------------------ *
   * 9. Thực thi thao tác
   * ------------------------------------------------------------------ */

  function runAction(shell, server, def, btn) {
    var active = def.activeWhen ? server[def.activeWhen.key] === def.activeWhen.value : false;
    var actionId = active ? def.offAction : def.id;
    var label = active ? def.offLabel : def.label;

    function execute(reason) {
      var originalText = btn.textContent;
      btn.disabled = true;
      btn.textContent = 'Đang chạy…';
      btn.style.opacity = '.6';

      sendAction(server.id, actionId, server.actionToken, reason).then(function (res) {
        showToast(res.message || ('Đã gửi lệnh "' + label + '" tới ' + server.id));
        refresh(shell);
      }).catch(function (error) {
        var message = error.status === 403
          ? 'Bạn không có quyền thực hiện thao tác này.'
          : error.status === 409
            ? 'Lệnh đã cũ hoặc đang được thực hiện. Dashboard vừa được làm mới, hãy thử lại.'
            : (error.message || 'Thao tác thất bại.');
        showToast('✕ ' + server.id + ': ' + message);
        refresh(shell);
      }).then(function () {
        btn.disabled = false;
        btn.textContent = originalText;
        btn.style.opacity = '';
      });
    }

    if (def.typed) {
      typedConfirm(server, label, def.note || '').then(function (ok) {
        if (ok) execute(label);
      });
      return;
    }

    execute(null);
  }

  /* ------------------------------------------------------------------ *
   * 10. Khởi động
   * ------------------------------------------------------------------ */

  function boot() {
    var observed = null;

    function onContentChanged() {
      var existing = document.getElementById('ops-monitor');
      if (existing) {
        var mount = findLiveMount(document.getElementById('content'));
        if (mount && existing.parentElement !== mount) mount.replaceChildren(existing);
        return;
      }
      if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
      activeShell = null;
      latest = null;
      lastGoodTs = null;
      attach();
    }

    var observer = new MutationObserver(onContentChanged);

    function retarget() {
      var content = document.getElementById('content');
      if (!content) return false;
      if (content === observed) return true;
      observer.disconnect();
      observer.observe(content, { childList: true });
      observed = content;
      return true;
    }

    window.__opsMonitorAttach = function () {
      attach();
      if (activeShell) refresh(activeShell, true);
    };

    retarget();
    attach();

    setInterval(function () {
      retarget();
      onContentChanged();
    }, 1000);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
