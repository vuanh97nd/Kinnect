import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { openSocial } from "../lib/social.js";
const exec = promisify(execFile);
test("local moderation CLI hides posts, revokes sessions and audits actions", async (t) => {
  const dir = await mkdtemp(join(tmpdir(), "kinnect-moderation-"));
  t.after(() => rm(dir, { recursive: true, force: true }));
  const path = join(dir, "kinnect.sqlite");
  let store = openSocial(path);
  store.db
    .prepare(
      "INSERT INTO users(id,username,password,salt,name,birth_date,created) VALUES(?,?,?,?,?,?,?)",
    )
    .run(
      "test-user",
      "test_user",
      "unused-test-hash",
      "unused-test-salt",
      "Test",
      "1990-01-01",
      Date.now(),
    );
  store.db
    .prepare("INSERT INTO posts VALUES(?,?,?,?,0,?)")
    .run("test-post", "test-user", "Reported post", "public", Date.now());
  store.db
    .prepare("INSERT INTO sessions VALUES(?,?,?)")
    .run("test-session", "test-user", Date.now() + 100000);
  store.db
    .prepare(
      "INSERT INTO reports(id,reporter,target_type,target_id,reason,created) VALUES(?,?,?,?,?,?)",
    )
    .run(
      "test-report",
      "test-user",
      "post",
      "test-post",
      "Please review this",
      Date.now(),
    );
  store.close();
  async function command(...args) {
    return exec(process.execPath, ["scripts/moderate.js", ...args], {
      env: { ...process.env, DATA_DIR: dir },
    });
  }
  const list = await command("reports");
  assert.equal(JSON.parse(list.stdout)[0].id, "test-report");
  await command("hide-post", "test-post");
  await command("suspend-user", "test-user");
  await command("close-report", "test-report");
  store = openSocial(path);
  assert.equal(store.db.prepare("SELECT hidden FROM posts").get().hidden, 1);
  assert.equal(
    store.db.prepare("SELECT count(*) AS n FROM sessions").get().n,
    0,
  );
  assert.equal(
    store.db.prepare("SELECT suspended FROM users").get().suspended,
    1,
  );
  assert.equal(
    store.db.prepare("SELECT status FROM reports").get().status,
    "closed",
  );
  assert.equal(
    store.db.prepare("SELECT count(*) AS n FROM moderation").get().n,
    3,
  );
  store.close();
  await command("show-post", "test-post");
  await command("restore-user", "test-user");
  store = openSocial(path);
  assert.equal(store.db.prepare("SELECT hidden FROM posts").get().hidden, 0);
  assert.equal(
    store.db.prepare("SELECT suspended FROM users").get().suspended,
    0,
  );
  store.close();
  await assert.rejects(command("hide-post", "missing-post"));
  async function admin(...args) {
    return exec(process.execPath, ["scripts/admin.js", ...args], {
      env: { ...process.env, DATA_DIR: dir },
    });
  }
  await assert.rejects(admin("promote", "missing_user"));
  await admin("promote", "test_user");
  store = openSocial(path);
  assert.equal(store.db.prepare("SELECT role FROM users").get().role, "admin");
  store.close();
  await assert.rejects(admin("demote", "test_user"));
});
