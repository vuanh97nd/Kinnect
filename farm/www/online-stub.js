/**
 * Lớp online-shaped: cùng contract khi gắn server sau.
 * MVP dùng stub làng (NPC) — không khóa chơi khi chưa có máy chủ.
 */
(function (global) {
  const SAVE_KEY = "kinnect-farm-v1";

  class StubValleyRoster {
    constructor() {
      this.connected = false;
      this.neighbors = [
        {
          id: "npc-lan",
          kind: "stub",
          name: "Lan (hàng xóm làng)",
          note: "Chỗ dành cho bạn bè — hiện là hàng xóm làng (giả lập).",
          bondHint: "Thích rau thơm",
        },
        {
          id: "slot-friend-1",
          kind: "empty-slot",
          name: "Chỗ bạn — trống",
          note: "Dấu bạn sẽ hiện khi nối máy chủ.",
          bondHint: null,
        },
      ];
    }
    async list() {
      return this.neighbors.map((n) => ({ ...n }));
    }
    statusText() {
      return this.connected
        ? "Đã nối máy chủ — thấy dấu bạn trên thung lũng."
        : "Chưa nối máy chủ — đang chơi với hàng xóm làng (NPC).";
    }
  }

  class StubGiftMailbox {
    constructor() {
      this.outbox = [];
      this.inbox = [
        {
          id: "gift-welcome",
          from: "Lan (hàng xóm làng)",
          label: "Hạt giống làng",
          amount: 1,
          crop: "herb",
        },
      ];
    }
    async peekInbox() {
      return this.inbox.slice();
    }
    async send(gift) {
      this.outbox.push({ ...gift, queuedAt: Date.now(), pendingSync: true });
      return { ok: true, queued: true };
    }
    async takeInboxItem(id) {
      const i = this.inbox.findIndex((g) => g.id === id);
      if (i < 0) return null;
      return this.inbox.splice(i, 1)[0];
    }
  }

  class StubPresence {
    async snapshot() {
      return { onlineFriends: 0, valleyPulse: "local", mode: "stub" };
    }
  }

  class StubKinnectRemote {
    /** Dây mờ sang nông trại kế (giả lập). */
    async remoteHints() {
      return [{ toward: "east", label: "Nông trại kế (giả lập)", strength: 0.35 }];
    }
  }

  const api = {
    SAVE_KEY,
    valley: new StubValleyRoster(),
    mailbox: new StubGiftMailbox(),
    presence: new StubPresence(),
    remote: new StubKinnectRemote(),
    async connectServer() {
      // Phase sau: thay stub bằng client–server thật.
      return { ok: false, reason: "Máy chủ chưa gắn — giữ chế độ làng stub." };
    },
  };

  global.KinnectOnline = api;
})(window);
