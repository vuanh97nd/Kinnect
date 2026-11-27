/**
 * External alert delivery for high/critical AI Security Monitor findings.
 * Supports Email (reusing configured SMTP mailer) and optional Telegram Bot webhook.
 * Rate-limited per threatType+IP so an attack wave cannot flood the operator's inbox.
 */
export function createSecurityNotifier({
  env = process.env,
  sendEmail = null,
  mailReady = () => false,
  fetchImpl = fetch,
  clock = () => Date.now(),
  cooldownMs = 5 * 60 * 1000,
  logger = console,
} = {}) {
  const recent = new Map();

  function formatAlert(alert) {
    const sev = String(alert?.severity || "medium").toUpperCase();
    const threat = String(alert?.threatType || "unknown");
    const ip = String(alert?.subjectIp || "unknown");
    const actor = alert?.subjectActor ? ` (@${alert.subjectActor})` : "";
    const when = new Date(clock()).toLocaleString("vi-VN", { timeZone: "Asia/Ho_Chi_Minh" });
    const evidence = Array.isArray(alert?.evidence) ? alert.evidence.slice(0, 3) : [];
    const autoActionId = alert?.autoActionId || alert?.autoMitigation?.id || "";
    const mitigated = autoActionId ? "Đã kích hoạt chặn tạm tự động (TTL)" : "Đang ở chế độ cảnh báo / cần xem xét";
    const subject = `[Kinnect Security · ${sev}] ${threat} từ IP ${ip}`;
    const lines = [
      `⚠️ CẢNH BÁO BẢO MẬT KINNECT (${sev})`,
      `Thời gian: ${when}`,
      `Loại mối đe dọa: ${threat}`,
      `Nguồn: ${ip}${actor}`,
      `Trạng thái xử lý: ${mitigated}`,
      `Tóm tắt: ${alert?.summary || "Phát hiện hành vi bất thường."}`,
      ...(evidence.length ? ["Bằng chứng:", ...evidence.map((e) => ` - ${e}`)] : []),
      "Kiểm tra & hoàn tác (nếu cần): https://admin.kinnect.io.vn",
    ];
    return { subject, text: lines.join("\n") };
  }

  async function notify(alert) {
    if (!alert) return { sent: false, reason: "empty" };
    const sev = String(alert.severity || "").toLowerCase();
    const autoActionId = alert?.autoActionId || alert?.autoMitigation?.id || "";
    if (!["high", "critical"].includes(sev) && !autoActionId) {
      return { sent: false, reason: "below_severity" };
    }
    const now = clock();
    const key = `${alert.threatType || ""}|${alert.subjectIp || ""}`;
    const last = recent.get(key) || 0;
    if (now - last < cooldownMs) {
      return { sent: false, reason: "cooldown" };
    }
    recent.set(key, now);
    if (recent.size > 200) {
      for (const [k, ts] of recent) {
        if (now - ts >= cooldownMs) recent.delete(k);
      }
    }

    const { subject, text } = formatAlert(alert);
    const channels = [];

    const emailTo = String(env.SECURITY_ALERT_EMAIL || env.RESET_NOTIFY_EMAIL || "").trim();
    if (emailTo && typeof sendEmail === "function" && mailReady()) {
      try {
        await sendEmail({ to: emailTo, subject, text });
        channels.push("email");
      } catch (err) {
        logger?.warn?.("[security-alert] Email failed:", err?.message || err);
      }
    }

    const tgToken = String(env.KINNECT_TELEGRAM_BOT_TOKEN || "").trim();
    const tgChatId = String(env.KINNECT_TELEGRAM_CHAT_ID || "").trim();
    if (tgToken && tgChatId && typeof fetchImpl === "function") {
      try {
        const res = await fetchImpl(`https://api.telegram.org/bot${encodeURIComponent(tgToken)}/sendMessage`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            chat_id: tgChatId,
            text: text.slice(0, 3800),
            disable_web_page_preview: true,
          }),
          signal: AbortSignal.timeout(6000),
        });
        if (res.ok) channels.push("telegram");
        else logger?.warn?.("[security-alert] Telegram HTTP", res.status);
      } catch (err) {
        logger?.warn?.("[security-alert] Telegram failed:", err?.message || err);
      }
    }

    return { sent: channels.length > 0, channels };
  }

  return { notify, formatAlert };
}
