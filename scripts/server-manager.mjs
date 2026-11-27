import { loadMailEnv } from '../lib/mailer.js';
import { spawn, execFileSync } from 'node:child_process';
import { appendFile, mkdir, open, readdir, readFile, stat, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const data = join(root, 'data');
const stateFile = join(data, 'server-manager.json');
const serverFile = join(root, 'server.js');
const selfFile = fileURLToPath(import.meta.url);
const tunnelConfig = join(root, 'scripts/windows-tunnel.yml');

loadMailEnv(join(root, 'sfu.env'));

const pause = (ms) => new Promise((r) => setTimeout(r, ms));
async function exists(p) {
  if (!p) return false;
  try {
    await stat(p);
    return true;
  } catch {
    return false;
  }
}

async function resolveTunnelExe() {
  const candidates = [
    process.env.KINNECT_CLOUDFLARED,
    join(root, 'tools', 'cloudflared.exe'),
    join(root, 'work', 'tools', 'cloudflared.exe'),
    resolve(root, '../2026-10-24/c-kinnect-s-theo-h-ng/work/tools/cloudflared.exe'),
  ].filter(Boolean);
  for (const c of candidates) {
    if (await exists(c)) return c;
  }
  return candidates[0] || join(root, 'tools', 'cloudflared.exe');
}

function alive(pid) {
  if (!Number.isInteger(pid) || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch (e) {
    return e.code === 'EPERM';
  }
}

async function state() {
  try {
    return JSON.parse(await readFile(stateFile, 'utf8'));
  } catch (e) {
    if (e.code === 'ENOENT') return {};
    throw Error('Cannot read manager state: ' + e.message);
  }
}

async function save(s) {
  await writeFile(stateFile, JSON.stringify(s, null, 2));
}

function identity(record) {
  if (!record || !Number.isInteger(record.pid) || !alive(record.pid)) return false;
  let info;
  try {
    const command =
      '$p=Get-CimInstance Win32_Process -Filter "ProcessId=' +
      record.pid +
      '" -ErrorAction Stop; if($p){$p | Select-Object ExecutablePath,CommandLine | ConvertTo-Json -Compress}';
    const raw = execFileSync('powershell.exe', ['-NoProfile', '-Command', command], {
      encoding: 'utf8',
      windowsHide: true,
      timeout: 10000,
    });
    info = raw.trim() ? JSON.parse(raw) : null;
  } catch {
    throw Error('Cannot verify process identity. Right-click CMD and choose Run as administrator.');
  }
  if (!info) return false;
  return (
    info.ExecutablePath?.toLowerCase() === record.exe.toLowerCase() &&
    info.CommandLine?.toLowerCase().includes(record.marker.toLowerCase())
  );
}

async function health() {
  try {
    const r = await fetch('http://127.0.0.1:3000/health', { signal: AbortSignal.timeout(2000) });
    const d = await r.json();
    return r.ok && d.ok && typeof d.uiVersion === 'string';
  } catch {
    return false;
  }
}

async function sfuHealth() {
  if (process.env.KINNECT_LIVE_TRANSPORT !== 'sfu' || process.env.KINNECT_SFU_MANAGED === 'remote') return true;
  try {
    const endpoint = new URL(process.env.KINNECT_SFU_URL || 'ws://127.0.0.1:7885/control');
    endpoint.protocol = endpoint.protocol === 'wss:' ? 'https:' : 'http:';
    endpoint.pathname = '/health';
    const response = await fetch(endpoint, {
      headers: process.env.KINNECT_SFU_SECRET ? { Authorization: 'Bearer ' + process.env.KINNECT_SFU_SECRET } : {},
      signal: AbortSignal.timeout(1200),
    });
    return response.ok;
  } catch {
    return false;
  }
}

async function launch(exe, args, log, marker, env = process.env) {
  const handle = await open(join(data, log), 'a');
  try {
    const child = spawn(exe, args, {
      cwd: root,
      env,
      detached: true,
      windowsHide: true,
      stdio: ['ignore', handle.fd, handle.fd],
    });
    await new Promise((ok, bad) => {
      child.once('spawn', ok);
      child.once('error', bad);
    });
    const record = { pid: child.pid, exe, marker, started: new Date().toISOString() };
    child.unref();
    return record;
  } finally {
    await handle.close();
  }
}

async function stop(s, keys = ['watchdog', 'tunnel', 'server', 'sfu']) {
  for (const key of keys) {
    const record = s[key];
    if (!record) continue;
    if (identity(record)) {
      process.kill(record.pid);
      for (let i = 0; i < 30 && alive(record.pid); i++) await pause(100);
      if (alive(record.pid)) throw Error('Process did not stop: ' + key);
      console.log('STOPPED ' + key + ' PID ' + record.pid);
    } else {
      console.log('No matching managed ' + key + ' process.');
    }
    delete s[key];
    await save(s);
  }
  if (keys.includes('server') && (await health())) {
    console.log('Port 3000 still serves an unmanaged Kinnect server; it was left running.');
  }
}

async function startSfu(s) {
  if (process.env.KINNECT_LIVE_TRANSPORT !== 'sfu' || process.env.KINNECT_SFU_MANAGED === 'remote') return;
  if (s.sfu && alive(s.sfu.pid)) {
    if (!identity(s.sfu)) throw Error('Saved SFU PID belongs to a different process.');
    return;
  }
  const exe = join(root, 'services/live-sfu/bin', process.platform === 'win32' ? 'kinnect-sfu.exe' : 'kinnect-sfu');
  if (!(await exists(exe))) throw Error('Build SFU first: node scripts/build-live-sfu.mjs');
  s.sfu = await launch(exe, [], 'startup-sfu.log', exe);
  await save(s);
  let ready = false;
  for (let i = 0; i < 30; i++) {
    if (!alive(s.sfu.pid)) break;
    if (await sfuHealth()) {
      ready = true;
      break;
    }
    await pause(300);
  }
  if (!ready) throw Error('SFU did not start. Check data/startup-sfu.log');
  console.log('SFU READY');
}

async function startTunnel(s, env = process.env) {
  const tunnelExe = await resolveTunnelExe();
  if ((await exists(tunnelExe)) && (await exists(tunnelConfig))) {
    if (!s.tunnel || !alive(s.tunnel.pid)) {
      s.tunnel = await launch(
        tunnelExe,
        ['tunnel', '--config', tunnelConfig, '--logfile', join(data, 'startup-tunnel.log'), 'run', 'kinnect'],
        'startup-tunnel-console.log',
        tunnelConfig,
        env,
      );
      await save(s);
    }
    console.log('Cloudflare tunnel launched; check data/startup-tunnel.log for connection status.');
  } else {
    console.log('Tunnel files missing. Local server is available, public web may remain offline.');
  }
}

async function startWatchdog(s) {
  if (s.watchdog && alive(s.watchdog.pid)) {
    try {
      if (identity(s.watchdog)) {
        console.log('Watchdog already running PID ' + s.watchdog.pid);
        return;
      }
    } catch {}
  }
  s.watchdog = await launch(process.execPath, [selfFile, 'watchdog'], 'watchdog.log', 'watchdog');
  await save(s);
  console.log('WATCHDOG READY PID ' + s.watchdog.pid);
}

async function rotateLogs(maxBytes = 5 * 1024 * 1024, keepBytes = 256 * 1024) {
  const names = await readdir(data).catch(() => []);
  let rotated = 0;
  for (const n of names) {
    if (!n.endsWith('.log')) continue;
    const full = join(data, n);
    const st = await stat(full).catch(() => null);
    if (!st?.isFile() || st.size <= maxBytes) continue;
    try {
      const raw = await readFile(full);
      await writeFile(full, raw.subarray(Math.max(0, raw.length - keepBytes)));
      rotated++;
    } catch {}
  }
  return rotated;
}

async function startServerOnly(s) {
  if (s.server && alive(s.server.pid)) {
    if (!identity(s.server)) throw Error('Saved server PID belongs to a different process. No process was stopped.');
    console.log('Server already running.');
    return;
  }
  if (await health()) {
    throw Error('An existing server is using port 3000. Close that server first; this manager will not kill an unknown process.');
  }
  const env = { ...process.env, PORT: '3000', SECURE_COOKIES: '1', DATA_DIR: data };
  s.server = await launch(process.execPath, [serverFile], 'startup-server.log', serverFile, env);
  await save(s);
  let ready = false;
  for (let i = 0; i < 30; i++) {
    if (!alive(s.server.pid)) break;
    if (await health()) {
      ready = true;
      break;
    }
    await pause(500);
  }
  if (!ready) throw Error('Server did not start. Check ' + join(data, 'startup-server.log'));
  console.log('SERVER READY: http://127.0.0.1:3000');
}

async function start(s) {
  await startSfu(s);
  await startServerOnly(s);
  const env = { ...process.env, PORT: '3000', SECURE_COOKIES: '1', DATA_DIR: data };
  await startTunnel(s, env);
  await startWatchdog(s);
}

async function logWatchdog(msg) {
  const line = `[${new Date().toISOString()}] [watchdog] ${msg}\n`;
  await appendFile(join(data, 'watchdog.log'), line).catch(() => {});
}

async function runWatchdogLoop(once = false) {
  let unhealthyStreak = 0;
  let tick = 0;
  await logWatchdog('Started auto-recovery loop (interval 30s)');
  while (true) {
    try {
      const s = await state();
      const serverUp = await health();
      if (serverUp) {
        unhealthyStreak = 0;
      } else {
        unhealthyStreak++;
        if (unhealthyStreak >= 2 || once) {
          await logWatchdog('Server unhealthy/offline — attempting auto-restart...');
          try {
            if (s.server && alive(s.server.pid) && identity(s.server)) {
              await stop(s, ['server']);
            } else {
              delete s.server;
              await save(s);
            }
            await startServerOnly(s);
            await logWatchdog('Server recovered PID ' + s.server?.pid);
            unhealthyStreak = 0;
          } catch (err) {
            await logWatchdog('Server recovery failed: ' + err.message);
          }
        }
      }

      if (process.env.KINNECT_LIVE_TRANSPORT === 'sfu' && process.env.KINNECT_SFU_MANAGED !== 'remote') {
        if (!(await sfuHealth())) {
          await logWatchdog('SFU offline — attempting auto-restart...');
          try {
            delete s.sfu;
            await save(s);
            await startSfu(s);
            await logWatchdog('SFU recovered PID ' + s.sfu?.pid);
          } catch (err) {
            await logWatchdog('SFU recovery failed: ' + err.message);
          }
        }
      }

      const tunnelExe = await resolveTunnelExe();
      if ((await exists(tunnelExe)) && (await exists(tunnelConfig))) {
        if (!s.tunnel || !alive(s.tunnel.pid)) {
          await logWatchdog('Cloudflare Tunnel stopped — attempting auto-restart...');
          try {
            delete s.tunnel;
            await save(s);
            await startTunnel(s);
            await logWatchdog('Tunnel recovered PID ' + s.tunnel?.pid);
          } catch (err) {
            await logWatchdog('Tunnel recovery failed: ' + err.message);
          }
        }
      }

      if (++tick % 20 === 0 || once) {
        const count = await rotateLogs(10 * 1024 * 1024, 256 * 1024);
        if (count > 0) await logWatchdog(`Rotated ${count} oversized log file(s).`);
      }
    } catch (err) {
      await logWatchdog('Watchdog cycle error: ' + err.message);
    }
    if (once) break;
    await pause(30000);
  }
}

const action = process.argv[2] || 'status';
try {
  await mkdir(data, { recursive: true });
  if (!(await exists(serverFile))) throw Error('Missing server.js');
  if (action === 'check') {
    if (!(await exists(join(root, 'node_modules/ws/package.json')))) throw Error('Missing dependencies');
    const tunnelExe = await resolveTunnelExe();
    console.log('Preflight OK: ' + root);
    console.log('Node ' + process.version);
    console.log('Tunnel files: ' + ((await exists(tunnelExe)) && (await exists(tunnelConfig)) ? 'present (' + tunnelExe + ')' : 'missing'));
    process.exit(0);
  }
  const s = await state();
  if (action === 'start') await start(s);
  else if (action === 'stop') await stop(s);
  else if (action === 'restart') {
    await stop(s);
    await start(s);
  } else if (action === 'restart-sfu') {
    await stop(s, ['sfu']);
    await startSfu(s);
  } else if (action === 'restart-server') {
    await stop(s, ['server']);
    await startServerOnly(s);
    await startWatchdog(s);
  } else if (action === 'restart-tunnel') {
    await stop(s, ['tunnel']);
    await startTunnel(s);
  } else if (action === 'start-watchdog') {
    await startWatchdog(s);
  } else if (action === 'stop-watchdog') {
    await stop(s, ['watchdog']);
  } else if (action === 'watchdog') {
    await runWatchdogLoop(process.argv.includes('--once'));
  } else if (action === 'rotate-logs') {
    const count = await rotateLogs(2 * 1024 * 1024, 256 * 1024);
    console.log('Rotated log files: ' + count);
  } else if (action === 'status') {
    console.log('Project: ' + root);
    console.log('HTTP health: ' + ((await health()) ? 'OK' : 'OFFLINE'));
    console.log('SFU health: ' + ((await sfuHealth()) ? 'OK' : 'OFFLINE'));
    for (const k of ['server', 'tunnel', 'sfu', 'watchdog']) {
      console.log(k + ': ' + (s[k] && alive(s[k].pid) ? 'PID ' + s[k].pid : 'not managed / stopped'));
    }
  } else {
    throw Error('Unknown action: ' + action);
  }
} catch (e) {
  console.error('ERROR: ' + e.message);
  process.exitCode = 1;
}
