import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { writeFile } from "node:fs/promises";
import { resolveScriptTarget } from "../../packages/shared/src/script-target.ts";
const require = createRequire(new URL("../../packages/cli/package.json", import.meta.url));
const { chromium } = require("playwright-core");
const output = process.argv[2];
assert.ok(output, "Provide an ignored report path");
const browser = await chromium.launch({ headless: true, chromiumSandbox: true,
  ...(process.env.KELPIE_CHROMIUM_EXECUTABLE ? { executablePath: process.env.KELPIE_CHROMIUM_EXECUTABLE } : {}) });
const report = { browser: browser.version(), cases: [] };
const timeout = setTimeout(() => { void browser.close().finally(() => process.exit(124)); }, 25000);
try {
  const page = await browser.newPage();
  const source = resolveScriptTarget.toString();
  for (const change of ["autocomplete", "type", "remove", "navigate"]) {
    for (const capture of [true, false]) {
      await page.setContent('<input id="edit" aria-label="Draft"><script>window.edits=0;edit.oninput=()=>edits++<\/script>');
      await page.evaluate(change => {
        history.replaceState({}, "", "#base");
        const el = document.getElementById("edit");
        el.onfocus = () => {
          el.autocomplete = "current-password";
          if (change === "type") el.type = "password";
          if (change === "remove") el.remove();
          if (change === "navigate") history.replaceState({}, "", "#changed");
        };
      }, change);
      const call = args => page.evaluate("(" + source + ")(..."+ JSON.stringify(args) + ")");
      const first = await call([{ selector: "#edit" }, "private"]);
      assert.equal(first.ok, true);
      const done = await call([{ selector: "#edit" }, "private", first.token, false,
        { action: "fill", text: "SYNTHETIC_PRIVATE_FOCUS" }, false, { refuseSensitive: capture }]);
      const facts = await page.evaluate(() => ({ edits: window.edits,
        hasValue: document.getElementById("edit")?.value.length > 0 }));
      assert.equal(done.sensitive, true);
      if (capture || change !== "autocomplete") {
        assert.equal(done.ok, false);
        assert.equal(facts.edits, 0);
        assert.equal(facts.hasValue, false);
      } else {
        assert.equal(done.ok, true);
        assert.equal(facts.edits, 1);
      }
      report.cases.push({ change, capture, result: done, facts });
    }
  }
} finally {
  clearTimeout(timeout);
  await writeFile(output, JSON.stringify(report, null, 2));
  await browser.close();
}
