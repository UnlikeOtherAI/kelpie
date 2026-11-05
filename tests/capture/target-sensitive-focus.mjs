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
  for (const [kind,handler] of [
    ["autocomplete","this.autocomplete='current-password'"],
    ["type","this.type='password'"],
  ]) {
    await page.setContent('<label>Password<input id="inline-edit" type="text" autocomplete="off" onfocus="'+handler+'"></label>');
    await page.evaluate(()=>{window.inlineFocusCount=0;document.getElementById("inline-edit").addEventListener("focus",()=>window.inlineFocusCount++);});
    const before=await page.evaluate(()=>({hasFocus:document.hasFocus(),active:document.activeElement===document.getElementById("inline-edit")}));
    const call=args=>page.evaluate("("+source+")(..."+JSON.stringify(args)+")");
    const first=await call([{selector:"#inline-edit"},"inline-private"]);
    assert.equal(first.ok,true);
    const done=await call([{selector:"#inline-edit"},"inline-private",first.token,false,
      {action:"fill",text:"SYNTHETIC_INLINE_FOCUS"},false,{refuseSensitive:true}]);
    const facts=await page.evaluate(()=>{const el=document.getElementById("inline-edit");return {
      hasFocus:document.hasFocus(),active:document.activeElement===el,focusEvents:window.inlineFocusCount,
      password:el.type==="password",passwordAutocomplete:/^(current|new)-password$/.test(el.autocomplete),
      hasValue:el.value.length>0}});
    assert.equal(facts.focusEvents,1);assert.equal(facts.active,true);
    assert.equal(done.ok,false);assert.equal(done.error,"SENSITIVE_CAPTURE_REFUSED");
    assert.equal(done.sensitive,true);assert.equal(facts.hasValue,false);
    report.cases.push({change:"inline-"+kind,capture:true,before,facts,result:done});
  }
} finally {
  clearTimeout(timeout);
  await writeFile(output, JSON.stringify(report, null, 2));
  await browser.close();
}
