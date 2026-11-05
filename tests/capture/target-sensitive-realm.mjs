import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { writeFile } from "node:fs/promises";
import { resolveScriptTarget } from "../../packages/shared/src/script-target.ts";
const require = createRequire(new URL("../../packages/cli/package.json", import.meta.url));
const { chromium } = require("playwright-core");
const output = process.argv[2];
assert.ok(output, "Provide an ignored report path");
const browser = await chromium.launch({ headless: true, chromiumSandbox: true });
const report = { browser: browser.version(), cases: [] };
const timer = setTimeout(() => { void browser.close().finally(() => process.exit(124)); }, 25000);
const source = resolveScriptTarget.toString();
try {
  const page = await browser.newPage();
  await page.route("https://sensitivity.test/**", route => route.fulfill({
    contentType: "text/html", body: '<input id="edit">' +
      (new URL(route.request().url()).pathname === "/start" ? '<iframe id="child" src="/child"></iframe>' : ""),
  }));
  for (const phase of ["focus", "input"]) {
    for (const removal of [false, true]) {
      for (const capture of [false, true]) {
        await page.goto("https://sensitivity.test/start");
        let frame = removal ? page.frames().find(item => item.parentFrame()) : page.mainFrame();
        assert.ok(frame);
        await frame.waitForSelector("#edit");
        await frame.evaluate(({ phase, removal }) => {
          const el = document.getElementById("edit");
          el.addEventListener(phase, () => {
            el.autocomplete = "current-password";
            sessionStorage.setItem("transitionObserved", "true");
            if (removal) frameElement.remove();
            else location.href = "/next";
          }, { once: true });
        }, { phase, removal });
        const call = args => frame.evaluate("(" + source + ")(..."+JSON.stringify(args)+")");
        const first = await call([{ selector: "#edit" }, "private"]);
        assert.equal(first.sensitivityKnown, true);
        let done;
        let resultLost = false;
        try { done = await call([{ selector: "#edit" }, "private", first.token, false,
          { action: "fill", text: "SYNTHETIC_REALM_PRIVATE" }, false, { refuseSensitive: capture }]); }
        catch { resultLost = true; }
        if (removal) {
          await page.waitForFunction(() => !document.getElementById("child"));
          await page.evaluate(() => {
            const el = document.createElement("iframe"); el.src = "/fresh"; el.id = "child"; document.body.append(el);
          });
          frame = page.frames().find(item => item.parentFrame());
          await frame.waitForSelector("#edit");
        } else {
          await page.waitForURL("https://sensitivity.test/next");
          frame = page.mainFrame();
        }
        const stale = await call([{ selector: "#edit" }, "private", first.token]);
        assert.equal(stale.ok, false);
        assert.equal(stale.sensitivityKnown, false);
        assert.equal(stale.sensitive, false);
        if (done) assert.equal(done.sensitive, true);
        report.cases.push({ phase, removal, capture, resultLost, result: done, stale });
      }
    }
  }
} finally {
  clearTimeout(timer);
  await writeFile(output, JSON.stringify(report, null, 2));
  await browser.close();
}
