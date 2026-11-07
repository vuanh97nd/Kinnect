(() => {
  const CROPS = {
    herb: {
      id: "herb",
      name: "Rau thơm",
      emoji: "🌿",
      cost: 8,
      growDays: 2,
      sell: 18,
      color: "#5f7344",
      friends: ["grain"],
    },
    grain: {
      id: "grain",
      name: "Lúa",
      emoji: "🌾",
      cost: 10,
      growDays: 3,
      sell: 24,
      color: "#c9a227",
      friends: ["herb", "root"],
    },
    root: {
      id: "root",
      name: "Củ",
      emoji: "🥕",
      cost: 9,
      growDays: 2,
      sell: 20,
      color: "#b5673d",
      friends: ["grain"],
    },
  };

  const COLS = 5;
  const ROWS = 4;
  const STORAGE = () => window.KinnectOnline?.SAVE_KEY || "kinnect-farm-v1";

  const $ = (id) => document.getElementById(id);
  const canvas = $("farm");
  const ctx = canvas.getContext("2d");

  let state = defaultState();
  let tool = "select";
  let hover = null;
  let splashDone = false;

  function defaultState() {
    const plots = [];
    for (let y = 0; y < ROWS; y++) {
      for (let x = 0; x < COLS; x++) {
        plots.push({
          x,
          y,
          crop: null,
          watered: false,
          age: 0,
          echo: 0,
        });
      }
    }
    return {
      day: 1,
      season: "Khô",
      coins: 40,
      plots,
      bonds: [],
      harvested: 0,
      log: ["Chào mừng đến Kinnect Farm."],
      tutorialStep: 0,
    };
  }

  function save() {
    localStorage.setItem(STORAGE(), JSON.stringify(state));
  }

  function load() {
    try {
      const raw = localStorage.getItem(STORAGE());
      if (!raw) return false;
      const data = JSON.parse(raw);
      if (!data?.plots?.length) return false;
      state = data;
      return true;
    } catch {
      return false;
    }
  }

  function setStatus(msg) {
    $("status-line").textContent = msg;
  }

  function refreshHud() {
    $("day-label").textContent = `Ngày ${state.day} · ${state.season}`;
    $("coin-label").textContent = `◎ ${state.coins}`;
    const note = window.KinnectOnline?.valley?.statusText?.() || "";
    if ($("net-note")) $("net-note").textContent = note;
  }

  function plotAt(x, y) {
    return state.plots.find((p) => p.x === x && p.y === y);
  }

  function neighbors(plot) {
    const dirs = [
      [1, 0],
      [-1, 0],
      [0, 1],
      [0, -1],
    ];
    return dirs
      .map(([dx, dy]) => plotAt(plot.x + dx, plot.y + dy))
      .filter(Boolean);
  }

  function recomputeBonds() {
    const bonds = [];
    const seen = new Set();
    for (const p of state.plots) {
      if (!p.crop || p.age < 1) continue;
      for (const n of neighbors(p)) {
        if (!n.crop || n.age < 1) continue;
        const a = `${p.x},${p.y}`;
        const b = `${n.x},${n.y}`;
        const key = a < b ? `${a}|${b}` : `${b}|${a}`;
        if (seen.has(key)) continue;
        seen.add(key);
        const ca = CROPS[p.crop];
        const cb = CROPS[n.crop];
        const friendly = ca.friends.includes(cb.id) || cb.friends.includes(ca.id);
        if (!friendly) continue;
        const level =
          p.age >= ca.growDays && n.age >= cb.growDays
            ? "Cộng hưởng"
            : p.watered && n.watered
              ? "Ổn"
              : "Lờ mờ";
        bonds.push({ ax: p.x, ay: p.y, bx: n.x, by: n.y, level });
      }
    }
    state.bonds = bonds;
  }

  function bondBonus(plot) {
    let mult = 1;
    for (const b of state.bonds) {
      const hit =
        (b.ax === plot.x && b.ay === plot.y) ||
        (b.bx === plot.x && b.by === plot.y);
      if (!hit) continue;
      if (b.level === "Cộng hưởng") mult = Math.max(mult, 1.5);
      else if (b.level === "Ổn") mult = Math.max(mult, 1.2);
      else mult = Math.max(mult, 1.05);
    }
    return mult;
  }

  /* ---- Vẽ nông trại (góc isometric nhẹ, cổ điển) ---- */
  function resizeCanvas() {
    const wrap = canvas.parentElement;
    const w = wrap.clientWidth;
    const h = wrap.clientHeight;
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = Math.floor(w * dpr);
    canvas.height = Math.floor(h * dpr);
    canvas.style.width = `${w}px`;
    canvas.style.height = `${h}px`;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    draw();
  }

  function iso(x, y) {
    const wrap = canvas.parentElement;
    const tw = 70;
    const th = 36;
    const ox = wrap.clientWidth / 2;
    const oy = wrap.clientHeight * 0.28;
    return {
      sx: ox + (x - y) * (tw / 2),
      sy: oy + (x + y) * (th / 2),
      tw,
      th,
    };
  }

  function drawDiamond(sx, sy, tw, th, fill, stroke) {
    ctx.beginPath();
    ctx.moveTo(sx, sy);
    ctx.lineTo(sx + tw / 2, sy + th / 2);
    ctx.lineTo(sx, sy + th);
    ctx.lineTo(sx - tw / 2, sy + th / 2);
    ctx.closePath();
    ctx.fillStyle = fill;
    ctx.fill();
    if (stroke) {
      ctx.strokeStyle = stroke;
      ctx.lineWidth = 1.2;
      ctx.stroke();
    }
  }

  function draw() {
    const wrap = canvas.parentElement;
    const W = wrap.clientWidth;
    const H = wrap.clientHeight;
    ctx.clearRect(0, 0, W, H);

    // trời / đồi
    const sky = ctx.createLinearGradient(0, 0, 0, H);
    sky.addColorStop(0, state.season === "Ẩm" ? "#6a8aa8" : "#87a7c4");
    sky.addColorStop(0.45, "#c5d6b8");
    sky.addColorStop(1, "#8f9e5f");
    ctx.fillStyle = sky;
    ctx.fillRect(0, 0, W, H);

    // núi xa
    ctx.fillStyle = "rgba(90,100,80,0.35)";
    ctx.beginPath();
    ctx.moveTo(0, H * 0.38);
    ctx.lineTo(W * 0.25, H * 0.22);
    ctx.lineTo(W * 0.5, H * 0.36);
    ctx.lineTo(W * 0.72, H * 0.2);
    ctx.lineTo(W, H * 0.34);
    ctx.lineTo(W, H * 0.42);
    ctx.lineTo(0, H * 0.42);
    ctx.fill();

    // nhà kho nhỏ
    const barn = iso(-1.2, 1.2);
    ctx.fillStyle = "#8b5e34";
    ctx.fillRect(barn.sx - 28, barn.sy - 36, 56, 40);
    ctx.fillStyle = "#5c3b1e";
    ctx.beginPath();
    ctx.moveTo(barn.sx - 34, barn.sy - 36);
    ctx.lineTo(barn.sx, barn.sy - 58);
    ctx.lineTo(barn.sx + 34, barn.sy - 36);
    ctx.fill();

    // dây remote stub
    const remote = state._remoteHint;
    if (remote) {
      const edge = iso(COLS - 0.2, 1.5);
      ctx.strokeStyle = "rgba(122,107,79,0.45)";
      ctx.setLineDash([4, 5]);
      ctx.beginPath();
      ctx.moveTo(edge.sx, edge.sy);
      ctx.lineTo(W - 20, edge.sy - 30);
      ctx.stroke();
      ctx.setLineDash([]);
      ctx.fillStyle = "rgba(44,36,25,0.65)";
      ctx.font = "12px Georgia, serif";
      ctx.fillText(remote.label, W - 150, edge.sy - 36);
    }

    // ô đất (vẽ từ xa tới gần)
    const ordered = [...state.plots].sort((a, b) => a.x + a.y - (b.x + b.y));
    for (const p of ordered) {
      const { sx, sy, tw, th } = iso(p.x, p.y);
      let soil = p.watered ? "#6b4f2e" : "#8a6a3f";
      if (p.echo > 0) soil = "#9a7a45";
      drawDiamond(sx, sy, tw, th, soil, "#5c3b1e");
      // cạnh bên
      ctx.fillStyle = "rgba(60,40,20,0.35)";
      ctx.beginPath();
      ctx.moveTo(sx - tw / 2, sy + th / 2);
      ctx.lineTo(sx, sy + th);
      ctx.lineTo(sx, sy + th + 8);
      ctx.lineTo(sx - tw / 2, sy + th / 2 + 8);
      ctx.fill();

      if (hover && hover.x === p.x && hover.y === p.y) {
        drawDiamond(sx, sy, tw, th, "rgba(255,240,200,0.25)", "#efe0c4");
      }

      if (p.crop) {
        const c = CROPS[p.crop];
        const ready = p.age >= c.growDays;
        const scale = 0.55 + Math.min(p.age / c.growDays, 1) * 0.45;
        ctx.save();
        ctx.translate(sx, sy + th * 0.15);
        ctx.scale(scale, scale);
        ctx.font = "28px serif";
        ctx.textAlign = "center";
        ctx.fillText(c.emoji, 0, 0);
        ctx.restore();
        if (ready) {
          ctx.fillStyle = "#f3e6d0";
          ctx.beginPath();
          ctx.arc(sx + 18, sy + 8, 4, 0, Math.PI * 2);
          ctx.fill();
        }
      }
    }

    // dây Kinnect
    for (const b of state.bonds) {
      const A = iso(b.ax, b.ay);
      const B = iso(b.bx, b.by);
      const alpha =
        b.level === "Cộng hưởng" ? 0.9 : b.level === "Ổn" ? 0.65 : 0.4;
      ctx.strokeStyle = `rgba(122,107,79,${alpha})`;
      ctx.lineWidth = b.level === "Cộng hưởng" ? 3 : 2;
      ctx.beginPath();
      ctx.moveTo(A.sx, A.sy + 10);
      ctx.lineTo(B.sx, B.sy + 10);
      ctx.stroke();
      if (b.level === "Cộng hưởng") {
        ctx.fillStyle = "rgba(201,162,39,0.85)";
        ctx.beginPath();
        ctx.arc((A.sx + B.sx) / 2, (A.sy + B.sy) / 2 + 10, 3.5, 0, Math.PI * 2);
        ctx.fill();
      }
    }
  }

  function canvasToPlot(clientX, clientY) {
    const rect = canvas.getBoundingClientRect();
    const mx = clientX - rect.left;
    const my = clientY - rect.top;
    let best = null;
    let bestDist = 40;
    for (const p of state.plots) {
      const { sx, sy, th } = iso(p.x, p.y);
      const cx = sx;
      const cy = sy + th / 2;
      const d = Math.hypot(mx - cx, my - cy);
      if (d < bestDist) {
        bestDist = d;
        best = p;
      }
    }
    return best;
  }

  function useToolOn(plot) {
    if (!plot) return;
    if (tool === "select") {
      describePlot(plot);
      return;
    }
    if (tool.startsWith("plant-")) {
      const cropId = tool.replace("plant-", "");
      const crop = CROPS[cropId];
      if (plot.crop) {
        setStatus("Ô này đã có cây. Thu hoạch hoặc chọn ô trống.");
        return;
      }
      if (state.coins < crop.cost) {
        setStatus(`Không đủ ◎ để trồng ${crop.name} (cần ${crop.cost}).`);
        return;
      }
      state.coins -= crop.cost;
      plot.crop = cropId;
      plot.age = 0;
      plot.watered = false;
      recomputeBonds();
      save();
      refreshHud();
      draw();
      setStatus(`Đã trồng ${crop.name}. Tưới nước và đặt cây tương thích cạnh nhau để tạo dây.`);
      return;
    }
    if (tool === "water") {
      if (!plot.crop) {
        setStatus("Ô trống — hãy trồng trước.");
        return;
      }
      plot.watered = true;
      recomputeBonds();
      save();
      draw();
      setStatus(`Đã tưới ${CROPS[plot.crop].name}. Dây Kinnect có thể sáng hơn.`);
      return;
    }
    if (tool === "harvest") {
      if (!plot.crop) {
        setStatus("Không có gì để thu hoạch.");
        return;
      }
      const crop = CROPS[plot.crop];
      if (plot.age < crop.growDays) {
        setStatus(`${crop.name} chưa chín (ngày ${plot.age}/${crop.growDays}).`);
        return;
      }
      const gain = Math.round(crop.sell * bondBonus(plot));
      state.coins += gain;
      state.harvested += 1;
      plot.echo = 2;
      plot.crop = null;
      plot.age = 0;
      plot.watered = false;
      recomputeBonds();
      save();
      refreshHud();
      draw();
      setStatus(`Thu hoạch +◎${gain}. Để lại Vang trên đất trong vài ngày.`);
    }
  }

  function describePlot(plot) {
    const tip = $("tooltip");
    if (!plot.crop) {
      tip.textContent =
        plot.echo > 0
          ? `Ô trống · còn Vang (${plot.echo} ngày) — hút vật nuôi/NPC sau này.`
          : "Ô đất trống — chọn hạt trên thanh công cụ rồi chạm ô.";
      tip.classList.remove("hidden");
      return;
    }
    const c = CROPS[plot.crop];
    const ready = plot.age >= c.growDays ? "đã chín" : `lớn ${plot.age}/${c.growDays}`;
    tip.textContent = `${c.name} · ${ready}${plot.watered ? " · đã tưới" : " · chưa tưới"} · thưởng dây ×${bondBonus(plot).toFixed(2)}`;
    tip.classList.remove("hidden");
  }

  function endDay() {
    for (const p of state.plots) {
      if (p.crop && p.watered) {
        p.age += 1;
        p.watered = false;
      } else if (p.crop && !p.watered) {
        // khô hạn nhẹ: không lớn
      }
      if (p.echo > 0) p.echo -= 1;
    }
    state.day += 1;
    if (state.day % 5 === 0) {
      state.season = state.season === "Khô" ? "Ẩm" : "Khô";
      state.log.unshift(
        state.season === "Ẩm"
          ? "Nhịp mưa tới — ruộng ẩm hơn, sương trên bậc thang."
          : "Mùa khô trở lại — đường đá lộ ra."
      );
    }
    recomputeBonds();
    const resonate = state.bonds.filter((b) => b.level === "Cộng hưởng").length;
    state.log.unshift(
      `Hết ngày ${state.day - 1}. ${resonate} dây Cộng hưởng. Đồng bộ thung lũng: chờ máy chủ.`
    );
    save();
    refreshHud();
    draw();
    openAlmanac(true);
    setStatus("Đã đóng ngày. Xem sổ tay — một dấu nối đang chờ đồng bộ.");
  }

  async function openAlmanac(fromEndDay) {
    recomputeBonds();
    const body = $("almanac-body");
    const bonds = state.bonds
      .map((b) => `<li>${b.level}: (${b.ax},${b.ay}) ↔ (${b.bx},${b.by})</li>`)
      .join("") || "<li>Chưa có dây — trồng cây tương thích cạnh nhau.</li>";
    const logs = state.log.slice(0, 5).map((l) => `<li>${l}</li>`).join("");
    const net = window.KinnectOnline?.valley?.statusText?.() || "";
    body.innerHTML = `
      <p class="muted">${net}</p>
      <p><strong>Ngày ${state.day}</strong> · Mùa ${state.season} · ◎ ${state.coins} · Đã thu ${state.harvested}</p>
      <h3 style="font-family:Georgia,serif;font-size:1rem;margin:12px 0 6px">Mạng Kinnect</h3>
      <ul>${bonds}</ul>
      <h3 style="font-family:Georgia,serif;font-size:1rem;margin:12px 0 6px">Nhịp gần đây</h3>
      <ul>${logs}</ul>
      ${fromEndDay ? "<p class=\"muted\">Một dấu nối đang chờ đồng bộ khi máy chủ sẵn.</p>" : ""}
    `;
    $("modal-almanac").classList.remove("hidden");
  }

  async function openValley() {
    const list = await window.KinnectOnline.valley.list();
    $("valley-status").textContent = window.KinnectOnline.valley.statusText();
    $("valley-list").innerHTML = list
      .map(
        (n) => `
      <li class="${n.kind === "empty-slot" ? "slot-empty" : ""}">
        <strong>${n.name}</strong><br/>
        <span class="muted">${n.note}${n.bondHint ? " · " + n.bondHint : ""}</span>
      </li>`
      )
      .join("");
    $("modal-valley").classList.remove("hidden");
  }

  async function openMarket() {
    const inbox = await window.KinnectOnline.mailbox.peekInbox();
    $("market-note").textContent =
      "Chợ đang họp với làng — dấu bạn sẽ hiện khi nối máy chủ.";
    const stalls = [
      {
        id: "npc-seed",
        title: "Lan · đổi hạt",
        detail: "Tặng ◎12 nhận hạt Lúa (hàng xóm làng)",
        action: "buy-grain",
      },
      ...inbox.map((g) => ({
        id: g.id,
        title: `${g.from}`,
        detail: `${g.label} — nhận vào túi giống`,
        action: "take:" + g.id,
      })),
      {
        id: "friend-slot",
        title: "Chỗ bạn (trống)",
        detail: "Ô dành sẵn cho người chơi khi nối máy chủ",
        action: null,
      },
    ];
    $("market-stalls").innerHTML = stalls
      .map((s) => {
        const btn = s.action
          ? `<button type="button" class="btn tiny" data-stall="${s.action}">Chọn</button>`
          : `<span class="muted">Chờ nối</span>`;
        return `<div class="stall"><div><strong>${s.title}</strong><br/><span class="muted">${s.detail}</span></div>${btn}</div>`;
      })
      .join("");
    $("modal-market").classList.remove("hidden");
  }

  async function handleStall(action) {
    if (action === "buy-grain") {
      if (state.coins < 12) {
        setStatus("Không đủ ◎.");
        return;
      }
      state.coins -= 12;
      // trồng nhanh: hoàn tiền dưới dạng “có hạt” — cộng 1 lần trồng miễn phí giả lập bằng +cost grain vào ví ảo: đơn giản cộng lại 10 và setStatus
      state.coins += 0;
      state.log.unshift("Đổi với Lan: có thêm giống Lúa (đã trừ ◎12; hoàn 10 ◎ như túi giống).");
      state.coins += 10;
      await window.KinnectOnline.mailbox.send({
        to: "slot-friend-1",
        label: "Lời chào từ nông trại bạn",
        pendingSync: true,
      });
      save();
      refreshHud();
      setStatus("Đã đổi với Lan. Quà gửi bạn đã vào hàng chờ đồng bộ.");
      $("modal-market").classList.add("hidden");
      return;
    }
    if (action.startsWith("take:")) {
      const id = action.slice(5);
      const gift = await window.KinnectOnline.mailbox.takeInboxItem(id);
      if (!gift) return;
      state.coins += 8;
      state.log.unshift(`Nhận ${gift.label} từ ${gift.from}.`);
      save();
      refreshHud();
      setStatus(`Đã nhận quà làng: ${gift.label}.`);
      openMarket();
    }
  }

  /* ---- Splash & màn hình ---- */
  async function runSplash() {
    await wait(1100);
    $("splash-kinnect").classList.add("fade-out");
    await wait(700);
    $("splash-kinnect").classList.add("hidden");
    $("splash-game").classList.remove("hidden");
    await wait(1400);
    $("splash-game").classList.add("fade-out");
    await wait(700);
    $("splash-game").classList.add("hidden");
    $("title-screen").classList.remove("hidden");
    refreshHud();
    splashDone = true;
  }

  function wait(ms) {
    return new Promise((r) => setTimeout(r, ms));
  }

  function enterGame(isNew) {
    if (isNew) {
      state = defaultState();
      localStorage.removeItem(STORAGE());
      save();
    } else if (!load()) {
      state = defaultState();
      save();
    }
    recomputeBonds();
    $("title-screen").classList.add("hidden");
    $("game-screen").classList.remove("hidden");
    refreshHud();
    resizeCanvas();
    window.KinnectOnline.remote.remoteHints().then((hints) => {
      state._remoteHint = hints[0];
      draw();
    });
    setStatus("Chạm ô đất để trồng. Cây tương thích cạnh nhau sẽ tạo dây Kinnect.");
  }

  /* ---- Sự kiện ---- */
  document.querySelectorAll(".tool").forEach((btn) => {
    btn.addEventListener("click", () => {
      document.querySelectorAll(".tool").forEach((b) => b.classList.remove("active"));
      btn.classList.add("active");
      tool = btn.dataset.tool;
      const labels = {
        select: "Đang chọn ô — chạm để xem.",
        "plant-herb": "Trồng Rau thơm (◎8). Hợp với Lúa.",
        "plant-grain": "Trồng Lúa (◎10). Hợp với Rau thơm và Củ.",
        "plant-root": "Trồng Củ (◎9). Hợp với Lúa.",
        water: "Tưới ô có cây.",
        harvest: "Thu hoạch khi chín (chấm sáng trên cây).",
      };
      setStatus(labels[tool] || "");
    });
  });

  function pointer(e) {
    const t = e.touches ? e.touches[0] : e;
    return t;
  }

  canvas.addEventListener("pointerdown", (e) => {
    const plot = canvasToPlot(e.clientX, e.clientY);
    hover = plot;
    useToolOn(plot);
  });
  canvas.addEventListener("pointermove", (e) => {
    hover = canvasToPlot(e.clientX, e.clientY);
    draw();
  });

  $("btn-end-day").addEventListener("click", endDay);
  $("btn-almanac").addEventListener("click", () => openAlmanac(false));
  $("btn-valley").addEventListener("click", openValley);
  $("btn-market").addEventListener("click", openMarket);
  $("btn-continue").addEventListener("click", () => enterGame(false));
  $("btn-new").addEventListener("click", () => {
    if (confirm("Xóa nông trại cũ và bắt đầu lại?")) enterGame(true);
  });

  document.querySelectorAll(".modal-close").forEach((btn) => {
    btn.addEventListener("click", () => {
      $(btn.dataset.close).classList.add("hidden");
    });
  });

  $("market-stalls").addEventListener("click", (e) => {
    const btn = e.target.closest("[data-stall]");
    if (!btn) return;
    handleStall(btn.dataset.stall);
  });

  window.addEventListener("resize", () => {
    if (!$("game-screen").classList.contains("hidden")) resizeCanvas();
  });

  // Khởi động
  if (load()) {
    $("btn-continue").textContent = `Tiếp tục nông trại (Ngày ${state.day})`;
  } else {
    $("btn-continue").textContent = "Vào nông trại";
  }
  refreshHud();
  runSplash();
})();
