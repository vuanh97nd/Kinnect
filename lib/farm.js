import {randomUUID} from 'node:crypto';

export const FARM_CROPS = Object.freeze([
  {id: 'rose', name: 'Hoa hồng', level: 1, grow: 300, seed: 20, coins: 30, xp: 2, icon: 'heart', color: '#f472b6'},
  {id: 'tomato', name: 'Cà chua', level: 1, grow: 1800, seed: 80, coins: 120, xp: 4, icon: 'circle_check', color: '#ef4444'},
  {id: 'sunflower', name: 'Hướng dương', level: 2, grow: 7200, seed: 250, coins: 380, xp: 8, icon: 'star', color: '#facc15'},
  {id: 'pumpkin', name: 'Bí ngô', level: 3, grow: 14400, seed: 600, coins: 900, xp: 14, icon: 'gift', color: '#fb923c'},
  {id: 'watermelon', name: 'Dưa hấu', level: 4, grow: 28800, seed: 1200, coins: 1900, xp: 22, icon: 'circle_check', color: '#22c55e'},
  {id: 'grape', name: 'Nho', level: 5, grow: 43200, seed: 2200, coins: 3500, xp: 32, icon: 'crown', color: '#a78bfa'},
  {id: 'crystal', name: 'Pha lê', level: 6, grow: 86400, seed: 4000, coins: 7000, xp: 60, icon: 'sparkles', color: '#67e8f9'},
  {id: 'strawberry', name: 'Dâu tây', level: 2, grow: 3600, seed: 150, coins: 230, xp: 6, icon: 'heart', color: '#fb7185'}
]);

export const FARM_SUPPLIES = Object.freeze([
  {id: 'water', name: 'Nước', price: 10},
  {id: 'fertilizer', name: 'Phân bón', price: 40},
  {id: 'pesticide', name: 'Thuốc sâu', price: 25}
]);

const SLOTS = 6;
const MISSION_TARGETS = {plant: 3, harvest: 5, buy: 2};
const MISSION_REWARD = {coins: 30, xp: 20};
const DAILY_HARVEST_CAP = 30000;
const SEED_DAILY_CAPS = {watermelon: 5, grape: 3, crystal: 2};

export function createFarm({db, body, fail, wallet, clock = Date.now}) {
  db.exec(`CREATE TABLE IF NOT EXISTS farm_players(user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,xp INTEGER NOT NULL DEFAULT 0,created INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS farm_plots(user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,slot INTEGER NOT NULL,crop_id TEXT NOT NULL,planted INTEGER NOT NULL,ready INTEGER NOT NULL,watered INTEGER NOT NULL DEFAULT 0,fertilized INTEGER NOT NULL DEFAULT 0,pest_due INTEGER NOT NULL DEFAULT 0,treated INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(user_id,slot));
CREATE TABLE IF NOT EXISTS farm_inventory(user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,item_id TEXT NOT NULL,quantity INTEGER NOT NULL,PRIMARY KEY(user_id,item_id));
CREATE TABLE IF NOT EXISTS farm_purchases(user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,request_id TEXT PRIMARY KEY,item_id TEXT NOT NULL,quantity INTEGER NOT NULL,coins INTEGER NOT NULL,created INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS farm_daily(user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,day TEXT NOT NULL,planted INTEGER NOT NULL DEFAULT 0,harvested INTEGER NOT NULL DEFAULT 0,bought INTEGER NOT NULL DEFAULT 0,earned INTEGER NOT NULL DEFAULT 0,claimed INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(user_id,day));`);

  const crop = id => FARM_CROPS.find(c => c.id === id);
  const supply = id => FARM_SUPPLIES.find(s => s.id === id);
  const levelFor = xp => Math.min(30, 1 + Math.floor(Math.sqrt(Math.max(0, Number(xp) || 0)) / 5));
  const nextXpFor = level => Math.pow(level * 5, 2);
  const ensure = id => db.prepare('INSERT OR IGNORE INTO farm_players(user_id,xp,created) VALUES(?,0,?)').run(id, clock());
  const dayKey = () => new Intl.DateTimeFormat('en-CA', {timeZone: 'Asia/Ho_Chi_Minh'}).format(new Date(clock()));
  const dayStart = () => {
    const d = new Date(clock() + 7 * 3600 * 1000);
    return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()) - 7 * 3600 * 1000;
  };
  const daily = id => {
    const day = dayKey();
    db.prepare('INSERT OR IGNORE INTO farm_daily(user_id,day) VALUES(?,?)').run(id, day);
    return db.prepare('SELECT * FROM farm_daily WHERE user_id=? AND day=?').get(id, day);
  };
  const inv = (id, item) => Number(db.prepare('SELECT quantity FROM farm_inventory WHERE user_id=? AND item_id=?').get(id, item)?.quantity || 0);
  const addItem = (id, item, delta) => {
    const q = inv(id, item) + delta;
    if (q <= 0) db.prepare('DELETE FROM farm_inventory WHERE user_id=? AND item_id=?').run(id, item);
    else db.prepare('INSERT INTO farm_inventory(user_id,item_id,quantity) VALUES(?,?,?) ON CONFLICT(user_id,item_id) DO UPDATE SET quantity=excluded.quantity').run(id, item, q);
  };
  const entry = (id, coins, reference) => db.prepare('INSERT INTO wallet_entries VALUES(?,?,?,?,?,?,?,?,?)').run(randomUUID(), id, reference, 'farm_trial', coins, 0, 0, 0, clock());
  const credit = (id, coins, reference) => { if (coins > 0) entry(id, coins, reference); };
  const debit = (id, coins, reference) => {
    if (coins <= 0) return true;
    if (wallet.trialBalance(id) < coins) return false;
    entry(id, -coins, reference);
    return true;
  };
  const xpOf = id => Number(db.prepare('SELECT xp FROM farm_players WHERE user_id=?').get(id)?.xp || 0);

  const state = id => {
    ensure(id);
    const xp = xpOf(id), level = levelFor(xp), d = daily(id), now = clock();
    const plots = [];
    for (let slot = 0; slot < SLOTS; slot++) {
      const row = db.prepare('SELECT * FROM farm_plots WHERE user_id=? AND slot=?').get(id, slot);
      const c = row ? crop(row.crop_id) : null;
      const pest = !!row && row.pest_due > 0 && now >= row.pest_due && !row.treated;
      plots.push({
        slot,
        cropId: row?.crop_id || '',
        name: c?.name || '',
        icon: c?.icon || '',
        color: c?.color || '',
        grow: c?.grow || 0,
        planted: row?.planted || 0,
        ready: row?.ready || 0,
        remaining: row ? Math.max(0, row.ready - now) : 0,
        watered: !!row?.watered,
        fertilized: !!row?.fertilized,
        pest,
        treated: !!row?.treated
      });
    }
    const seeds = {}, supplies = {};
    for (const c of FARM_CROPS) seeds[c.id] = inv(id, 'seed_' + c.id);
    for (const s of FARM_SUPPLIES) supplies[s.id] = inv(id, s.id);
    const progress = {plant: d.planted, harvest: d.harvested, buy: d.bought};
    const claimable = !d.claimed && progress.plant >= MISSION_TARGETS.plant && progress.harvest >= MISSION_TARGETS.harvest && progress.buy >= MISSION_TARGETS.buy;
    return {
      coins: wallet.trialBalance(id),
      xp,
      level,
      nextXp: nextXpFor(level),
      serverNow: now,
      crops: FARM_CROPS.map(c => ({...c, unlocked: level >= c.level})),
      supplies: FARM_SUPPLIES,
      inventory: {seeds, supplies},
      plots,
      dailyEarned: d.earned,
      dailyCap: DAILY_HARVEST_CAP,
      missions: {targets: MISSION_TARGETS, progress, claimed: !!d.claimed, claimable, rewardCoins: MISSION_REWARD.coins, rewardXp: MISSION_REWARD.xp}
    };
  };

  const requirePlot = (id, slot) => {
    if (!Number.isInteger(slot) || slot < 0 || slot >= SLOTS) fail(400, 'Ô đất không hợp lệ.');
    const row = db.prepare('SELECT * FROM farm_plots WHERE user_id=? AND slot=?').get(id, slot);
    if (!row) fail(404, 'Ô đất đang trống.');
    return row;
  };

  function plant(id, slot, cropId) {
    ensure(id);
    if (!Number.isInteger(slot) || slot < 0 || slot >= SLOTS) fail(400, 'Ô đất không hợp lệ.');
    const c = crop(String(cropId || ''));
    if (!c) fail(400, 'Hạt giống không hợp lệ.');
    if (levelFor(xpOf(id)) < c.level) fail(403, 'Cần cấp ' + c.level + ' để trồng cây này.');
    if (db.prepare('SELECT 1 FROM farm_plots WHERE user_id=? AND slot=?').get(id, slot)) fail(409, 'Ô đất đã có cây.');
    if (inv(id, 'seed_' + c.id) < 1) fail(409, 'Bạn chưa có hạt giống này.');
    db.exec('BEGIN IMMEDIATE');
    try {
      addItem(id, 'seed_' + c.id, -1);
      const now = clock();
      const pestDue = Math.random() < 0.25 ? now + Math.floor(c.grow * 1000 * 0.3) : 0;
      db.prepare('INSERT INTO farm_plots VALUES(?,?,?,?,?,0,0,?,0)').run(id, slot, c.id, now, now + c.grow * 1000, pestDue);
      db.prepare('UPDATE farm_players SET xp=xp+1 WHERE user_id=?').run(id);
      const d = daily(id);
      db.prepare('UPDATE farm_daily SET planted=planted+1 WHERE user_id=? AND day=?').run(id, d.day);
      db.exec('COMMIT');
      return state(id);
    } catch (e) {
      if (db.isTransaction) db.exec('ROLLBACK');
      throw e;
    }
  }

  function care(id, slot, kind) {
    ensure(id);
    const row = requirePlot(id, slot);
    if (kind === 'water') {
      if (row.watered) fail(409, 'Cây này đã được tưới.');
      if (inv(id, 'water') < 1) fail(409, 'Bạn chưa có nước. Mua trong cửa hàng.');
    } else if (kind === 'fertilize') {
      if (row.fertilized) fail(409, 'Cây này đã được bón phân.');
      if (inv(id, 'fertilizer') < 1) fail(409, 'Bạn chưa có phân bón. Mua trong cửa hàng.');
    } else if (kind === 'treat') {
      const pest = row.pest_due > 0 && clock() >= row.pest_due && !row.treated;
      if (!pest) fail(409, 'Cây này không có sâu.');
      if (inv(id, 'pesticide') < 1) fail(409, 'Bạn chưa có thuốc sâu. Mua trong cửa hàng.');
    } else {
      fail(400, 'Thao tác không hợp lệ.');
    }
    db.exec('BEGIN IMMEDIATE');
    try {
      addItem(id, kind === 'water' ? 'water' : kind === 'fertilize' ? 'fertilizer' : 'pesticide', -1);
      db.prepare(`UPDATE farm_plots SET ${kind === 'water' ? 'watered=1' : kind === 'fertilize' ? 'fertilized=1' : 'treated=1'} WHERE user_id=? AND slot=?`).run(id, slot);
      db.exec('COMMIT');
      return state(id);
    } catch (e) {
      if (db.isTransaction) db.exec('ROLLBACK');
      throw e;
    }
  }

  function harvest(id, slot) {
    ensure(id);
    const row = requirePlot(id, slot);
    const now = clock();
    if (now < row.ready) fail(409, 'Cây chưa chín.');
    const c = crop(row.crop_id);
    const pest = row.pest_due > 0 && now >= row.pest_due && !row.treated;
    let multiplier = 1 + (row.watered ? 0.1 : 0) + (row.fertilized ? 0.25 : 0);
    if (pest) multiplier -= 0.15;
    let coins = Math.max(1, Math.round(c.coins * multiplier));
    const golden = Math.random() < 0.05;
    if (golden) coins *= 2;
    const d = daily(id);
    coins = Math.min(coins, Math.max(0, DAILY_HARVEST_CAP - d.earned));
    db.exec('BEGIN IMMEDIATE');
    try {
      credit(id, coins, 'farm-harvest:' + randomUUID());
      db.prepare('DELETE FROM farm_plots WHERE user_id=? AND slot=?').run(id, slot);
      db.prepare('UPDATE farm_players SET xp=xp+? WHERE user_id=?').run(c.xp, id);
      db.prepare('UPDATE farm_daily SET harvested=harvested+1,earned=earned+? WHERE user_id=? AND day=?').run(coins, id, d.day);
      db.exec('COMMIT');
      return {...state(id), receipt: {cropId: c.id, name: c.name, coins, golden, xp: c.xp}};
    } catch (e) {
      if (db.isTransaction) db.exec('ROLLBACK');
      throw e;
    }
  }

  function buy(id, itemId, quantity, requestId) {
    ensure(id);
    const q = Math.max(1, Math.min(99, Number(quantity) || 1));
    const seed = itemId.startsWith('seed_') ? crop(itemId.slice(5)) : null;
    const sup = seed ? null : supply(itemId);
    if (!seed && !sup) fail(400, 'Vật phẩm không hợp lệ.');
    if (seed && levelFor(xpOf(id)) < seed.level) fail(403, 'Cần cấp ' + seed.level + ' để mua hạt giống này.');
    const prior = db.prepare('SELECT * FROM farm_purchases WHERE request_id=?').get(requestId);
    if (prior) {
      if (prior.user_id !== id || prior.item_id !== itemId) fail(409, 'Mã yêu cầu đã được dùng.');
      return {...state(id), duplicate: true};
    }
    if (seed && SEED_DAILY_CAPS[seed.id]) {
      const cap = SEED_DAILY_CAPS[seed.id];
      const used = Number(db.prepare('SELECT COALESCE(SUM(quantity),0) n FROM farm_purchases WHERE user_id=? AND item_id=? AND created>=?').get(id, itemId, dayStart()).n);
      if (used + q > cap) fail(409, 'Đã đạt giới hạn ' + cap + ' hạt mỗi ngày.');
    }
    const cost = (seed ? seed.seed : sup.price) * q;
    db.exec('BEGIN IMMEDIATE');
    try {
      if (!debit(id, cost, 'farm-buy:' + requestId)) {
        db.exec('ROLLBACK');
        fail(402, 'Chưa đủ xu tặng.');
        return;
      }
      addItem(id, itemId, q);
      db.prepare('INSERT INTO farm_purchases VALUES(?,?,?,?,?,?)').run(id, requestId, itemId, q, cost, clock());
      const d = daily(id);
      db.prepare('UPDATE farm_daily SET bought=bought+1 WHERE user_id=? AND day=?').run(id, d.day);
      db.exec('COMMIT');
      return state(id);
    } catch (e) {
      if (db.isTransaction) db.exec('ROLLBACK');
      throw e;
    }
  }

  function claim(id) {
    ensure(id);
    const d = daily(id);
    if (d.claimed) fail(409, 'Hôm nay đã nhận thưởng nhiệm vụ.');
    const done = d.planted >= MISSION_TARGETS.plant && d.harvested >= MISSION_TARGETS.harvest && d.bought >= MISSION_TARGETS.buy;
    if (!done) fail(409, 'Chưa hoàn thành đủ nhiệm vụ hôm nay.');
    db.exec('BEGIN IMMEDIATE');
    try {
      credit(id, MISSION_REWARD.coins, 'farm-mission:' + d.day);
      db.prepare('UPDATE farm_players SET xp=xp+? WHERE user_id=?').run(MISSION_REWARD.xp, id);
      db.prepare('UPDATE farm_daily SET claimed=1 WHERE user_id=? AND day=?').run(id, d.day);
      db.exec('COMMIT');
      return state(id);
    } catch (e) {
      if (db.isTransaction) db.exec('ROLLBACK');
      throw e;
    }
  }

  async function route(req, res, path, json, me) {
    if (!path.startsWith('/api/farm')) return false;
    if (req.method === 'GET' && path === '/api/farm') {
      json(200, state(me.id));
      return true;
    }
    if (req.method !== 'POST') fail(405, 'Phương thức không hợp lệ.');
    const b = await body(req, 8192);
    if (path === '/api/farm/plant') {
      json(200, plant(me.id, Number(b.slot), String(b.cropId || '')));
      return true;
    }
    if (path === '/api/farm/water') { json(200, care(me.id, Number(b.slot), 'water')); return true; }
    if (path === '/api/farm/fertilize') { json(200, care(me.id, Number(b.slot), 'fertilize')); return true; }
    if (path === '/api/farm/treat') { json(200, care(me.id, Number(b.slot), 'treat')); return true; }
    if (path === '/api/farm/harvest') { json(200, harvest(me.id, Number(b.slot))); return true; }
    if (path === '/api/farm/missions/claim') { json(200, claim(me.id)); return true; }
    if (path === '/api/farm/shop/buy') {
      if (typeof b.requestId !== 'string' || !/^[A-Za-z0-9_-]{16,80}$/.test(b.requestId)) fail(400, 'Mã yêu cầu không hợp lệ.');
      json(200, buy(me.id, String(b.itemId || ''), Number(b.quantity) || 1, b.requestId));
      return true;
    }
    fail(404, 'Không tìm thấy thao tác nông trại.');
  }

  return {state, route};
}
