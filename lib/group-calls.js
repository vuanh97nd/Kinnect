const MAX_GROUP_CALL_PARTICIPANTS = 8;

export function createGroupCalls({ social, wss, send, isBusy = () => false }) {
  // groupId -> { groupId, mode, startedAt, members: Map<ws.id, { ws, userId, muted, video }>, blockedPairs: Set<string> }
  const rooms = new Map();

  const inGroupCall = (userId) => {
    for (const room of rooms.values()) {
      for (const entry of room.members.values()) {
        if (entry.userId === userId) return true;
      }
    }
    return false;
  };

  const isGroupMember = (groupId, userId) => {
    try {
      return !!social.db.prepare("SELECT 1 FROM group_members WHERE group_id=? AND user_id=?").get(groupId, userId);
    } catch {
      return false;
    }
  };

  const groupMemberIds = (groupId) => {
    try {
      return new Set(social.db.prepare("SELECT user_id FROM group_members WHERE group_id=?").all(groupId).map((r) => r.user_id));
    } catch {
      return new Set();
    }
  };

  function serializeParticipants(room, viewerId = null) {
    const out = [];
    for (const [peerId, entry] of room.members.entries()) {
      const u = social.user(entry.userId);
      if (!u || u.suspended) continue;
      if (viewerId && entry.userId !== viewerId && social.blocked(viewerId, entry.userId)) continue;
      out.push({
        peerId,
        userId: u.id,
        name: u.name,
        username: u.username,
        avatar: u.avatar ? "/api/users/" + u.id + "/avatar" : null,
        muted: !!entry.muted,
        video: !!entry.video,
      });
    }
    return out;
  }

  function state(groupId, viewerId = null) {
    const room = rooms.get(groupId);
    if (!room || !room.members.size) {
      return { active: false, groupId, mode: "audio", startedAt: null, participants: [] };
    }
    const participants = serializeParticipants(room, viewerId);
    if (!participants.length) {
      return { active: false, groupId, mode: "audio", startedAt: null, participants: [] };
    }
    return {
      active: true,
      groupId,
      mode: room.mode,
      startedAt: room.startedAt,
      participants,
    };
  }

  function broadcastGroupState(groupId) {
    const memberIds = groupMemberIds(groupId);
    for (const client of wss.clients) {
      if (memberIds.has(client.userId) && social.authenticate(client.authRequest)) {
        send(client, { type: "group-call-state", ...state(groupId, client.userId) });
      }
    }
  }

  function leave(ws) {
    const groupId = ws.groupCallId;
    if (!groupId) return;
    ws.groupCallId = null;
    const room = rooms.get(groupId);
    if (!room) return;
    if (!room.members.delete(ws.id)) return;
    if (room.blockedPairs) {
      for (const pairKey of [...room.blockedPairs]) {
        if (pairKey.startsWith(ws.id + ":") || pairKey.endsWith(":" + ws.id)) {
          room.blockedPairs.delete(pairKey);
        }
      }
    }
    for (const entry of room.members.values()) {
      if (social.authenticate(entry.ws.authRequest) && !social.blocked(ws.userId, entry.ws.userId)) {
        send(entry.ws, { type: "group-call-peer-left", groupId, peerId: ws.id, userId: ws.userId });
      }
    }
    if (!room.members.size) rooms.delete(groupId);
    broadcastGroupState(groupId);
  }

  function handle(ws, m) {
    if (!String(m.type || "").startsWith("group-call-")) return false;
    const error = (message) => send(ws, { type: "group-call-error", groupId: m.groupId || ws.groupCallId || "", message });

    if (m.type === "group-call-join") {
      const groupId = typeof m.groupId === "string" ? m.groupId.trim() : "";
      if (!groupId || !isGroupMember(groupId, ws.userId)) {
        error("Bạn không phải thành viên nhóm này.");
        return true;
      }
      if (ws.room) {
        error("Hãy rời phòng Live trước khi tham gia gọi nhóm.");
        return true;
      }
      if (isBusy(ws.userId)) {
        error("Bạn đang trong một cuộc gọi khác.");
        return true;
      }
      if (ws.groupCallId && ws.groupCallId !== groupId) leave(ws);
      let room = rooms.get(groupId);
      const mode = m.mode === "video" ? "video" : "audio";
      if (!room) {
        room = { groupId, mode, startedAt: Date.now(), members: new Map(), blockedPairs: new Set() };
        rooms.set(groupId, room);
      } else if (mode === "video" && room.mode !== "video") {
        room.mode = "video";
      }
      // Replace previous socket of same user in the same group call to avoid echo duplicates.
      for (const [oldPeerId, entry] of [...room.members.entries()]) {
        if (entry.userId === ws.userId && oldPeerId !== ws.id) {
          room.members.delete(oldPeerId);
          if (room.blockedPairs) {
            for (const pairKey of [...room.blockedPairs]) {
              if (pairKey.startsWith(oldPeerId + ":") || pairKey.endsWith(":" + oldPeerId)) {
                room.blockedPairs.delete(pairKey);
              }
            }
          }
          entry.ws.groupCallId = null;
          send(entry.ws, { type: "group-call-ended", groupId, reason: "joined_elsewhere" });
          for (const other of room.members.values()) {
            if (social.authenticate(other.ws.authRequest) && !social.blocked(ws.userId, other.ws.userId)) {
              send(other.ws, { type: "group-call-peer-left", groupId, peerId: oldPeerId, userId: ws.userId });
            }
          }
        }
      }
      if (!room.members.has(ws.id) && room.members.size >= MAX_GROUP_CALL_PARTICIPANTS) {
        error("Cuộc gọi nhóm đã đạt tối đa " + MAX_GROUP_CALL_PARTICIPANTS + " người tham gia.");
        return true;
      }
      room.blockedPairs ??= new Set();
      for (const [otherPeerId, other] of room.members.entries()) {
        if (otherPeerId !== ws.id && other.userId !== ws.userId && social.blocked(ws.userId, other.userId)) {
          room.blockedPairs.add(ws.id < otherPeerId ? `${ws.id}:${otherPeerId}` : `${otherPeerId}:${ws.id}`);
        }
      }
      const existingPeerIds = [...room.members.entries()]
        .filter(([id, entry]) => id !== ws.id && !social.blocked(ws.userId, entry.userId))
        .map(([id]) => id);
      room.members.set(ws.id, { ws, userId: ws.userId, muted: false, video: mode === "video" });
      ws.groupCallId = groupId;
      const participants = serializeParticipants(room, ws.userId);
      send(ws, {
        type: "group-call-joined",
        groupId,
        mode: room.mode,
        selfId: ws.id,
        peers: existingPeerIds,
        participants,
      });
      for (const entry of room.members.values()) {
        if (entry.ws !== ws && social.authenticate(entry.ws.authRequest) && !social.blocked(entry.userId, ws.userId)) {
          send(entry.ws, {
            type: "group-call-peer-joined",
            groupId,
            peerId: ws.id,
            userId: ws.userId,
            name: ws.name,
            video: mode === "video",
          });
        }
      }
      broadcastGroupState(groupId);
      return true;
    }

    if (m.type === "group-call-leave") {
      leave(ws);
      return true;
    }

    if (m.type === "group-call-media") {
      const groupId = ws.groupCallId;
      const room = groupId && rooms.get(groupId);
      const entry = room?.members.get(ws.id);
      if (!entry) return true;
      if (typeof m.muted === "boolean") entry.muted = m.muted;
      if (typeof m.video === "boolean") entry.video = m.video;
      broadcastGroupState(groupId);
      return true;
    }

    if (m.type === "group-call-signal") {
      const groupId = ws.groupCallId;
      const room = groupId && rooms.get(groupId);
      if (!room || !room.members.has(ws.id)) return true;
      const target = room.members.get(m.to);
      if (!target || target.ws === ws || !social.authenticate(target.ws.authRequest)) return true;
      if (social.blocked(ws.userId, target.userId)) return true;
      const desc = m.description || m.signal?.description;
      const cand = m.candidate || m.signal?.candidate;
      if (desc && ["offer", "answer"].includes(desc.type) && typeof desc.sdp === "string" && desc.sdp.length < 100000) {
        send(target.ws, { type: "group-call-signal", groupId, from: ws.id, fromUserId: ws.userId, description: desc });
      } else if (cand && typeof cand === "object") {
        send(target.ws, { type: "group-call-signal", groupId, from: ws.id, fromUserId: ws.userId, candidate: cand });
      }
      return true;
    }

    return true;
  }

  function disconnect(ws) {
    leave(ws);
  }

  function enforce() {
    for (const [groupId, room] of [...rooms.entries()]) {
      for (const entry of [...room.members.values()]) {
        if (!social.authenticate(entry.ws.authRequest) || !isGroupMember(groupId, entry.userId)) {
          leave(entry.ws);
        }
      }
      if (!rooms.has(groupId)) continue;
      room.blockedPairs ??= new Set();
      const members = [...room.members.entries()];
      const currentBlocked = new Set();
      let blockChanged = false;
      for (let i = 0; i < members.length; i++) {
        const [peerA, a] = members[i];
        for (let j = i + 1; j < members.length; j++) {
          const [peerB, b] = members[j];
          if (a.userId === b.userId) continue;
          if (social.blocked(a.userId, b.userId)) {
            const pairKey = peerA < peerB ? `${peerA}:${peerB}` : `${peerB}:${peerA}`;
            currentBlocked.add(pairKey);
            if (!room.blockedPairs.has(pairKey)) {
              blockChanged = true;
              if (social.authenticate(a.ws.authRequest)) {
                send(a.ws, { type: "group-call-peer-left", groupId, peerId: peerB, userId: b.userId });
              }
              if (social.authenticate(b.ws.authRequest)) {
                send(b.ws, { type: "group-call-peer-left", groupId, peerId: peerA, userId: a.userId });
              }
            }
          }
        }
      }
      if (room.blockedPairs.size !== currentBlocked.size) blockChanged = true;
      room.blockedPairs = currentBlocked;
      if (blockChanged) broadcastGroupState(groupId);
    }
  }

  return { handle, disconnect, enforce, state, isBusy: inGroupCall };
}
