import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { execFileSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import { writeFile } from "node:fs/promises";
import { resolveScriptTarget } from "../../packages/shared/src/script-target.ts";
const require = createRequire(new URL("../../packages/cli/package.json", import.meta.url));
const { chromium } = require("playwright-core");
const targetModule = process.env.KELPIE_TARGET_MODULE
  ? await import(pathToFileURL(process.env.KELPIE_TARGET_MODULE).href) : { resolveScriptTarget };
const target = targetModule.resolveScriptTarget.toString();
const output = process.argv[2];
assert.ok(output, "Provide an ignored report path");
const browser = await chromium.launch({ headless: true, chromiumSandbox: true,
  ...(process.env.KELPIE_CHROMIUM_EXECUTABLE ? { executablePath: process.env.KELPIE_CHROMIUM_EXECUTABLE } : {}) });
const report = { version: 1, browser: browser.version(), mode: "CDP actual page scale; no CSS zoom/transform", samples: [] };
const timeout = setTimeout(() => { void browser.close().finally(() => process.exit(124)); }, 25000);
try {
  if (process.platform === "win32") {
    const policy = execFileSync("powershell.exe", ["-NoProfile", "-Command",
      "$all=Get-CimInstance Win32_Process; $ids=@(" + process.pid + "); do {$next=@($all|Where-Object {$ids -contains $_.ParentProcessId -and $ids -notcontains $_.ProcessId}|Select-Object -ExpandProperty ProcessId);$ids+=$next}while($next.Count); @($ids|ForEach-Object {$p=Get-Process -Id $_ -ErrorAction Stop;[pscustomobject]@{id=$p.Id;name=$p.ProcessName;affinity=$p.ProcessorAffinity.ToInt64();priority=[string]$p.PriorityClass}})|ConvertTo-Json -Compress"], { encoding: "utf8", timeout: 4000 });
    report.processPolicy = JSON.parse(policy);
    assert.ok(report.processPolicy.some(item => /chrome/.test(item.name)), "No browser leaf observed");
    const expectedAffinity=Number(process.env.KELPIE_EXPECTED_AFFINITY??"1");
    assert.ok(Number.isSafeInteger(expectedAffinity)&&expectedAffinity>0,"Invalid expected affinity");
    assert.ok(report.processPolicy.every(item => item.affinity === expectedAffinity && item.priority === "Normal"), "Process policy not inherited");
  }
  const page = await browser.newPage({ viewport: { width: 800, height: 600 }, hasTouch: true });
  const cdp = await page.context().newCDPSession(page);
  await page.setContent('<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=4"><style>html,body{margin:0;width:800px;height:1200px}button{position:absolute;top:60px;height:60px}#partial{left:350px;width:200px}#outside{left:600px;width:100px}#stable{left:100px;top:180px;width:100px}</style><button id="partial">Partial</button><button id="outside">Outside</button><button id="stable">Stable</button>');
  const invoke = (selector, token) => page.evaluate("(" + target + ")(" + JSON.stringify({ selector }) + ',"visual-audit",' + JSON.stringify(token) + ")");
  const metrics = () => page.evaluate(() => ({ innerWidth, innerHeight, vv: {
    x: visualViewport.offsetLeft, y: visualViewport.offsetTop, width: visualViewport.width,
    height: visualViewport.height, scale: visualViewport.scale } }));
  const first = await invoke("#stable");
  assert.equal(first.ok, true);
  await cdp.send("Emulation.setPageScaleFactor", { pageScaleFactor: 2 });
  await page.waitForFunction(() => visualViewport.scale > 1.9);
  const current = await metrics();
  assert.equal(current.innerWidth, 800); assert.ok(current.vv.width < 401);
  const fenced = await invoke("#stable", first.token);
  const partial = await invoke("#partial");
  const outside = await invoke("#outside");
  report.samples.push({ metrics: current, staleScaleToken: fenced, partial, outside });
  if (process.env.KELPIE_TARGET_DIAGNOSTIC !== "1") {
    assert.equal(fenced.error, "VIEWPORT_CHANGED");
    assert.equal(partial.ok, true);
    assert.ok(Math.abs(partial.x - 375) <= 1); assert.ok(Math.abs(partial.width - 50) <= 1);
    assert.equal(outside.ok, false);
  }
  await cdp.send("Emulation.setPageScaleFactor",{pageScaleFactor:1});
  const markup=bodyStyle=>'<style>html{overflow:visible}body{margin:0;'+bodyStyle+
    '}button{position:absolute;left:40px;top:230px;width:30px;height:30px}</style><button id="first">First</button>';
  await page.setContent(markup("height:0;overflow:hidden"));
  const hit=await page.evaluate(()=>document.elementFromPoint(55,245)?.id);
  const propagated=await invoke("#first");
  assert.equal(hit,"first");assert.equal(propagated.ok,true);
  assert.equal(propagated.x,55);assert.equal(propagated.y,245);
  await page.setContent(markup("position:relative;height:0;overflow:hidden;contain:layout"));
  const containedHit=await page.evaluate(()=>document.elementFromPoint(55,245)?.id??null);
  const contained=await invoke("#first");
  assert.notEqual(containedHit,"first");assert.equal(contained.ok,false);
  await page.setContent('<style>html{height:0;overflow:hidden}body{margin:0;overflow:visible}button{position:absolute;left:40px;top:230px;width:30px;height:30px}</style><button id="first">First</button>');
  const rootHit=await page.evaluate(()=>document.elementFromPoint(55,245)?.id);
  const rootClipping=await invoke("#first");
  assert.equal(rootHit,"first");assert.equal(rootClipping.ok,true);
  report.bodyOverflow={hit,propagated,containedHit,contained,rootHit,rootClipping};
} finally {
  clearTimeout(timeout);
  await writeFile(output, JSON.stringify(report, null, 2));
  await browser.close();
}
