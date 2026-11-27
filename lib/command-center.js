const DESKS = {
  support: { title: 'Hỗ trợ khách hàng', detail: 'Báo cáo, nội dung và cấp mật khẩu', page: 'reports' },
  operations: { title: 'Kỹ thuật và hệ thống', detail: 'Máy chủ, live và hàng chờ AI', page: 'operations' },
  finance: { title: 'Tài chính và đối soát', detail: 'Sổ cái xu và đề nghị bù', page: 'finance' },
  admin: { title: 'Điều hành', detail: 'Nhân sự, an toàn và phiếu cấp cao', page: 'tickets' }
};

const emptyQueue = () => ({ open: 0, in_progress: 0, waiting: 0 });

export function readDesk(db) {
  const one = (sql, ...v) => db.prepare(sql).get(...v);
  const all = (sql, ...v) => db.prepare(sql).all(...v);
  const safe = (fn, fallback) => { try { return fn(); } catch { return fallback; } };
  const departments = { admin: emptyQueue(), support: emptyQueue(), operations: emptyQueue(), finance: emptyQueue() };
  for (const row of safe(() => all("SELECT team, status, count(*) n FROM console_tickets WHERE status!='resolved' GROUP BY team, status"), [])) {
    const queue = departments[row.team];
    if (queue && queue[row.status] !== undefined) queue[row.status] = row.n;
  }
  const staff = { support: 0, operations: 0, finance: 0 };
  for (const row of safe(() => all('SELECT team, count(*) n FROM console_staff WHERE suspended=0 GROUP BY team'), [])) {
    if (staff[row.team] !== undefined) staff[row.team] = row.n;
  }
  const now = Date.now();
  return {
    departments,
    staff,
    visitors: {
      online: safe(() => one('SELECT count(*) n FROM users WHERE last_active>? AND suspended=0', now - 90000).n, 0),
      sessions: safe(() => one('SELECT count(*) n FROM sessions WHERE expires>?', now).n, 0),
      members: safe(() => one("SELECT count(*) n FROM users WHERE role='user'").n, 0),
      suspended: safe(() => one('SELECT count(*) n FROM users WHERE suspended=1').n, 0)
    },
    care: {
      reports: safe(() => one("SELECT count(*) n FROM reports WHERE status='open'").n, 0),
      resets: safe(() => one("SELECT count(*) n FROM password_resets WHERE status='open'").n, 0)
    },
    finance: {
      pending: safe(() => one("SELECT count(*) n FROM console_wallet_operations WHERE state='pending'").n, 0),
      entries: safe(() => one('SELECT count(*) n FROM wallet_entries').n, 0)
    }
  };
}

export function assessLoad({ pc = {}, cloud = {} } = {}) {
  const reasons = [];
  let level = 'ok';
  const bump = (next, reason) => {
    reasons.push(reason);
    if (next === 'overload' || (next === 'watch' && level === 'ok')) level = next;
  };
  if (pc.status === 'unreachable') bump('overload', 'Máy chủ app không phản hồi.');
  else if (pc.status === 'unhealthy') bump('watch', 'Máy chủ app chưa đạt kiểm tra.');
  if (pc.maintenance) bump('watch', 'App đang ở chế độ bảo trì.');
  if (Number(pc.memoryMb) >= 1200) bump('overload', `RAM máy app ${pc.memoryMb} MB.`);
  else if (Number(pc.memoryMb) >= 800) bump('watch', `RAM máy app ${pc.memoryMb} MB.`);
  if (Number(pc.heapTotalMb) > 0 && Number(pc.heapUsedMb) / Number(pc.heapTotalMb) >= 0.92) bump('overload', 'Bộ nhớ heap của Node gần đầy.');
  const queue = Number(pc.aiQueue ?? cloud.aiQueue ?? 0);
  if (queue >= 30) bump('overload', `Hàng chờ AI đang ${queue} việc.`);
  else if (queue >= 12) bump('watch', `Hàng chờ AI đang ${queue} việc.`);
  if (Number(pc.sockets) >= 1500) bump('watch', `${pc.sockets} kết nối thời gian thực.`);
  if (pc.sfu?.configured && pc.sfu.ready === false) bump('watch', 'SFU live chưa sẵn sàng.');
  if (Number(cloud.replicaAgeMs) > 180000) bump('watch', 'Bản đồng bộ cloud cũ hơn 3 phút.');
  const title = level === 'overload' ? 'Quá tải' : level === 'watch' ? 'Cần theo dõi' : 'Ổn định';
  const summary = reasons.length ? reasons.join(' ') : 'Máy app và cloud quản trị đang trong ngưỡng an toàn.';
  return { level, title, summary };
}

export function presentCommand({ me, desk, pc, cloud, generatedAt = Date.now() }) {
  const team = me.role === 'admin' ? 'admin' : (me.team || 'support');
  const infra = team === 'admin' || team === 'operations';
  const load = assessLoad({ pc, cloud });
  return {
    generatedAt,
    actor: team,
    load: infra ? load : { level: load.level, title: load.title, summary: load.level === 'ok' ? 'Hệ thống đang ổn định.' : 'Kỹ thuật đang theo dõi tải máy chủ.' },
    visitors: infra ? desk.visitors : null,
    pc: infra ? pc : null,
    cloud: infra ? cloud : null,
    care: team === 'admin' || team === 'support' ? desk.care : null,
    finance: team === 'admin' || team === 'finance' ? desk.finance : null,
    desks: ['support', 'operations', 'finance', 'admin'].map(id => ({
      id,
      title: DESKS[id].title,
      detail: DESKS[id].detail,
      page: DESKS[id].page,
      open: desk.departments[id].open,
      inProgress: desk.departments[id].in_progress,
      waiting: desk.departments[id].waiting,
      staff: id === 'admin' ? null : desk.staff[id] || 0,
      operable: team === 'admin' || team === id
    }))
  };
}
