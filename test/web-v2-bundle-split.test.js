import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, statSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { createApp } from "../server.js";

test("web v2.js strips inline base64 auth wall and lazy-loads auth-wall, commerce, and admin ES modules", async () => {
  const publicDir = new URL("../public/", import.meta.url);
  const v2Path = new URL("v2.js", publicDir);
  const v2Size = statSync(v2Path).size;
  const v2Src = readFileSync(v2Path, "utf8");

  assert.ok(v2Size < 310 * 1024, `Expected slimmed v2.js < 310 KB, got ${v2Size} bytes`);
  assert.doesNotMatch(v2Src, /data:image\/jpeg;base64,/);
  assert.match(v2Src, /import\(['"]\/v2-auth-wall\.js['"]\)/);
  assert.match(v2Src, /import\(['"]\/v2-commerce\.js['"]\)/);
  assert.match(v2Src, /import\(['"]\/v2-admin\.js['"]\)/);

  for (const file of ["v2.js", "v2-auth-wall.js", "v2-commerce.js", "v2-admin.js"]) {
    execFileSync(process.execPath, ["--check", new URL(file, publicDir).pathname.replace(/^\/([A-Za-z]:)/, "$1")]);
  }

  const app = createApp();
  await new Promise((resolve) => app.server.listen(0, "127.0.0.1", resolve));
  const origin = "http://127.0.0.1:" + app.server.address().port;
  try {
    const v2Res = await fetch(origin + "/v2.js");
    assert.equal(v2Res.status, 200);
    assert.match(v2Res.headers.get("content-type") || "", /javascript/);
    const servedV2 = await v2Res.text();
    assert.match(servedV2, /import\('\/v2-auth-wall\.js\?v=/);
    assert.match(servedV2, /import\('\/v2-commerce\.js\?v=/);
    assert.match(servedV2, /import\('\/v2-admin\.js\?v=/);

    for (const modPath of ["/v2-auth-wall.js", "/v2-commerce.js", "/v2-admin.js"]) {
      const res = await fetch(origin + modPath);
      assert.equal(res.status, 200, `Expected 200 for ${modPath}`);
      assert.match(res.headers.get("content-type") || "", /javascript/);
      const body = await res.text();
      assert.match(body, /export function /);
    }
  } finally {
    app.wss.close();
    app.server.closeAllConnections?.();
    await new Promise((resolve) => app.server.close(resolve));
    app.social.close();
  }
});
