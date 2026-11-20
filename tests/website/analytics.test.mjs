import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import { createRequire } from "node:module";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(new URL("../../packages/shared/package.json", import.meta.url));
const { chromium, webkit } = require("playwright-core");
const site = fileURLToPath(new URL("../../site/", import.meta.url));
const origin = "https://kelpie.rocks";
const mirror = "https://unlikeotherai.github.io/kelpie";
const tagUrl = "https://www.googletagmanager.com/gtag/js?id=G-Q4485DL97E";
let browser;

before(async () => {
  const engine = process.env.KELPIE_TEST_ENGINE === "webkit" ? webkit : chromium;
  browser = await engine.launch({ executablePath: process.env.KELPIE_TEST_EXECUTABLE });
});
after(async () => { await browser?.close(); });

async function openSite(t, viewport) {
  const context = await browser.newContext({ viewport });
  const page = await context.newPage();
  t.after(async () => { await context.close(); });
  const requests = [];
  page.on("request", request => {
    if (request.url().startsWith("https://www.googletagmanager.com/")) requests.push(request.url());
  });
  await context.route("**/*", route => {
    const url = route.request().url();
    if (url === tagUrl) return route.fulfill({ contentType: "application/javascript", body: "" });
    const prefix = [origin, mirror].find(candidate => url.startsWith(candidate + "/"));
    if (!prefix) return route.abort();
    const path = url.slice(prefix.length + 1);
    return route.fulfill({ path: join(site, path.endsWith("/") || !path ? path + "index.html" : path) });
  });
  return { page, requests };
}

test("a visitor can decline and keep that choice across both pages", async t => {
  const { page, requests } = await openSite(t, { width: 390, height: 844 });
  await page.goto(origin);
  const panel = page.getByRole("region", { name: "Website analytics" });
  const bounds = await panel.boundingBox();
  assert.ok(bounds && bounds.x >= 0 && bounds.x + bounds.width <= 390);
  assert.deepEqual(requests, []);

  await panel.getByRole("button", { name: "Decline analytics" }).click();
  assert.equal(await panel.isVisible(), false);
  await page.goto(origin + "/privacy/");
  const settings = page.getByRole("button", { name: "Analytics settings" });
  await settings.waitFor();
  assert.equal(await panel.isVisible(), false);
  assert.deepEqual(requests, []);

  await settings.click();
  assert.equal(await panel.isVisible(), true);
  assert.equal(await panel.getByRole("button", { name: "Decline analytics" }).evaluate(el => el === document.activeElement), true);
});

test("the tag loads on acceptance and stops after withdrawal", async t => {
  const { page, requests } = await openSite(t);
  await page.goto(origin);
  const tagResponse = page.waitForResponse(tagUrl);
  await page.getByRole("button", { name: "Allow analytics" }).click();
  await tagResponse;
  assert.deepEqual(requests, [tagUrl]);
  assert.equal(await page.evaluate(() => window.dataLayer[1][1]), "G-Q4485DL97E");

  const privacyTagResponse = page.waitForResponse(tagUrl);
  await page.goto(origin + "/privacy/");
  await privacyTagResponse;
  const otherTab = await page.context().newPage();
  await otherTab.goto(origin);
  await otherTab.waitForFunction(() => Boolean(window.gtag));
  const domainCookies = ["_ga", "_ga_Q4485DL97E"].map(name => ({
    name, value: "test", domain: ".kelpie.rocks", path: "/",
  }));
  await page.context().addCookies([
    ...domainCookies,
    ...domainCookies.map(({ name }) => ({ name, value: "test", url: origin })),
  ]);
  await page.getByRole("button", { name: "Analytics settings" }).click();
  await page.getByRole("button", { name: "Decline analytics" }).click();
  assert.equal(await page.evaluate(() => window["ga-disable-G-Q4485DL97E"]), true);
  assert.deepEqual(await page.context().cookies(origin), []);
  await otherTab.waitForFunction(() => window["ga-disable-G-Q4485DL97E"] === true);

  await page.context().addCookies(domainCookies);
  await page.reload();
  await page.getByRole("button", { name: "Analytics settings" }).waitFor();
  assert.deepEqual(await page.context().cookies(origin), []);
  assert.deepEqual(requests, [tagUrl, tagUrl]);
});

test("the GitHub Pages mirror never loads the analytics module", async t => {
  const { page, requests } = await openSite(t);
  await page.goto(mirror + "/", { waitUntil: "networkidle" });
  assert.equal(await page.getByRole("button", { name: "Analytics settings" }).count(), 0);
  assert.deepEqual(requests, []);
});
