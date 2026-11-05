import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { execFileSync } from "node:child_process";
import { writeFile } from "node:fs/promises";
import { resolveScriptTarget } from "../../packages/shared/src/script-target.ts";
const require = createRequire(new URL("../../packages/cli/package.json", import.meta.url));
const { chromium } = require("playwright-core");
const output = process.argv[2]; assert.ok(output);
const browser = await chromium.launch({ headless: true, chromiumSandbox: true,
  ...(process.env.KELPIE_CHROMIUM_EXECUTABLE ? { executablePath: process.env.KELPIE_CHROMIUM_EXECUTABLE } : {}), timeout: 8000 });
const report = { version: 1, browser: browser.version(), stages: [], policy: [], mode: "actual CDP trusted input/pageScale/pinch; no CSS zoom or transform" };
const deadline = setTimeout(() => { void browser.close().finally(() => process.exit(124)); }, 25000);
try {
  const page = await browser.newPage({ viewport: { width: 800, height: 600 }, hasTouch: true });
  page.setDefaultTimeout(5000);
  const cdp = await page.context().newCDPSession(page);
  const send = async (method, params) => {
    let timer;
    try { return await Promise.race([cdp.send(method, params), new Promise((_, reject) => {
      timer = setTimeout(() => reject(Error("CDP_TIMEOUT")), 3500);
    })]); } finally { clearTimeout(timer); }
  };
  await page.setContent('<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=4"><style>html,body{margin:0;width:800px;height:1600px}button{position:absolute;left:350px;top:80px;width:200px;height:80px}</style><button id="target" type="button">Probe</button>');
  await page.evaluate(() => {
    globalThis.probeEvents = [];
    document.addEventListener("click", event => globalThis.probeEvents.push({
      trusted: event.isTrusted, x: event.clientX, y: event.clientY, target: event.target.id || event.target.tagName,
    }));
  });
  const metrics = () => page.evaluate(() => ({ innerWidth, innerHeight, scrollX, scrollY, dpr: devicePixelRatio,
    visual: { offsetLeft: visualViewport.offsetLeft, offsetTop: visualViewport.offsetTop, width: visualViewport.width,
      height: visualViewport.height, scale: visualViewport.scale } }));
  async function probe(stage) {
    const frame = await metrics();
    const target = await page.evaluate("(" + resolveScriptTarget.toString() + ')({selector:"#target"},"input-viewport")');
    const record = { stage, frame, target, candidates: [] };
    if (target.ok) {
      const v = frame.visual;
      for (const [name, x, y] of [
        ["layout", target.x, target.y],
        ["visual-relative", target.x - v.offsetLeft, target.y - v.offsetTop],
        ["visual-relative-scaled", (target.x - v.offsetLeft) * v.scale, (target.y - v.offsetTop) * v.scale],
      ]) {
        await page.evaluate(() => { globalThis.probeEvents = []; });
        await send("Input.dispatchMouseEvent", { type: "mousePressed", x, y, button: "left", clickCount: 1 });
        await send("Input.dispatchMouseEvent", { type: "mouseReleased", x, y, button: "left", clickCount: 1 });
        const events = await page.evaluate(() => globalThis.probeEvents);
        record.candidates.push({ name, x, y, events, exactTrustedCenter: events.length === 1 && events[0].trusted &&
          events[0].target === "target" && Math.abs(events[0].x - target.x) <= 0.5 && Math.abs(events[0].y - target.y) <= 0.5 });
      }
    }
    report.stages.push(record);
  }
  await send("Emulation.setPageScaleFactor", { pageScaleFactor: 2 });
  await page.waitForFunction(() => visualViewport.scale > 1.9);
  await probe("page-scale2-origin");
  await send("Emulation.setDeviceMetricsOverride", { width: 800, height: 600, deviceScaleFactor: 1, mobile: true, screenWidth: 800, screenHeight: 600 });
  report.pinchProfile = "CDP mobile device emulation; same owned browser/page";
  await send("Emulation.setPageScaleFactor", { pageScaleFactor: 1 });
  try {
    await send("Input.synthesizePinchGesture", { x: 300, y: 200, scaleFactor: 2, relativeSpeed: 2000, gestureSourceType: "touch" });
    await probe("mobile-emulation-supported-pinch");
  } catch (error) { report.pinchUnsupported = String(error.message).slice(0, 120); }
  const after = await metrics();
  if (after.visual.offsetLeft === 0 && after.visual.offsetTop === 0) {
    try {
      await send("Emulation.setPageScaleFactor", { pageScaleFactor: 2 });
      await send("Input.synthesizeScrollGesture", { x: 300, y: 200, xDistance: -100, yDistance: 0, speed: 1000, gestureSourceType: "touch" });
      await probe("mobile-emulation-supported-touch-pan");
    } catch (error) { report.panUnsupported = String(error.message).slice(0, 120); }
  }
  report.nonzeroVisualOffsetObserved = report.stages.some(stage => stage.frame.visual.offsetLeft !== 0 || stage.frame.visual.offsetTop !== 0);
  const origin = report.stages[0];
  assert.equal(origin.frame.visual.scale, 2);
  assert.equal(origin.candidates.find(c => c.name === "layout").exactTrustedCenter, true);
  assert.equal(origin.candidates.find(c => c.name === "visual-relative-scaled").exactTrustedCenter, false);
  if (process.platform === "win32") {
    const command = "$all=Get-CimInstance Win32_Process;$ids=@(" + process.pid + ");do{$next=@($all|Where-Object {$ids -contains $_.ParentProcessId -and $ids -notcontains $_.ProcessId}|Select-Object -ExpandProperty ProcessId);$ids+=$next}while($next.Count);@($ids|ForEach-Object {$p=Get-Process -Id $_ -ErrorAction Stop;[pscustomobject]@{id=$p.Id;name=$p.ProcessName;affinity=$p.ProcessorAffinity.ToInt64();priority=[string]$p.PriorityClass}})|ConvertTo-Json -Compress";
    report.policy = JSON.parse(execFileSync("powershell.exe", ["-NoProfile", "-Command", command], { encoding: "utf8", timeout: 4000 }));
    assert.ok(report.policy.every(p => p.affinity === 1 && p.priority === "Normal"));
  }
} finally {
  clearTimeout(deadline); await writeFile(output, JSON.stringify(report, null, 2), { flag: "wx" });
  await browser.close();
}
