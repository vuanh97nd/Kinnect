import { randomUUID } from 'node:crypto';

const TEAMS = new Set(['admin', 'support', 'operations', 'finance']);
const STAFF_TEAMS = new Set(['support', 'operations', 'finance']);
const PRIORITIES = new Set(['low', 'normal', 'high', 'urgent']);
const STATUSES = new Set(['open', 'in_progress', 'waiting', 'resolved']);
const fail = (status, message) => { const error = new Error(message); error.status = status; throw error; };
function text(value, name, max, required = false) {
  if (value === undefined || value === null) { if (required) fail(400, `Thiếu ${name}.`); return ''; }
  if (typeof value !== 'string' || value.length > max) fail(400, `${name} không hợp lệ.`);
  const result = value.trim();
  if (required && !result) fail(400, `Thiếu ${name}.`);
  return result;
}

/** Shared case queue. Caller supplies a freshly authenticated console principal. */
export function createConsoleTickets(db) {
  db.exec(`CREATE TABLE IF NOT EXISTS console_tickets(
    id TEXT PRIMARY KEY, subject TEXT NOT NULL, description TEXT NOT NULL,
    priority TEXT NOT NULL, team TEXT NOT NULL, member TEXT NOT NULL DEFAULT '',
    assignee TEXT, status TEXT NOT NULL DEFAULT 'open', version INTEGER NOT NULL DEFAULT 1,
    created_by TEXT NOT NULL, created INTEGER NOT NULL, updated INTEGER NOT NULL
  );
  CREATE TABLE IF NOT EXISTS console_ticket_teams(
    ticket_id TEXT NOT NULL REFERENCES console_tickets(id), team TEXT NOT NULL,
    PRIMARY KEY(ticket_id,team)
  );
  CREATE TABLE IF NOT EXISTS console_ticket_events(
    id TEXT PRIMARY KEY, ticket_id TEXT NOT NULL REFERENCES console_tickets(id),
    actor TEXT NOT NULL, actor_name TEXT NOT NULL, actor_team TEXT NOT NULL,
    action TEXT NOT NULL, message TEXT NOT NULL DEFAULT '',
    before_json TEXT, after_json TEXT NOT NULL, created INTEGER NOT NULL
  );
  CREATE INDEX IF NOT EXISTS console_tickets_updated ON console_tickets(updated DESC);
  CREATE INDEX IF NOT EXISTS console_ticket_events_ticket ON console_ticket_events(ticket_id,created);
  CREATE TRIGGER IF NOT EXISTS console_ticket_events_immutable_update
    BEFORE UPDATE ON console_ticket_events BEGIN SELECT RAISE(ABORT,'Ticket events are immutable'); END;
  CREATE TRIGGER IF NOT EXISTS console_ticket_events_immutable_delete
    BEFORE DELETE ON console_ticket_events BEGIN SELECT RAISE(ABORT,'Ticket events are immutable'); END;`);
  const one = (sql, ...args) => db.prepare(sql).get(...args);
  const all = (sql, ...args) => db.prepare(sql).all(...args);
  const run = (sql, ...args) => db.prepare(sql).run(...args);
  const current = id => one('SELECT * FROM console_tickets WHERE id=?', id);
  const actorTeam = me => me.role === 'admin' ? 'admin' : me.team;
  const validPrincipal = me => {
    if (!me || !me.id || !me.username || !(me.role === 'admin' || me.role === 'support' && STAFF_TEAMS.has(me.team))) fail(403, 'Không có quyền truy cập phiếu phối hợp.');
  };
  const visible = (ticket, me) => ticket && (me.role === 'admin' || !!one('SELECT 1 FROM console_ticket_teams WHERE ticket_id=? AND team=?', ticket.id, me.team));
  const requireTicket = (id, me) => { const ticket = current(id); if (!visible(ticket, me)) fail(404, 'Không tìm thấy phiếu phối hợp.'); return ticket; };
  const display = ticket => ({ ...ticket,
    assigneeUsername: ticket.assignee ? one('SELECT username FROM console_staff WHERE id=?', ticket.assignee)?.username || null : null,
    participantTeams: all('SELECT team FROM console_ticket_teams WHERE ticket_id=? ORDER BY team', ticket.id).map(row => row.team),
  });
  const validateAssignee = (id, team) => {
    if (id === null || id === undefined || id === '') return null;
    if (typeof id !== 'string' || id.length > 100) fail(400, 'Nhân viên được phân công không hợp lệ.');
    const staff = one('SELECT id,team,suspended FROM console_staff WHERE id=?', id);
    if (!staff || staff.suspended || staff.team !== team || team === 'admin') fail(400, 'Chỉ phân công cho nhân viên đang hoạt động thuộc nhóm phụ trách.');
    return id;
  };
  const event = (ticket, me, action, message, before = null) => run(
    'INSERT INTO console_ticket_events VALUES(?,?,?,?,?,?,?,?,?,?)',
    randomUUID(), ticket.id, me.username, String(me.name || me.username), actorTeam(me), action, message,
    before ? JSON.stringify(before) : null, JSON.stringify(ticket), Date.now(),
  );
  function transaction(fn) {
    db.exec('BEGIN IMMEDIATE');
    try { const result = fn(); db.exec('COMMIT'); return result; }
    catch (error) { db.exec('ROLLBACK'); throw error; }
  }
  return function handle({ me, method, path, url = new URL('http://localhost'), body = {} }) {
    if (path !== '/tickets' && !path.startsWith('/tickets/')) return null;
    validPrincipal(me);
    if (!body || typeof body !== 'object' || Array.isArray(body)) fail(400, 'Dữ liệu phiếu không hợp lệ.');
    if (path === '/tickets' && method === 'GET') {
      const params = typeof url === 'string' ? new URL(url, 'http://localhost').searchParams : url.searchParams;
      const state = params.get('state') || 'all', q = text(params.get('q'), 'Từ khóa', 100);
      if (state !== 'all' && !STATUSES.has(state)) fail(400, 'Bộ lọc trạng thái không hợp lệ.');
      const visibility = me.role === 'admin' ? '1=1' : 'EXISTS(SELECT 1 FROM console_ticket_teams p WHERE p.ticket_id=t.id AND p.team=?)';
      const visibleArgs = me.role === 'admin' ? [] : [me.team];
      const counts = all('SELECT status,count(*) AS n FROM console_tickets t WHERE ' + visibility + ' GROUP BY status', ...visibleArgs);
      const summary = { total: 0, open: 0, in_progress: 0, waiting: 0, resolved: 0 };
      for (const row of counts) { summary[row.status] = row.n; summary.total += row.n; }
      const filter = visibility + (state === 'all' ? '' : ' AND t.status=?') + (q ? " AND instr(lower(t.subject || ' ' || t.description || ' ' || t.member),lower(?))>0" : '');
      const args = [...visibleArgs, ...(state === 'all' ? [] : [state]), ...(q ? [q] : [])];
      const tickets = all(`SELECT t.* FROM console_tickets t WHERE ${filter}
        ORDER BY CASE t.status WHEN 'resolved' THEN 1 ELSE 0 END,
        CASE t.priority WHEN 'urgent' THEN 0 WHEN 'high' THEN 1 WHEN 'normal' THEN 2 ELSE 3 END,
        t.updated DESC,t.rowid DESC LIMIT 100`, ...args).map(display);
      const total = one('SELECT count(*) AS n FROM console_tickets t WHERE ' + filter, ...args).n;
      return { tickets, summary, total };
    }
    if (path === '/tickets' && method === 'POST') {
      const subject = text(body.subject, 'Tiêu đề', 180, true), description = text(body.description, 'Mô tả', 6000, true);
      const priority = body.priority || 'normal', team = body.team || actorTeam(me), member = text(body.member, 'Thành viên liên quan', 100);
      if (!PRIORITIES.has(priority) || !TEAMS.has(team)) fail(400, 'Nhóm hoặc mức ưu tiên không hợp lệ.');
      if (me.role !== 'admin' && body.assignee) fail(403, 'Chỉ admin phân công nhân viên cụ thể.');
      const assignee = validateAssignee(body.assignee, team), now = Date.now(), id = randomUUID();
      return transaction(() => {
        run('INSERT INTO console_tickets VALUES(?,?,?,?,?,?,?,?,?,?,?,?)', id, subject, description, priority, team, member, assignee, 'open', 1, me.username, now, now);
        run('INSERT INTO console_ticket_teams VALUES(?,?)', id, actorTeam(me));
        run('INSERT OR IGNORE INTO console_ticket_teams VALUES(?,?)', id, team);
        const ticket = current(id); event(ticket, me, 'create', description);
        return { ticket: display(ticket) };
      });
    }
    const match = /^\/tickets\/([a-f0-9-]{36})(\/events)?$/.exec(path);
    if (!match) fail(404, 'Không tìm thấy phiếu phối hợp.');
    const [, id, suffix] = match;
    if (!suffix && method === 'GET') {
      const ticket = requireTicket(id, me);
      const eventTotal = one('SELECT count(*) AS n FROM console_ticket_events WHERE ticket_id=?', id).n;
      const events = all('SELECT * FROM (SELECT rowid AS event_order,* FROM console_ticket_events WHERE ticket_id=? ORDER BY created DESC,rowid DESC LIMIT 200) ORDER BY created,event_order', id).map(({ before_json, after_json, event_order, ...row }) => ({ ...row, before: before_json ? JSON.parse(before_json) : null, after: JSON.parse(after_json) }));
      return { ticket: display(ticket), events, eventTotal };
    }
    if (suffix === '/events' && method === 'POST') {
      if (!Number.isSafeInteger(body.version) || body.version < 1) fail(400, 'Thiếu phiên bản phiếu hợp lệ.');
      const action = body.action, message = text(body.message, 'Nội dung trao đổi', 4000, action === 'note');
      if (!['note', 'transfer', 'status', 'assign', 'process'].includes(action)) fail(400, 'Thao tác phiếu không hợp lệ.');
      return transaction(() => {
        const before = requireTicket(id, me);
        if (before.version !== body.version) fail(409, 'Phiếu đã được cập nhật. Hãy tải lại trước khi thao tác.');
        const next = { ...before };
        if (action === 'transfer') {
          if (before.status === 'resolved') fail(409, 'Admin cần mở lại phiếu trước khi bàn giao.');
          if (!TEAMS.has(body.team) || body.team === before.team) fail(400, 'Chọn nhóm tiếp nhận khác nhóm hiện tại.');
          if (!message) fail(400, 'Nhập lý do bàn giao.');
          if (me.role !== 'admin' && body.assignee) fail(403, 'Chỉ admin phân công nhân viên cụ thể.');
          next.team = body.team; next.assignee = validateAssignee(body.assignee, body.team); next.status = 'open';
          run('INSERT OR IGNORE INTO console_ticket_teams VALUES(?,?)', id, body.team);
        }
        if (action === 'status') {
          if (!STATUSES.has(body.status) || body.status === before.status) fail(400, 'Chọn trạng thái mới hợp lệ.');
          if (before.status === 'resolved' && me.role !== 'admin') fail(403, 'Chỉ admin được mở lại phiếu đã hoàn tất.');
          next.status = body.status;
        }
        if (action === 'assign') {
          if (me.role !== 'admin') fail(403, 'Chỉ admin phân công nhân viên cụ thể.');
          if (!Object.hasOwn(body, 'assignee')) fail(400, 'Chọn nhân viên hoặc bỏ phân công.');
          if (before.team === 'admin' && body.assignee) {
            const staff = one('SELECT id,team,suspended FROM console_staff WHERE id=?', body.assignee);
            if (!staff || staff.suspended) fail(400, 'Chỉ phân công cho nhân viên đang hoạt động thuộc nhóm phụ trách.');
            next.team = staff.team;
            next.assignee = staff.id;
            run('INSERT OR IGNORE INTO console_ticket_teams VALUES(?,?)', id, staff.team);
          } else {
            next.assignee = validateAssignee(body.assignee, before.team);
          }
          if (next.assignee === before.assignee && next.team === before.team) fail(400, 'Phân công không thay đổi.');
        }
        if (action === 'process') {
          if (body.priority && PRIORITIES.has(body.priority)) next.priority = body.priority;
          if (body.status && STATUSES.has(body.status)) {
            if (before.status === 'resolved' && body.status !== 'resolved' && me.role !== 'admin') fail(403, 'Chỉ admin được mở lại phiếu đã hoàn tất.');
            next.status = body.status;
          }
          if (body.team && TEAMS.has(body.team) && body.team !== before.team) {
            if (before.status === 'resolved' && next.status === 'resolved' && me.role !== 'admin') fail(409, 'Admin cần mở lại phiếu trước khi bàn giao.');
            next.team = body.team;
            run('INSERT OR IGNORE INTO console_ticket_teams VALUES(?,?)', id, body.team);
            if (next.team === 'admin') next.assignee = null;
          }
          if (Object.hasOwn(body, 'assignee')) {
            if (!body.assignee) {
              if (me.role !== 'admin' && before.assignee) fail(403, 'Chỉ admin phân công nhân viên cụ thể.');
              next.assignee = null;
            } else if (body.assignee !== before.assignee) {
              if (me.role !== 'admin') fail(403, 'Chỉ admin phân công nhân viên cụ thể.');
              const staff = one('SELECT id,team,suspended FROM console_staff WHERE id=?', body.assignee);
              if (!staff || staff.suspended) fail(400, 'Nhân viên được phân công không hợp lệ hoặc đang bị đình chỉ.');
              next.assignee = staff.id;
              if (next.team !== staff.team) {
                next.team = staff.team;
                run('INSERT OR IGNORE INTO console_ticket_teams VALUES(?,?)', id, staff.team);
              }
            }
          }
          const changed = next.status !== before.status || next.team !== before.team || next.assignee !== before.assignee || next.priority !== before.priority;
          if (!changed && !message) fail(400, 'Nhập nội dung phản hồi hoặc chọn thay đổi trạng thái / bộ phận / nhân sự.');
        }
        next.version++; next.updated = Date.now();
        const result = run('UPDATE console_tickets SET priority=?,team=?,assignee=?,status=?,version=?,updated=? WHERE id=? AND version=?', next.priority, next.team, next.assignee, next.status, next.version, next.updated, id, before.version);
        if (result.changes !== 1) fail(409, 'Phiếu đã được cập nhật. Hãy tải lại.');
        event(next, me, action, message, before);
        return { ticket: display(next) };
      });
    }
    fail(405, 'Phương thức không hỗ trợ cho phiếu phối hợp.');
  };
}
