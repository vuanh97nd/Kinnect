import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createApp} from '../server.js';

async function setup(t, username = 'farm_test') {
  const app = createApp({authLimit: 1000});
  await new Promise(r => app.server.listen(0, '127.0.0.1', r));
  t.after(async () => {
    const peers = [...app.wss.clients];
    await Promise.all(peers.map(ws => new Promise(r => { ws.once('close', r); ws.terminate(); })));
    app.wss.close();
    app.server.closeAllConnections();
    await new Promise(r => app.server.close(r));
    app.social.close();
  });
  const root = 'http://127.0.0.1:' + app.server.address().port;
  async function req(path, method = 'GET', data, cookie) {
    const r = await fetch(root + '/api' + path, {
      method,
      headers: {...(cookie ? {Cookie: cookie} : {}), ...(data ? {'Content-Type': 'application/json'} : {})},
      body: data ? JSON.stringify(data) : undefined
    });
    return {status: r.status, body: await r.json(), cookie: r.headers.get('set-cookie')?.split(';')[0]};
  }
  const u = await req('/register', 'POST', {username, name: 'Farm', password: 'strong-password', agree18: true, acceptPrivacyNotice: true});
  return {...app, root, req, u};
}

const day = () => new Intl.DateTimeFormat('en-CA', {timeZone: 'Asia/Ho_Chi_Minh'}).format(new Date());

test('farm P1: shop, plant, care, harvest, wallet credit and daily mission', async t => {
  const a = await setup(t);
  const id = a.u.body.user.id;
  let f = (await a.req('/farm', 'GET', null, a.u.cookie)).body;
  assert.equal(f.coins, 2000);
  assert.equal(f.level, 1);
  assert.equal(f.plots.length, 6);
  assert.equal(f.crops.length, 8);
  assert.equal(f.inventory.seeds.rose, 0);
  assert.equal(f.missions.targets.plant, 3);

  const buy = await a.req('/farm/shop/buy', 'POST', {itemId: 'seed_rose', quantity: 2, requestId: 'farm-buy-request-0001'}, a.u.cookie);
  assert.equal(buy.status, 200);
  assert.equal(buy.body.coins, 1960);
  assert.equal(buy.body.inventory.seeds.rose, 2);
  const dup = await a.req('/farm/shop/buy', 'POST', {itemId: 'seed_rose', quantity: 2, requestId: 'farm-buy-request-0001'}, a.u.cookie);
  assert.equal(dup.status, 200);
  assert.equal(dup.body.duplicate, true);
  assert.equal(dup.body.coins, 1960);

  const plant = await a.req('/farm/plant', 'POST', {slot: 0, cropId: 'rose'}, a.u.cookie);
  assert.equal(plant.status, 200);
  assert.equal(plant.body.plots[0].cropId, 'rose');
  assert.equal(plant.body.inventory.seeds.rose, 1);
  assert.equal(plant.body.xp, 1);
  assert.equal((await a.req('/farm/plant', 'POST', {slot: 0, cropId: 'rose'}, a.u.cookie)).status, 409);

  assert.equal((await a.req('/farm/shop/buy', 'POST', {itemId: 'water', quantity: 1, requestId: 'farm-buy-request-0002'}, a.u.cookie)).status, 200);
  const water = await a.req('/farm/water', 'POST', {slot: 0}, a.u.cookie);
  assert.equal(water.status, 200);
  assert.equal(water.body.plots[0].watered, true);
  assert.equal((await a.req('/farm/water', 'POST', {slot: 0}, a.u.cookie)).status, 409);

  assert.equal((await a.req('/farm/shop/buy', 'POST', {itemId: 'fertilizer', quantity: 1, requestId: 'farm-buy-request-0003'}, a.u.cookie)).status, 200);
  const fert = await a.req('/farm/fertilize', 'POST', {slot: 0}, a.u.cookie);
  assert.equal(fert.status, 200);
  assert.equal(fert.body.plots[0].fertilized, true);

  a.social.db.prepare('UPDATE farm_plots SET ready=?,pest_due=0,treated=0 WHERE user_id=? AND slot=0').run(Date.now() - 1000, id);
  const before = a.social.wallet.trialBalance(id);
  const harvest = await a.req('/farm/harvest', 'POST', {slot: 0}, a.u.cookie);
  assert.equal(harvest.status, 200);
  assert.equal(harvest.body.plots[0].cropId, '');
  assert.ok(harvest.body.receipt.coins > 0);
  assert.equal(a.social.wallet.trialBalance(id), before + harvest.body.receipt.coins);
  assert.equal(harvest.body.xp, 3);
  assert.equal((await a.req('/farm/harvest', 'POST', {slot: 0}, a.u.cookie)).status, 404);

  a.social.db.prepare('UPDATE farm_daily SET planted=3,harvested=5,bought=2 WHERE user_id=? AND day=?').run(id, day());
  const claim = await a.req('/farm/missions/claim', 'POST', {}, a.u.cookie);
  assert.equal(claim.status, 200);
  assert.equal(claim.body.missions.claimed, true);
  assert.equal(claim.body.xp, 23);
  assert.equal((await a.req('/farm/missions/claim', 'POST', {}, a.u.cookie)).status, 409);
});

test('farm shop enforces crop level, daily seed caps, funds and request ownership', async t => {
  const a = await setup(t, 'farm_limits');
  const id = a.u.body.user.id;
  await a.req('/farm', 'GET', null, a.u.cookie);
  assert.equal((await a.req('/farm/shop/buy', 'POST', {itemId: 'seed_sunflower', quantity: 1, requestId: 'farm-lock-request-0001'}, a.u.cookie)).status, 403);
  a.social.db.prepare('UPDATE farm_players SET xp=900 WHERE user_id=?').run(id);
  a.social.db.prepare("UPDATE wallet_entries SET coins=100000 WHERE user_id=? AND kind='signup_trial'").run(id);
  for (let i = 0; i < 5; i++) {
    assert.equal((await a.req('/farm/shop/buy', 'POST', {itemId: 'seed_watermelon', quantity: 1, requestId: 'farm-cap-request-000' + i}, a.u.cookie)).status, 200);
  }
  assert.equal((await a.req('/farm/shop/buy', 'POST', {itemId: 'seed_watermelon', quantity: 1, requestId: 'farm-cap-request-006'}, a.u.cookie)).status, 409);
  assert.equal((await a.req('/farm/shop/buy', 'POST', {itemId: 'seed_crystal', quantity: 1, requestId: 'farm-level-request-01'}, a.u.cookie)).status, 200);
  a.social.db.prepare('UPDATE wallet_entries SET coins=0 WHERE user_id=?').run(id);
  assert.equal((await a.req('/farm/shop/buy', 'POST', {itemId: 'water', quantity: 1, requestId: 'farm-fund-request-0001'}, a.u.cookie)).status, 402);
  assert.equal((await a.req('/farm/shop/buy', 'POST', {itemId: 'water', quantity: 1, requestId: 'short'}, a.u.cookie)).status, 400);
});

test('farm pest treatment clears the warning and harvest still pays', async t => {
  const a = await setup(t, 'farm_pest');
  const id = a.u.body.user.id;
  await a.req('/farm', 'GET', null, a.u.cookie);
  assert.equal((await a.req('/farm/shop/buy', 'POST', {itemId: 'seed_rose', quantity: 1, requestId: 'farm-pest-seed-0001'}, a.u.cookie)).status, 200);
  assert.equal((await a.req('/farm/plant', 'POST', {slot: 0, cropId: 'rose'}, a.u.cookie)).status, 200);
  a.social.db.prepare('UPDATE farm_plots SET pest_due=? WHERE user_id=? AND slot=0').run(Date.now() - 1000, id);
  const s = (await a.req('/farm', 'GET', null, a.u.cookie)).body;
  assert.equal(s.plots[0].pest, true);
  assert.equal((await a.req('/farm/shop/buy', 'POST', {itemId: 'pesticide', quantity: 1, requestId: 'farm-pest-spray-0001'}, a.u.cookie)).status, 200);
  const treated = await a.req('/farm/treat', 'POST', {slot: 0}, a.u.cookie);
  assert.equal(treated.status, 200);
  assert.equal(treated.body.plots[0].pest, false);
  assert.equal(treated.body.plots[0].treated, true);
  a.social.db.prepare('UPDATE farm_plots SET ready=? WHERE user_id=? AND slot=0').run(Date.now() - 1000, id);
  const harvest = await a.req('/farm/harvest', 'POST', {slot: 0}, a.u.cookie);
  assert.equal(harvest.status, 200);
  assert.ok(harvest.body.receipt.coins >= 26);
});
