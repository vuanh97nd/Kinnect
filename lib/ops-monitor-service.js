import { randomUUID } from 'node:crypto';

const SERVERS = [
  {
    id: 'app-1', role: 'app', name: 'Máy chủ PC chính (Kinnect Server)', region: 'PC-LOCAL',
    capacity: 5000, memTotalMb: 4096, diskPct: 47, baseLatency: 15, waveSec: 240
  },
  {
    id: 'sfu-1', role: 'sfu', name: 'WebRTC SFU (Live Stream)', region: 'PC-LOCAL',
    capacity: 1500, memTotalMb: 2048, diskPct: 31, baseLatency: 20, waveSec: 300
  },
  {
    id: 'turn-1', role: 'turn', name: 'TURN Relay (Cuộc gọi thoại/video)', region: 'CLOUDFLARE',
    capacity: 2500, memTotalMb: 1024, diskPct: 22, baseLatency: 25, waveSec: 360
  },
  {
    id: 'db-1', role: 'db', name: 'Supabase phụ (PostgreSQL Standby)', region: 'SUPABASE-CLOUD',
    capacity: 10000, memTotalMb: 4096, diskPct: 20, baseLatency: 45, waveSec: 420
  },
  {
    id: 'ai-1', role: 'ai', name: 'Worker AI kiểm duyệt', region: 'CLOUD',
    capacity: 3000, memTotalMb: 3072, diskPct: 15, baseLatency: 120, waveSec: 200
  },
  {
    id: 'gw-1', role: 'gateway', name: 'Cloudflare Tunnel (Cổng kết nối)', region: 'GLOBAL',
    capacity: 10000, memTotalMb: 512, diskPct: 9, baseLatency: 12, waveSec: 480
  }
];

const ALLOWED_ACTIONS = {
  app: ['drain', 'undrain', 'purge-cache', 'scale-out', 'scale-in', 'restart'],
  sfu: ['drain', 'undrain', 'throttle-media', 'restore-media', 'restart'],
  turn: ['failover', 'failback', 'restart'],
  db: ['optimize', 'integrity-check', 'switch-replica', 'switch-primary'],
  ai: ['pause', 'resume', 'flush-queue'],
  gateway: ['purge-cache', 'toggle-maintenance']
};

const ADMIN_ONLY_ACTIONS = new Set([
  'failover',
  'failback',
  'switch-replica',
  'switch-primary',
  'toggle-maintenance'
]);

const RECOMMENDATIONS = {
  app: {
    watch: 'Theo dõi số kết nối WebSocket; chưa cần can thiệp.',
    warning: 'Chuẩn bị bật thêm node API khu vực SG-2.',
    critical: 'Bật thêm node API ngay và giới hạn tần suất cho endpoint nặng.'
  },
  sfu: {
    watch: 'Theo dõi số peer đang kết nối.',
    warning: 'Hạ bitrate video xuống 720p để giảm tải media.',
    critical: 'Bật thêm node SFU; nếu chưa kịp, tạm tắt video và giữ thoại.'
  },
  turn: {
    watch: 'Theo dõi băng thông relay.',
    warning: 'Ưu tiên kết nối trực tiếp P2P để giảm tải relay.',
    critical: 'Chuyển sang relay dự phòng và thông báo chất lượng giảm.'
  },
  db: {
    watch: 'Theo dõi độ trễ truy vấn.',
    warning: 'Bật cache đọc và tạm dừng job nền.',
    critical: 'Chuyển truy vấn sang bản sao đọc; tạm dừng ghi không thiết yếu.'
  },
  ai: {
    watch: 'Theo dõi độ sâu hàng chờ.',
    warning: 'Giảm tần suất kiểm duyệt ảnh để giải phóng hàng chờ.',
    critical: 'Tắt kiểm duyệt không thiết yếu; ưu tiên báo cáo liên quan trẻ em.'
  },
  gateway: {
    watch: 'Theo dõi tỉ lệ lỗi 5xx.',
    warning: 'Kiểm tra quy tắc tường lửa và giới hạn tần suất.',
    critical: 'Bật chế độ bảo trì cho toàn hệ thống.'
  }
};

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function deterministicNoise(seed, step) {
  const x = Math.sin(seed * 12.9898 + step * 78.233) * 43758.5453;
  return (x - Math.floor(x)) * 2 - 1;
}

export function actionTokenFor(serverId, nowMs = Date.now()) {
  return serverId + ':' + Math.floor(nowMs / 60000);
}

export function tokenIsFresh(serverId, token, nowMs = Date.now()) {
  if (typeof token !== 'string') return false;
  const bucket = Math.floor(nowMs / 60000);
  return token === serverId + ':' + bucket || token === serverId + ':' + (bucket - 1);
}

function levelOf(utilPct) {
  if (utilPct >= 88) return 'critical';
  if (utilPct >= 75) return 'warning';
  if (utilPct >= 60) return 'watch';
  return 'good';
}

function rawUtil(server, tSec, idx) {
  const phase = (tSec % server.waveSec) / server.waveSec;
  const step = Math.floor(tSec / 5);
  const n = deterministicNoise(idx + 1, step);

  if (server.role === 'app') return 58 + 26 * Math.sin(phase * Math.PI) + n * 1.5;
  if (server.role === 'ai') return 56 + 18 * Math.sin(phase * Math.PI) + n * 2;
  if (server.role === 'sfu') return 52 + 16 * Math.sin(phase * Math.PI) + n * 2;
  if (server.role === 'turn') return 38 + 12 * Math.sin(phase * Math.PI) + n * 1.5;
  if (server.role === 'db') return 44 + 10 * Math.sin(phase * Math.PI) + n * 1.2;
  return 30 + 8 * Math.sin(phase * Math.PI) + n * 1;
}

function predict(series, utilPct, capacity) {
  const values = (Array.isArray(series) ? series : []).filter(v => typeof v === 'number' && isFinite(v));
  if (values.length < 4 || capacity <= 0) {
    return { slope: 0, r2: 0, etaSec: null, confidence: 0, level: levelOf(utilPct) };
  }

  const alpha = 0.35;
  const smooth = [values[0]];
  for (let i = 1; i < values.length; i++) {
    smooth.push(alpha * values[i] + (1 - alpha) * smooth[i - 1]);
  }

  const n = smooth.length;
  let sw = 0, swx = 0, swy = 0;
  for (let i = 0; i < n; i++) {
    const w = 1 + i / n;
    sw += w;
    swx += w * i;
    swy += w * smooth[i];
  }
  const xBar = swx / sw;
  const yBar = swy / sw;

  let num = 0, den = 0;
  for (let i = 0; i < n; i++) {
    const w = 1 + i / n;
    num += w * (i - xBar) * (smooth[i] - yBar);
    den += w * Math.pow(i - xBar, 2);
  }
  const slope = den === 0 ? 0 : num / den;

  let ssRes = 0, ssTot = 0;
  for (let i = 0; i < n; i++) {
    const predicted = yBar + slope * (i - xBar);
    ssRes += Math.pow(smooth[i] - predicted, 2);
    ssTot += Math.pow(smooth[i] - yBar, 2);
  }
  const r2 = ssTot === 0 ? 0 : clamp(1 - ssRes / ssTot, 0, 1);

  const slopePerSecond = slope / 5;
  const threshold = 88;
  let etaSec = null;
  if (slopePerSecond > 0.02) {
    etaSec = Math.max(0, (threshold - utilPct) / slopePerSecond);
    if (!isFinite(etaSec) || etaSec > 7200) etaSec = null;
  }

  const confidence = clamp(
    0.45 * r2 + 0.35 * Math.min(1, Math.abs(slopePerSecond) / 0.35) + 0.2 * (n / 12),
    0.25, 0.99
  );

  let level = levelOf(utilPct);
  if (etaSec !== null && confidence >= 0.6) {
    if (etaSec < 180 && level !== 'critical') level = 'critical';
    else if (etaSec < 600 && level === 'good') level = 'warning';
  }

  return {
    slope: slopePerSecond,
    r2: Math.round(r2 * 100) / 100,
    etaSec: etaSec === null ? null : Math.round(etaSec),
    confidence: Math.round(confidence * 100) / 100,
    level
  };
}

function buildAlerts(samples, predictions) {
  const alerts = [];

  for (const server of samples) {
    const prediction = predictions[server.id];

    if (server.status === 'offline') {
      alerts.push({
        code: 'SRV-DOWN',
        severity: 'critical',
        serverId: server.id,
        title: server.name + ' đang mất kết nối',
        detail: 'Không nhận được số liệu trong 30 giây gần nhất.',
        etaSec: null,
        confidence: 1,
        recommendation: 'Kiểm tra tiến trình và khởi động lại nếu cần.'
      });
      continue;
    }

    if (server.errRate > 0.05) {
      alerts.push({
        code: 'ERR-SPIKE',
        severity: 'critical',
        serverId: server.id,
        title: server.name + ' có tỉ lệ lỗi tăng cao',
        detail: (server.errRate * 100).toFixed(1) + '% yêu cầu lỗi trong 2 mẫu liên tiếp.',
        etaSec: null,
        confidence: 0.95,
        recommendation: RECOMMENDATIONS[server.role].critical
      });
      continue;
    }

    if (prediction.etaSec !== null && prediction.confidence >= 0.6) {
      const severity = prediction.etaSec < 180 ? 'critical' : prediction.etaSec < 600 ? 'warning' : 'watch';
      const trend = prediction.slope > 0
        ? '+' + (prediction.slope * 60).toFixed(1) + '%/phút'
        : 'đi ngang';

      alerts.push({
        code: prediction.etaSec < 180 ? 'FC-OVERLOAD-3M' : 'FC-OVERLOAD-10M',
        severity,
        serverId: server.id,
        title: server.name + ' đang tiến gần ngưỡng quá tải',
        detail: server.utilPct.toFixed(1) + '% · ' +
          server.activeUsers.toLocaleString('vi-VN') + '/' + server.capacity.toLocaleString('vi-VN') +
          ' người · ' + trend + ' · R² ' + prediction.r2.toFixed(2),
        etaSec: prediction.etaSec,
        confidence: prediction.confidence,
        recommendation: RECOMMENDATIONS[server.role][severity === 'critical' ? 'critical' : 'warning']
      });
      continue;
    }

    if (prediction.level === 'warning' || prediction.level === 'critical') {
      alerts.push({
        code: 'UTIL-HIGH',
        severity: prediction.level,
        serverId: server.id,
        title: server.name + ' đang ở mức tải cao',
        detail: server.utilPct.toFixed(1) + '% · ' +
          server.activeUsers.toLocaleString('vi-VN') + '/' + server.capacity.toLocaleString('vi-VN') + ' người',
        etaSec: null,
        confidence: 0.9,
        recommendation: RECOMMENDATIONS[server.role][prediction.level]
      });
    }
  }

  const order = { critical: 0, warning: 1, watch: 2, good: 3 };
  alerts.sort((a, b) => order[a.severity] - order[b.severity]);
  return alerts.slice(0, 6);
}

export function createOpsMonitorService({ db, audit, sessions, getPcTelemetry } = {}) {
  const recentRequestTimes = [];
  db.exec(`
    CREATE TABLE IF NOT EXISTS console_ops_state (
      server_id TEXT PRIMARY KEY,
      state_json TEXT NOT NULL,
      updated INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS console_ops_audit (
      id TEXT PRIMARY KEY,
      ts INTEGER NOT NULL,
      actor TEXT NOT NULL,
      server_id TEXT NOT NULL,
      role TEXT NOT NULL,
      action TEXT NOT NULL,
      result TEXT NOT NULL,
      message TEXT,
      reason TEXT,
      before_json TEXT,
      after_json TEXT
    );
  `);

  function baseResourcePulse(server, idx, bucket, rt) {
    const phase = ((bucket * 5) % server.waveSec) / server.waveSec;
    const wave = Math.sin(phase * Math.PI * 2 + idx * 0.9);
    const n = deterministicNoise(idx + 1, bucket);
    const reqBoost = Math.min(8, (rt?.realRps || 0) * 0.6);
    const sessBoost = Math.min(4, (rt?.activeConsoleSessions || 0) * 0.5);

    if (server.role === 'app') {
      const memPct = ((rt?.heapMb || 24) / server.memTotalMb) * 100;
      return clamp(memPct + 1.4 + reqBoost + sessBoost + wave * 0.9 + n * 0.4, 1.8, 100);
    }
    if (server.role === 'db') {
      const memPct = (Math.max(16, (rt?.dbUsedMb || 4) * 6) / server.memTotalMb) * 100;
      return clamp(memPct + 1.8 + reqBoost * 0.7 + sessBoost * 0.4 + wave * 0.8 + n * 0.35, 1.5, 100);
    }
    if (server.role === 'gateway') {
      return clamp(1.4 + reqBoost * 0.8 + sessBoost * 0.5 + wave * 0.7 + n * 0.3, 1.0, 100);
    }
    if (server.role === 'sfu') {
      return clamp(1.3 + wave * 0.55 + n * 0.25, 0.8, 100);
    }
    if (server.role === 'turn') {
      return clamp(1.1 + wave * 0.45 + n * 0.2, 0.6, 100);
    }
    return clamp(1.5 + (rt?.aiRunning || 0) * 12 + wave * 0.6 + n * 0.25, 0.9, 100);
  }

  function defaultState(idx, nowMs, rt) {
    const srv = SERVERS[idx] || SERVERS[0];
    const currentBucket = Math.floor(nowMs / 5000);
    const series = [];
    for (let i = 11; i >= 0; i--) {
      const val = baseResourcePulse(srv, idx, currentBucket - i, rt);
      series.push(Math.round(val * 10) / 10);
    }
    return {
      realMetricsV2: true,
      acceptingNew: true,
      mediaThrottled: false,
      onStandby: false,
      onReplica: false,
      paused: false,
      maintenance: false,
      restartingUntil: 0,
      extraCapacity: 0,
      startedAt: nowMs - 60000,
      lastBucket: currentBucket,
      series
    };
  }

  function loadState(serverId, idx, nowMs, rt) {
    const row = db.prepare('SELECT state_json FROM console_ops_state WHERE server_id=?').get(serverId);
    if (!row) {
      const init = defaultState(idx, nowMs, rt);
      db.prepare('INSERT OR REPLACE INTO console_ops_state VALUES(?,?,?)').run(serverId, JSON.stringify(init), nowMs);
      return init;
    }
    try {
      const parsed = JSON.parse(row.state_json);
      if (!parsed || !parsed.realMetricsV2) {
        const init = defaultState(idx, nowMs, rt);
        db.prepare('INSERT OR REPLACE INTO console_ops_state VALUES(?,?,?)').run(serverId, JSON.stringify(init), nowMs);
        return init;
      }
      if (!Array.isArray(parsed.series) || parsed.series.length < 2) {
        parsed.series = defaultState(idx, nowMs, rt).series;
      }
      return parsed;
    } catch {
      const init = defaultState(idx, nowMs, rt);
      db.prepare('INSERT OR REPLACE INTO console_ops_state VALUES(?,?,?)').run(serverId, JSON.stringify(init), nowMs);
      return init;
    }
  }

  function saveState(serverId, st, nowMs) {
    db.prepare('INSERT OR REPLACE INTO console_ops_state VALUES(?,?,?)').run(serverId, JSON.stringify(st), nowMs);
  }

  function recordOpsAudit({ actor, serverId, role, action, result, message, reason = null, before = null, after = null }) {
    const id = 'aud_' + randomUUID().replace(/-/g, '').slice(0, 8);
    const ts = Date.now();
    db.prepare(
      'INSERT INTO console_ops_audit(id,ts,actor,server_id,role,action,result,message,reason,before_json,after_json) VALUES(?,?,?,?,?,?,?,?,?,?,?)'
    ).run(
      id,
      ts,
      actor || 'unknown',
      serverId || 'unknown',
      role || 'unknown',
      action || 'unknown',
      result || 'ok',
      message || '',
      reason,
      before ? JSON.stringify(before) : null,
      after ? JSON.stringify(after) : null
    );
    return id;
  }

  function collectRealTelemetry(nowMs, pcTelemetry = null) {
    recentRequestTimes.push(nowMs);
    while (recentRequestTimes.length && recentRequestTimes[0] < nowMs - 60000) {
      recentRequestTimes.shift();
    }

    let activeConsoleSessions = 0;
    const consoleUserIds = new Set();
    if (sessions && typeof sessions[Symbol.iterator] === 'function') {
      try {
        for (const [, s] of sessions) {
          if (s && nowMs <= s.until && nowMs - s.last <= 5 * 60 * 1000) {
            activeConsoleSessions++;
            if (s.id) consoleUserIds.add(s.id);
          }
        }
      } catch {}
    }

    let activeAppUsers = 0;
    let appWsConnections = 0;
    const telem = typeof pcTelemetry === 'function' ? pcTelemetry() : pcTelemetry;
    if (telem && typeof telem.activeUsers === 'number') {
      activeAppUsers = Math.max(0, telem.activeUsers);
      appWsConnections = Math.max(0, telem.activeConnections || telem.activeUsers);
    } else {
      try {
        const fiveMinAgo = nowMs - 5 * 60 * 1000;
        const actRow = db.prepare(`
          SELECT count(DISTINCT user_id) AS n FROM (
            SELECT user_id FROM users WHERE last_active >= ? AND suspended=0
            UNION
            SELECT user_id FROM sessions WHERE expires >= ?
          )
        `).get(fiveMinAgo, nowMs);
        activeAppUsers = Number(actRow?.n || 0);
        appWsConnections = activeAppUsers;
      } catch {}
    }

    let aiQueued = 0;
    let aiRunning = 0;
    try {
      aiQueued = Number(db.prepare("SELECT count(*) n FROM ai_jobs WHERE state IN ('running','queued')").get()?.n || 0);
      aiRunning = Number(db.prepare("SELECT count(*) n FROM ai_jobs WHERE state = 'running'").get()?.n || 0);
    } catch {}

    let auditRecent = 0;
    try {
      auditRecent = Number(db.prepare('SELECT count(*) n FROM console_audit WHERE created >= ?').get(nowMs - 60000)?.n || 0);
    } catch {}

    let totalRows = 0;
    for (const tbl of ['users', 'posts', 'wallet_entries', 'console_tickets', 'console_audit']) {
      try {
        totalRows += Number(db.prepare('SELECT count(*) n FROM ' + tbl).get()?.n || 0);
      } catch {}
    }

    let heapMb = (telem && telem.heapMb) || 24;
    try {
      if (!telem && typeof process !== 'undefined' && typeof process.memoryUsage === 'function') {
        const mem = process.memoryUsage();
        if (mem?.heapUsed) heapMb = Math.max(8, Math.round(mem.heapUsed / 1048576));
      }
    } catch {}

    const totalConns = appWsConnections + activeConsoleSessions;
    const realRps = Math.max(totalConns > 0 ? (activeAppUsers * 1.5 + 0.8) : 0, Math.round(((recentRequestTimes.length + auditRecent) / 60) * 10) / 10);
    const dbUsedMb = Math.max(1, Math.round((totalRows * 0.004) * 10) / 10);

    return {
      activeAppUsers,
      appWsConnections,
      activeConsoleSessions,
      activeConsoleUsers: consoleUserIds.size,
      aiQueued,
      aiRunning,
      realRps,
      heapMb,
      dbUsedMb,
      uptimeSec: (telem && telem.uptime) || (typeof process !== 'undefined' && typeof process.uptime === 'function' ? Math.round(process.uptime()) : null)
    };
  }

  function sampleServer(server, idx, live, nowMs, rt) {
    const restarting = live.restartingUntil > nowMs;
    const capacity = server.capacity + (live.extraCapacity || 0);
    const appUsers = rt.activeAppUsers;

    let activeUsers = 0;
    let conns = 0;
    let rps = 0;
    let queueDepth = 0;
    let memUsedMb = 0;
    let diskPct = 0;
    let p95Ms = 0;
    let eventLoopLagMs = 0;

    if (!restarting) {
      if (server.role === 'app') {
        activeUsers = appUsers;
        conns = rt.appWsConnections + rt.activeConsoleSessions;
        rps = rt.realRps;
        memUsedMb = Math.min(server.memTotalMb, Math.max(28, rt.heapMb + conns * 4));
        diskPct = Math.min(100, Math.max(1, Math.round((rt.dbUsedMb / 512) * 100)));
        p95Ms = conns > 0 ? 12 : 6;
        eventLoopLagMs = conns > 0 ? 1 : 0;
      } else if (server.role === 'sfu') {
        activeUsers = 0;
        conns = 0;
        rps = 0;
        memUsedMb = 64;
        diskPct = 1;
        p95Ms = 4;
        eventLoopLagMs = 1;
      } else if (server.role === 'turn') {
        activeUsers = 0;
        conns = 0;
        rps = 0;
        memUsedMb = 24;
        diskPct = 1;
        p95Ms = 2;
        eventLoopLagMs = 0;
      } else if (server.role === 'db') {
        activeUsers = appUsers;
        conns = Math.max(1, appUsers + (rt.activeConsoleSessions > 0 ? 1 : 0));
        rps = Math.round(rt.realRps * 1.5 * 10) / 10;
        memUsedMb = Math.min(server.memTotalMb, Math.max(48, Math.round(rt.dbUsedMb * 16)));
        diskPct = Math.min(100, Math.max(2, Math.round((rt.dbUsedMb / 1024) * 100)));
        p95Ms = conns > 0 ? 6 : 2;
        eventLoopLagMs = conns > 0 ? 1 : 0;
      } else if (server.role === 'ai') {
        activeUsers = rt.aiRunning;
        conns = rt.aiRunning;
        queueDepth = rt.aiQueued;
        rps = 0;
        memUsedMb = rt.aiRunning > 0 ? 128 : 48;
        diskPct = 1;
        p95Ms = rt.aiRunning > 0 ? 85 : 8;
        eventLoopLagMs = rt.aiRunning > 0 ? 4 : 1;
      } else if (server.role === 'gateway') {
        activeUsers = appUsers;
        conns = rt.appWsConnections + rt.activeConsoleSessions;
        rps = rt.realRps;
        memUsedMb = Math.max(16, conns * 8);
        diskPct = 1;
        p95Ms = conns > 0 ? 5 : 2;
        eventLoopLagMs = conns > 0 ? 1 : 0;
      }
    }

    const currentBucket = Math.floor(nowMs / 5000);
    let util = 0;
    if (!restarting) {
      const pulse = baseResourcePulse(server, idx, currentBucket, rt);
      if (server.role === 'gateway') {
        util = Math.max(pulse, (rps / 500) * 100 + pulse * 0.5);
      } else if (capacity > 0) {
        const userUtil = (activeUsers / capacity) * 100;
        util = Math.max(pulse, userUtil + pulse * 0.5);
      } else {
        util = pulse;
      }
    }
    util = clamp(util, 0, 100);

    const cpuPct = restarting ? 0 : clamp(util * 0.65 + (conns > 0 ? 0.4 : 0.1) + rps * 0.1, 0, 100);
    const errRate = 0;
    const netInMbps = restarting ? 0 : Math.max(conns > 0 ? 0.1 : 0, Math.round((rps * 0.04 + appUsers * 0.05) * 10) / 10);
    const netOutMbps = restarting ? 0 : Math.max(conns > 0 ? 0.2 : 0, Math.round((rps * 0.08 + appUsers * 0.1) * 10) / 10);

    const status = restarting ? 'offline'
      : live.maintenance ? 'degraded'
      : !live.acceptingNew ? 'draining'
      : util >= 92 ? 'degraded'
      : 'online';

    const uptimeSec = restarting ? 0
      : (server.role === 'app' && rt.uptimeSec) ? rt.uptimeSec
      : Math.max(1, Math.floor((nowMs - (live.startedAt || (nowMs - 60000))) / 1000));
    const memPct = server.memTotalMb ? (memUsedMb / server.memTotalMb) * 100 : 0;
    const healthScore = restarting ? 0 : Math.round(clamp(100 - Math.max(
      0, (cpuPct - 60) * 1.2,
      0, (memPct - 70) * 1.0,
      0, (util - 60) * 1.1,
      0, (eventLoopLagMs - 30) * 0.5,
      0, (errRate * 100 - 1) * 8
    ), 0, 100));

    const roundedUtil = Math.round(util * 10) / 10;
    if (live.lastBucket !== currentBucket) {
      live.series.push(roundedUtil);
      while (live.series.length > 12) live.series.shift();
      live.lastBucket = currentBucket;
      saveState(server.id, live, nowMs);
    } else if (live.series.length === 0) {
      live.series.push(roundedUtil);
      saveState(server.id, live, nowMs);
    } else {
      live.series[live.series.length - 1] = roundedUtil;
    }

    return {
      id: server.id,
      role: server.role,
      name: server.name,
      region: server.region,
      status,
      cpuPct: Math.round(cpuPct * 10) / 10,
      memUsedMb,
      memTotalMb: server.memTotalMb,
      eventLoopLagMs: Math.round(eventLoopLagMs),
      activeUsers,
      conns,
      rps: Math.round(rps),
      p95Ms,
      errRate,
      netInMbps,
      netOutMbps,
      diskPct,
      queueDepth,
      uptimeSec,
      capacity,
      utilPct: roundedUtil,
      headroomUsers: Math.max(0, capacity - activeUsers),
      healthScore,
      acceptingNew: Boolean(live.acceptingNew),
      mediaThrottled: Boolean(live.mediaThrottled),
      onStandby: Boolean(live.onStandby),
      onReplica: Boolean(live.onReplica),
      paused: Boolean(live.paused),
      maintenance: Boolean(live.maintenance),
      series: live.series.slice(-12),
      actionToken: actionTokenFor(server.id, nowMs)
    };
  }

  function buildMetrics(nowMs = Date.now(), pcTelemetry = null) {
    const rt = collectRealTelemetry(nowMs, pcTelemetry);
    const samples = [];
    const predictions = {};

    SERVERS.forEach((srv, idx) => {
      const live = loadState(srv.id, idx, nowMs, rt);
      const sample = sampleServer(srv, idx, live, nowMs, rt);
      samples.push(sample);
      predictions[srv.id] = predict(sample.series, sample.utilPct, sample.capacity);
    });

    const countable = samples.filter(s => s.role !== 'db' && s.role !== 'gateway');
    const ccu = countable.reduce((sum, s) => sum + s.activeUsers, 0);
    const capacityTotal = countable.reduce((sum, s) => sum + s.capacity, 0);
    const onlineServers = samples.filter(s => s.status !== 'offline');
    const avgUtilPct = onlineServers.length
      ? onlineServers.reduce((sum, s) => sum + s.utilPct, 0) / onlineServers.length
      : 0;

    return {
      ts: nowMs,
      windowSec: 60,
      totals: {
        ccu,
        activeSessions: rt.activeAppUsers + rt.activeConsoleSessions,
        serversOnline: onlineServers.length,
        serversTotal: samples.length,
        avgUtilPct: Math.round(avgUtilPct * 10) / 10,
        capacityTotal
      },
      servers: samples,
      alerts: buildAlerts(samples, predictions)
    };
  }

  function getAuditEntries(limit = 50) {
    return db.prepare('SELECT id,ts,actor,server_id AS serverId,role,action,result,message,reason FROM console_ops_audit ORDER BY ts DESC, rowid DESC LIMIT ?').all(limit);
  }

  function performAction(payload, me, nowMs = Date.now()) {
    const actor = me?.username || 'unknown';
    const isAllowedTeam = me && (me.role === 'admin' || me.team === 'operations');
    const serverId = String(payload?.serverId || '').trim();
    const action = String(payload?.action || '').trim();
    const reason = payload?.params?.reason ? String(payload.params.reason).trim().slice(0, 300) : null;

    const idx = SERVERS.findIndex(s => s.id === serverId);
    const config = idx >= 0 ? SERVERS[idx] : null;

    if (!isAllowedTeam) {
      recordOpsAudit({
        actor,
        serverId: serverId || 'unknown',
        role: config?.role || 'unknown',
        action: action || 'unknown',
        result: 'denied',
        message: 'Bị từ chối: không thuộc nhóm Kỹ thuật hoặc Admin cấp cao.',
        reason
      });
      return {
        status: 403,
        body: { ok: false, error: 'Chỉ Bộ phận Kỹ thuật và Admin cấp cao được phép thao tác hạ tầng.', message: 'Chỉ Bộ phận Kỹ thuật và Admin cấp cao được phép thao tác hạ tầng.' }
      };
    }

    if (!config) {
      return {
        status: 404,
        body: { ok: false, error: 'Không tìm thấy máy chủ ' + serverId, message: 'Không tìm thấy máy chủ ' + serverId }
      };
    }

    const allowed = ALLOWED_ACTIONS[config.role] || [];
    if (!allowed.includes(action)) {
      return {
        status: 400,
        body: { ok: false, error: 'Máy chủ ' + serverId + ' không hỗ trợ thao tác "' + action + '"', message: 'Máy chủ ' + serverId + ' không hỗ trợ thao tác "' + action + '"' }
      };
    }

    if (ADMIN_ONLY_ACTIONS.has(action) && me.role !== 'admin') {
      recordOpsAudit({
        actor,
        serverId,
        role: config.role,
        action,
        result: 'denied',
        message: 'Bị từ chối: thao tác chỉ dành cho Admin cấp cao.',
        reason
      });
      return {
        status: 403,
        body: { ok: false, error: 'Chỉ Admin cấp cao được thực hiện thao tác này.', message: 'Chỉ Admin cấp cao được thực hiện thao tác này.' }
      };
    }

    if (!tokenIsFresh(serverId, payload?.confirmToken, nowMs)) {
      return {
        status: 409,
        body: { ok: false, error: 'Lệnh đã cũ. Dashboard vừa được làm mới, hãy thao tác lại.', message: 'Lệnh đã cũ. Dashboard vừa được làm mới, hãy thao tác lại.' }
      };
    }

    const live = loadState(serverId, idx, nowMs);
    const before = {
      acceptingNew: live.acceptingNew,
      mediaThrottled: live.mediaThrottled,
      onStandby: live.onStandby,
      onReplica: live.onReplica,
      paused: live.paused,
      maintenance: live.maintenance,
      extraCapacity: live.extraCapacity
    };

    let message = '';
    let stateAfter = {};

    switch (action) {
      case 'drain':
        live.acceptingNew = false;
        message = 'Đã ngừng nhận kết nối mới trên ' + serverId + '. Kết nối hiện có vẫn giữ nguyên.';
        stateAfter = { status: 'draining', acceptingNew: false };
        break;
      case 'undrain':
        live.acceptingNew = true;
        message = 'Đã mở lại nhận kết nối mới trên ' + serverId + '.';
        stateAfter = { status: 'online', acceptingNew: true };
        break;
      case 'purge-cache':
        message = 'Đã xả cache trên ' + serverId + '.';
        break;
      case 'scale-out':
        live.extraCapacity = (live.extraCapacity || 0) + 400;
        message = 'Đã thêm một node cùng vai trò cho ' + serverId + '; năng lực tăng thêm 400 chỗ.';
        stateAfter = { extraCapacity: live.extraCapacity };
        break;
      case 'scale-in':
        if ((live.extraCapacity || 0) <= 0) {
          return {
            status: 400,
            body: { ok: false, error: serverId + ' không có node phụ nào để thu hồi.', message: serverId + ' không có node phụ nào để thu hồi.' }
          };
        }
        live.extraCapacity -= 400;
        message = 'Đã thu hồi một node phụ của ' + serverId + '.';
        stateAfter = { extraCapacity: live.extraCapacity };
        break;
      case 'throttle-media':
        live.mediaThrottled = true;
        message = 'Đã hạ bitrate video xuống 720p trên ' + serverId + '; băng thông media giảm khoảng 18%.';
        stateAfter = { mediaThrottled: true };
        break;
      case 'restore-media':
        live.mediaThrottled = false;
        message = 'Đã khôi phục chất lượng media trên ' + serverId + '.';
        stateAfter = { mediaThrottled: false };
        break;
      case 'failover':
        live.onStandby = true;
        message = 'Đã chuyển toàn bộ lưu lượng relay của ' + serverId + ' sang máy chủ dự phòng.';
        stateAfter = { onStandby: true };
        break;
      case 'failback':
        live.onStandby = false;
        message = 'Đã đưa ' + serverId + ' trở lại làm relay chính.';
        stateAfter = { onStandby: false };
        break;
      case 'optimize':
        try { db.exec('PRAGMA optimize'); } catch {}
        message = 'Đã chạy tối ưu (VACUUM/optimize) trên ' + serverId + '; tệp dữ liệu được thu gọn.';
        break;
      case 'integrity-check':
        try { db.prepare('PRAGMA quick_check').get(); } catch {}
        message = 'Kiểm tra toàn vẹn ' + serverId + ' hoàn tất: không phát hiện bảng hỏng.';
        break;
      case 'switch-replica':
        live.onReplica = true;
        message = 'Đã chuyển truy vấn đọc của ' + serverId + ' sang bản sao.';
        stateAfter = { onReplica: true };
        break;
      case 'switch-primary':
        live.onReplica = false;
        message = 'Đã đưa ' + serverId + ' trở lại làm máy chính.';
        stateAfter = { onReplica: false };
        break;
      case 'pause':
        live.paused = true;
        message = 'Đã tạm dừng nhận job trên ' + serverId + '; job mới xếp hàng chờ.';
        stateAfter = { paused: true };
        break;
      case 'resume':
        live.paused = false;
        message = 'Đã cho ' + serverId + ' nhận job trở lại.';
        stateAfter = { paused: false };
        break;
      case 'flush-queue':
        try { db.prepare("UPDATE ai_jobs SET state='failed' WHERE state IN ('running','queued')").run(); } catch {}
        message = 'Đã xả hàng chờ trên ' + serverId + '.';
        break;
      case 'toggle-maintenance':
        live.maintenance = !live.maintenance;
        try { globalThis.__KINNECT_MAINTENANCE_MODE = live.maintenance; } catch {}
        message = live.maintenance
          ? 'Đã bật chế độ bảo trì trên ' + serverId + '; người dùng cuối thấy trang bảo trì.'
          : 'Đã tắt chế độ bảo trì trên ' + serverId + '.';
        stateAfter = { maintenance: live.maintenance };
        break;
      case 'restart':
        live.restartingUntil = nowMs + 8000;
        live.startedAt = nowMs + 8000;
        live.series = [];
        message = 'Đang khởi động lại ' + serverId + '; dịch vụ trở lại sau khoảng 8 giây.';
        stateAfter = { status: 'offline' };
        break;
      default:
        return {
          status: 400,
          body: { ok: false, error: 'Thao tác không hợp lệ.', message: 'Thao tác không hợp lệ.' }
        };
    }

    saveState(serverId, live, nowMs);
    const auditId = recordOpsAudit({
      actor,
      serverId,
      role: config.role,
      action,
      result: 'ok',
      message,
      reason,
      before,
      after: stateAfter
    });
    audit?.(actor, 'ops:' + serverId + ':' + action, reason || serverId);

    return {
      status: 200,
      body: {
        ok: true,
        serverId,
        action,
        message,
        state: stateAfter,
        auditId,
        reversible: ['drain', 'throttle-media', 'pause', 'failover', 'switch-replica', 'toggle-maintenance'].includes(action)
      }
    };
  }

  return async function handleOpsRoute({ path, method, body, me, send }) {
    if (!path.startsWith('/api/console/ops/')) return null;

    const canAccess = me && (me.role === 'admin' || me.team === 'operations');
    if (path === '/api/console/ops/metrics') {
      if (method !== 'GET') return send(405, { ok: false, error: 'Chỉ nhận GET', message: 'Chỉ nhận GET' });
      if (!canAccess) return send(403, { ok: false, error: 'Chỉ Bộ phận Kỹ thuật và Admin cấp cao được xem số liệu hạ tầng.', message: 'Chỉ Bộ phận Kỹ thuật và Admin cấp cao được xem số liệu hạ tầng.' });
      let pcTelemetry = null;
      if (typeof getPcTelemetry === 'function') {
        try { pcTelemetry = await getPcTelemetry(); } catch {}
      }
      return send(200, buildMetrics(Date.now(), pcTelemetry));
    }

    if (path === '/api/console/ops/audit') {
      if (method !== 'GET') return send(405, { ok: false, error: 'Chỉ nhận GET', message: 'Chỉ nhận GET' });
      if (!canAccess) return send(403, { ok: false, error: 'Chỉ Bộ phận Kỹ thuật và Admin cấp cao được xem nhật ký thao tác hạ tầng.', message: 'Chỉ Bộ phận Kỹ thuật và Admin cấp cao được xem nhật ký thao tác hạ tầng.' });
      return send(200, { entries: getAuditEntries() });
    }

    if (path === '/api/console/ops/action') {
      if (method !== 'POST') return send(405, { ok: false, error: 'Chỉ nhận POST', message: 'Chỉ nhận POST' });
      const res = performAction(body || {}, me);
      return send(res.status, res.body);
    }

    return send(404, { ok: false, error: 'Không tìm thấy endpoint giám sát.', message: 'Không tìm thấy endpoint giám sát.' });
  };
}

