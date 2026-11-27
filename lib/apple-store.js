import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";

let appleLibPromise = null;
async function getAppleLib() {
  if (!appleLibPromise) {
    appleLibPromise = import("@apple/app-store-server-library").catch(() => null);
  }
  return appleLibPromise;
}

const error = (status, message) => Object.assign(new Error(message), { status });
const TRANSIENT_ERROR_CODES = new Set([
  "ETIMEDOUT", "ECONNRESET", "ECONNREFUSED", "EAI_AGAIN", "ENOTFOUND",
  "EHOSTUNREACH", "ENETUNREACH", "EPIPE", "UND_ERR_CONNECT_TIMEOUT",
  "UND_ERR_HEADERS_TIMEOUT", "UND_ERR_BODY_TIMEOUT", "UND_ERR_SOCKET"
]);
function isTransientVerificationError(err) {
  if (!err) return false;
  // HTTP 503 or @apple/app-store-server-library VerificationStatus.RETRYABLE_VERIFICATION_FAILURE (2)
  if (err.status === 503 || err.status === 2) return true;
  if (err.name === "AbortError" || err.name === "TimeoutError" || err.name === "FetchError") return true;
  if (TRANSIENT_ERROR_CODES.has(err.code) || TRANSIENT_ERROR_CODES.has(err.cause?.code)) return true;
  return false;
}
export function appleAccountUuid(userId) {
  const bytes = createHash("sha256").update("kinnect-apple-account-v1:" + userId).digest().subarray(0, 16);
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  const h = bytes.toString("hex");
  return [h.slice(0,8), h.slice(8,12), h.slice(12,16), h.slice(16,20), h.slice(20)].join("-");
}

// Trust only explicitly provisioned Apple roots; never trust an x5c root supplied by the client.
export function appleSignedDataVerifier({ env = process.env } = {}) {
  let instances;
  const enabled = () => env.APPLE_STORE_ENABLED === "true" && !!env.APPLE_ROOT_CA_FILES
    && ["Sandbox", "Production"].includes(env.APPLE_STORE_ENVIRONMENT)
    && (env.APPLE_STORE_ENVIRONMENT !== "Production" || Number(env.APPLE_APP_ID) > 0);
  async function verifiers() {
    if (!enabled()) throw error(503, "App Store chưa được cấu hình xác minh giao dịch.");
    if (!instances) {
      let files;
      try { files = JSON.parse(env.APPLE_ROOT_CA_FILES); }
      catch { throw error(503, "Cấu hình chứng chỉ gốc Apple không hợp lệ."); }
      if (!Array.isArray(files) || !files.length || files.some(x => typeof x !== "string"))
        throw error(503, "Thiếu chứng chỉ gốc Apple.");
      const lib = await getAppleLib();
      if (!lib || !lib.SignedDataVerifier) {
        throw error(503, "Thư viện Apple Store Server chưa được nạp.");
      }
      let roots;
      try { roots = await Promise.all(files.map(file => readFile(file))); }
      catch { throw error(503, "Không thể đọc chứng chỉ gốc Apple."); }
      const isProd = env.APPLE_STORE_ENVIRONMENT === "Production";
      const primary = new lib.SignedDataVerifier(
        roots, true,
        isProd ? lib.Environment.PRODUCTION : lib.Environment.SANDBOX,
        "app.kinnect.live",
        isProd ? Number(env.APPLE_APP_ID) : undefined
      );
      const sandbox = isProd
        ? new lib.SignedDataVerifier(roots, true, lib.Environment.SANDBOX, "app.kinnect.live", undefined)
        : null;
      instances = {
        primary,
        sandbox,
        invalidEnvironment: lib.VerificationStatus?.INVALID_ENVIRONMENT ?? 4
      };
    }
    return instances;
  }
  async function verifyWithFallback(method, jws) {
    const { primary, sandbox, invalidEnvironment } = await verifiers();
    try {
      return await primary[method](jws);
    } catch (err) {
      if (sandbox && err?.status === invalidEnvironment) {
        return await sandbox[method](jws);
      }
      throw err;
    }
  }
  return {
    enabled,
    verifyTransaction: async jws => verifyWithFallback("verifyAndDecodeTransaction", jws),
    verifyNotification: async jws => verifyWithFallback("verifyAndDecodeNotification", jws)
  };
}

export function createAppleStore({ db, products, verifier, env = process.env, clock = Date.now }) {
  verifier ||= appleSignedDataVerifier({ env });
  db.exec("CREATE TABLE IF NOT EXISTS apple_store_transactions(transaction_id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,product_id TEXT NOT NULL,state TEXT NOT NULL,signed_date INTEGER NOT NULL,verified INTEGER NOT NULL,environment TEXT NOT NULL DEFAULT '')");
  if (!db.prepare("PRAGMA table_info(apple_store_transactions)").all().some(c => c.name === "environment")) {
    db.exec("ALTER TABLE apple_store_transactions ADD COLUMN environment TEXT NOT NULL DEFAULT ''");
  }
  db.exec("CREATE TABLE IF NOT EXISTS apple_store_revocations(transaction_id TEXT PRIMARY KEY,product_id TEXT NOT NULL)");
  const owned = userId => db.prepare("SELECT DISTINCT product_id FROM apple_store_transactions WHERE user_id=? AND state='PURCHASED'").all(userId).map(x => x.product_id);
  function validate(transaction) {
    if (transaction.bundleId !== "app.kinnect.live" || !/^\d{1,40}$/.test(transaction.transactionId || "")
        || !products.some(p => p.id === transaction.productId) || transaction.quantity !== 1
        || transaction.type !== "Non-Consumable") throw error(422, "Giao dịch App Store không khớp sản phẩm.");
  }
  async function verify(userId, productId, jws) {
    if (!verifier.enabled()) throw error(503, "App Store chưa mở thanh toán.");
    if (typeof jws !== "string" || jws.length < 20 || jws.length > 60000) throw error(400, "Thiếu giao dịch Apple đã ký.");
    let transaction;
    try { transaction = await verifier.verifyTransaction(jws); }
    catch (err) {
      if (isTransientVerificationError(err)) {
        throw error(503, err?.status === 503 && err.message ? err.message : "Tạm thời không kết nối được dịch vụ xác minh Apple. Vui lòng thử lại sau.");
      }
      throw error(422, "Không xác minh được chữ ký giao dịch Apple.");
    }
    validate(transaction);
    if (transaction.productId !== productId || transaction.appAccountToken?.toLowerCase() !== appleAccountUuid(userId))
      throw error(403, "Giao dịch Apple không thuộc tài khoản hoặc sản phẩm này.");
    if (!db.prepare("SELECT 1 FROM users WHERE id=? AND suspended=0").get(userId))
      throw error(401, "Tài khoản không còn hoạt động.");
    const prior = db.prepare("SELECT * FROM apple_store_transactions WHERE transaction_id=?").get(transaction.transactionId);
    if (prior && (prior.user_id !== userId || prior.product_id !== productId))
      throw error(409, "Giao dịch Apple đã gắn với tài khoản khác.");
    const state = transaction.revocationDate || prior?.state === "CANCELLED" || db.prepare("SELECT 1 FROM apple_store_revocations WHERE transaction_id=?").get(transaction.transactionId) ? "CANCELLED" : "PURCHASED";
    const environment = typeof transaction.environment === "string" ? transaction.environment : "";
    db.prepare("INSERT INTO apple_store_transactions(transaction_id,user_id,product_id,state,signed_date,verified,environment) VALUES(?,?,?,?,?,?,?) ON CONFLICT(transaction_id) DO UPDATE SET state=excluded.state,signed_date=MAX(signed_date,excluded.signed_date),verified=excluded.verified,environment=CASE WHEN excluded.environment<>'' THEN excluded.environment ELSE apple_store_transactions.environment END")
      .run(transaction.transactionId, userId, productId, state, Number(transaction.signedDate) || clock(), clock(), environment);
    return { state, owned: owned(userId), transactionId: transaction.transactionId };
  }
  async function handleNotification(jws) {
    if (!verifier.enabled()) throw error(503, "App Store chưa được cấu hình.");
    let notification, transaction;
    try {
      notification = await verifier.verifyNotification(jws);
      const signed = notification.data?.signedTransactionInfo;
      if (!signed) return { ok: true };
      transaction = await verifier.verifyTransaction(signed);
    } catch (err) {
      if (isTransientVerificationError(err)) {
        throw error(503, err?.status === 503 && err.message ? err.message : "Tạm thời không kết nối được dịch vụ xác minh Apple. Vui lòng thử lại sau.");
      }
      throw error(422, "Thông báo Apple không có chữ ký hợp lệ.");
    }
    validate(transaction);
    const prior = db.prepare("SELECT * FROM apple_store_transactions WHERE transaction_id=?").get(transaction.transactionId);
    // Record revocation even if the notification arrives before the device submits its purchase.
    const revoked = transaction.revocationDate || ["REFUND", "REVOKE"].includes(notification.notificationType);
    if (revoked) db.prepare("INSERT OR IGNORE INTO apple_store_revocations VALUES(?,?)")
        .run(transaction.transactionId, transaction.productId);
    // Notifications never invent ownership for an unknown account.
    if (!prior) return { ok: true };
    if (transaction.productId !== prior.product_id || transaction.appAccountToken?.toLowerCase() !== appleAccountUuid(prior.user_id))
      throw error(403, "Thông báo Apple không khớp tài khoản.");
    if (revoked)
      db.prepare("UPDATE apple_store_transactions SET state='CANCELLED',verified=? WHERE transaction_id=?").run(clock(), transaction.transactionId);
    return { ok: true };
  }
  return { enabled: verifier.enabled, owned, verify, handleNotification };
}
