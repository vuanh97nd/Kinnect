// Durable bridge for NEW console credits; never infer or mint unrelated wallet entries.
let savepointSequence = 0;
const FIELDS = ['id','user_id','reference','kind','coins','net_vnd','creator_vnd','platform_vnd','created'];
const UNAVAILABLE = 'Chưa đồng bộ được xu về máy chủ ứng dụng. Vui lòng thử lại cùng mã thao tác.';
function unavailable() { return Object.assign(new Error(UNAVAILABLE), {status:503}); }
function invalid() { return Object.assign(new Error('Dữ liệu đồng bộ xu không hợp lệ.'), {status:400}); }
function boundedString(value) {
 return typeof value === 'string' && value.length > 0 && value.length <= 256 && value === value.trim() && !/[\u0000-\u001f\u007f]/.test(value);
}
function canonical(entry) {
 if (!entry || typeof entry !== 'object' || Array.isArray(entry) ||
     !boundedString(entry.id) || !boundedString(entry.user_id) || !boundedString(entry.reference) ||
     !['admin_trial','coin_purchase'].includes(entry.kind) ||
     !Number.isSafeInteger(entry.coins) || entry.coins <= 0 ||
     !Number.isSafeInteger(entry.created) || entry.created < 0 ||
     entry.net_vnd !== 0 || entry.creator_vnd !== 0 || entry.platform_vnd !== 0) throw invalid();
 const prefix = entry.kind === 'admin_trial' ? 'console-gift:' : 'console-paid:';
 if (!entry.reference.startsWith(prefix) || entry.reference.length === prefix.length) throw invalid();
 return Object.fromEntries(FIELDS.map(field => [field,entry[field]]));
}
function equal(left, right) { return FIELDS.every(field => left[field] === right[field]); }
function schema(db) {
 db.exec(`CREATE TABLE IF NOT EXISTS console_wallet_mirror(
   id TEXT PRIMARY KEY, user_id TEXT NOT NULL, reference TEXT NOT NULL, kind TEXT NOT NULL,
   coins INTEGER NOT NULL, net_vnd INTEGER NOT NULL, creator_vnd INTEGER NOT NULL,
   platform_vnd INTEGER NOT NULL, created INTEGER NOT NULL, applied_at INTEGER,
   UNIQUE(user_id,reference)
 );
 CREATE INDEX IF NOT EXISTS console_wallet_mirror_owner ON console_wallet_mirror(user_id,applied_at);
 CREATE TRIGGER IF NOT EXISTS console_wallet_mirror_immutable_v1
 BEFORE UPDATE ON console_wallet_mirror
 WHEN NEW.id IS NOT OLD.id OR NEW.user_id IS NOT OLD.user_id OR NEW.reference IS NOT OLD.reference
   OR NEW.kind IS NOT OLD.kind OR NEW.coins IS NOT OLD.coins OR NEW.net_vnd IS NOT OLD.net_vnd
   OR NEW.creator_vnd IS NOT OLD.creator_vnd OR NEW.platform_vnd IS NOT OLD.platform_vnd OR NEW.created IS NOT OLD.created
 BEGIN SELECT RAISE(ABORT,'Immutable console wallet mirror'); END;`);
}
function savepoint(db, fn) {
 const name = 'console_wallet_credit_' + (++savepointSequence);
 db.exec('SAVEPOINT ' + name);
 try { const result = fn(); db.exec('RELEASE SAVEPOINT ' + name); return result; }
 catch (error) {
  try { db.exec('ROLLBACK TO SAVEPOINT ' + name); db.exec('RELEASE SAVEPOINT ' + name); } catch {}
  throw error;
 }
}
function sanitized(fn) {
 try { return fn(); } catch (error) { if (error?.status === 400) throw invalid(); throw unavailable(); }
}
/** No user foreign key: a cloud member may not yet have a PC replica. */
export function ensureWalletCreditMirror(db) { return sanitized(() => { schema(db); }); }
function statements(db) {
 return {
  queueId:db.prepare('SELECT * FROM console_wallet_mirror WHERE id=?'),
  queueRef:db.prepare('SELECT * FROM console_wallet_mirror WHERE user_id=? AND reference=?'),
  queueInsert:db.prepare('INSERT INTO console_wallet_mirror(id,user_id,reference,kind,coins,net_vnd,creator_vnd,platform_vnd,created) VALUES(?,?,?,?,?,?,?,?,?)'),
  owner:db.prepare('SELECT id FROM users WHERE id=?'),
  ledgerId:db.prepare('SELECT * FROM wallet_entries WHERE id=?'),
  ledgerRef:db.prepare('SELECT * FROM wallet_entries WHERE user_id=? AND reference=?'),
  ledgerInsert:db.prepare('INSERT INTO wallet_entries(id,user_id,reference,kind,coins,net_vnd,creator_vnd,platform_vnd,created) VALUES(?,?,?,?,?,?,?,?,?)'),
  mark:db.prepare('UPDATE console_wallet_mirror SET applied_at=COALESCE(applied_at,?) WHERE id=?'),
 };
}
function apply(dbStatements, entry) {
 const {owner,ledgerId,ledgerRef,ledgerInsert,mark} = dbStatements;
 // Check both uniqueness constraints even when the member replica is absent.
 const byId = ledgerId.get(entry.id), byRef = ledgerRef.get(entry.user_id,entry.reference);
 if (byId && !equal(byId,entry) || byRef && !equal(byRef,entry)) throw unavailable();
 if (!owner.get(entry.user_id)) return {applied:0,pending:1,verified:0};
 let inserted = 0;
 if (!byId && !byRef) {
  ledgerInsert.run(...FIELDS.map(field => entry[field]));
  inserted = 1;
 }
 // Mark only after the ledger insertion or exact canonical match has succeeded.
 mark.run(Date.now(),entry.id);
 return {applied:inserted,pending:0,verified:inserted?0:1};
}
/**
 * Validate the entire batch before writing. Queue and ledger share one SAVEPOINT.
 * Returns counts only; repeated source entries cannot add the same credit twice.
 */
export function stageWalletCredits(db, entries) {
 if (!Array.isArray(entries) || entries.length > 10000) throw invalid();
 const batch = entries.map(canonical);
 return sanitized(() => savepoint(db, () => {
  schema(db);
  const s=statements(db),counts={staged:0,applied:0,pending:0,duplicates:0},seen=new Set();
  for (const entry of batch) {
   const byId=s.queueId.get(entry.id),byRef=s.queueRef.get(entry.user_id,entry.reference);
   if (byId && !equal(byId,entry) || byRef && !equal(byRef,entry)) throw unavailable();
   if (!byId && !byRef) { s.queueInsert.run(...FIELDS.map(field=>entry[field])); counts.staged++; }
   else counts.duplicates++;
   const outcome=apply(s,entry);counts.applied+=outcome.applied;
   // Pending counts distinct canonical entries, not duplicate input rows.
   if (outcome.pending && !seen.has(entry.id)) counts.pending++;
   seen.add(entry.id);
  }
  return counts;
 }));
}
/** Replay after a cloud user is mirrored. Never creates users or changes other credits. */
export function flushWalletCreditsForUser(db,userId) {
 if (!boundedString(userId)) throw invalid();
 return sanitized(() => savepoint(db, () => {
  schema(db);
  const s=statements(db),rows=db.prepare('SELECT * FROM console_wallet_mirror WHERE user_id=? ORDER BY created,id').all(userId);
  const counts={applied:0,pending:0,verified:0};
  for (const stored of rows) {
   const entry=canonical(stored),outcome=apply(s,entry);
   counts.applied+=outcome.applied;counts.pending+=outcome.pending;counts.verified+=outcome.verified;
  }
  return counts;
 }));
}
