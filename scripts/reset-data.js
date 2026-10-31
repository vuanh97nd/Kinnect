import { DatabaseSync } from 'node:sqlite';
import { mkdirSync, existsSync, lstatSync, renameSync, copyFileSync, readdirSync, writeFileSync, realpathSync } from 'node:fs';
import { resolve, relative, sep, join } from 'node:path';
import { fileURLToPath } from 'node:url';

export function resetKinnectData({ database, backupDirectory, includeMedia = false }) {
  const path = resolve(database), backup = resolve(backupDirectory), root = resolve(path, '..', '..');
  if (!existsSync(path)) throw Error('Không tìm thấy database đã chỉ định.');
  if (relative(root, backup) === '' || !relative(root, backup).startsWith('..' + sep)) {
    if (backup === root || backup.startsWith(join(root, 'public') + sep)) throw Error('Thư mục sao lưu không được nằm trong public.');
  }
  mkdirSync(backup, { recursive: true });
  if(realpathSync(backup)!==backup)throw Error("Thư mục sao lưu không được là liên kết.");
  const snapshot = join(backup, 'kinnect.sqlite');
  if (existsSync(snapshot)) throw Error('Bản sao lưu đã tồn tại; không ghi đè.');
  const db = new DatabaseSync(path); db.exec('PRAGMA busy_timeout=10000; PRAGMA secure_delete=ON;');
  const quote = name => '"' + name.replaceAll('"', '""') + '"';
  const tables = db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name").all().map(t => t.name);
  let counts;
  try {
    const before = db.prepare('PRAGMA data_version').get().data_version;
    db.prepare('VACUUM INTO ?').run(snapshot);
    const check = new DatabaseSync(snapshot, { readOnly: true });
    try { if (check.prepare('PRAGMA integrity_check').get().integrity_check !== 'ok') throw Error('Bản sao lưu chưa đạt kiểm tra toàn vẹn.'); } finally { check.close(); }
    db.exec('PRAGMA foreign_keys=OFF; BEGIN IMMEDIATE');
    if (db.prepare('PRAGMA data_version').get().data_version !== before) { db.exec('ROLLBACK'); throw Error('Database đang thay đổi. Đã sao lưu nhưng chưa xoá; dừng server rồi chạy lại vào thư mục sao lưu mới.'); }
    try {
      counts = Object.fromEntries(tables.map(name => [name, db.prepare('SELECT count(*) n FROM ' + quote(name)).get().n]));
      for (const name of tables) db.exec('DELETE FROM ' + quote(name));
      if (db.prepare("SELECT 1 FROM sqlite_master WHERE name='sqlite_sequence'").get()) db.exec('DELETE FROM sqlite_sequence');
      db.exec('COMMIT');
    } catch (err) { try { db.exec('ROLLBACK'); } catch {} throw err; }
    for (const name of tables) if (db.prepare('SELECT count(*) n FROM ' + quote(name)).get().n) throw Error('Chưa xoá hết bảng ' + name);
    db.exec('PRAGMA wal_checkpoint(TRUNCATE)');
  } finally { db.close(); }
  const warnings=[];
  const result = { resetAt: new Date().toISOString(), database: path, snapshot, deletedRows: counts, remainingRows: 0, status:'database-reset',warnings };
  writeFileSync(join(backup, 'reset-report.json'), JSON.stringify(result, null, 2));
  if (includeMedia) {
    for (const name of ['music', 'music-removed']) {
      const source = resolve(root, name), target = resolve(backup, name);
      if (!existsSync(source)) continue;
      if (lstatSync(source).isSymbolicLink() || realpathSync(source) !== source || !source.startsWith(root + sep) || !target.startsWith(backup + sep)) throw Error('Đường dẫn thư viện nhạc không an toàn.');
      if (existsSync(target)) throw Error('Đã có bản sao thư viện nhạc.');
      renameSync(source, target); mkdirSync(source);
      for (const doc of ['README.md', 'README.txt', '.gitkeep']) if (existsSync(join(target, doc))) copyFileSync(join(target, doc), join(source, doc));
    }
    writeFileSync(join(root,'music','credits.json'),'{}\n');
    const dataDirectory = resolve(path, '..'), logBackup = join(backup, 'logs'); mkdirSync(logBackup);
    for (const name of readdirSync(dataDirectory).filter(n => n.endsWith('.log'))) { const source=join(dataDirectory,name);if(lstatSync(source).isFile()){try{copyFileSync(source,join(logBackup,name));writeFileSync(source,'');}catch(err){warnings.push({file:name,reason:err.code||'locked'});}} }
  }
  result.status="complete";
  writeFileSync(join(backup, 'reset-report.json'), JSON.stringify(result, null, 2)); return result;
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [confirmation, database, backupDirectory] = process.argv.slice(2);
  if (confirmation !== '--confirm-delete-all' || !database || !backupDirectory) { console.error('Usage: node scripts/reset-data.js --confirm-delete-all ABSOLUTE_DATABASE_PATH ABSOLUTE_BACKUP_DIRECTORY'); process.exitCode = 1; }
  else { try { console.log(JSON.stringify(resetKinnectData({database,backupDirectory,includeMedia:true}),null,2)); } catch(err) { console.error(err.message); process.exitCode=1; } }
}
