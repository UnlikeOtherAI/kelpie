import { createKelpieBrowserBackend } from "./fixtures/native-browser.js";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { chromium } from "playwright-core";
import type { Browser, Page } from "playwright-core";
import {
  createBrowserClient, createBrowserControlProxy, createPlaywrightBrowserBackend,
} from "../src/browser-control/index.js";
import type { BrowserControlBackend, BrowserTabClient } from "../src/browser-control/index.js";
import { actOnNativeReference, rememberNativeSnapshot } from "../src/browser-control/native-reference.js";
import { readFile } from "node:fs/promises";

let engine: Browser;
beforeAll(async () => { engine = await chromium.launch({ headless: true }); });
afterAll(async () => { await engine?.close(); });

it("renders the calibrated viewport point and scrolled page coordinates without intercepting input", async () => {
  const page = await engine.newPage({ viewport: { width: 320, height: 240 } });
  try {
    const source = await readFile(new URL("../../../assets/tap-marker.js", import.meta.url), "utf8");
    await page.clock.install({ time: new Date(0) });
    await page.clock.pauseAt(new Date(1000));
    await page.setContent('<main style="width:1000px;height:1000px"></main><button style="position:fixed;right:0;bottom:0" onclick="this.dataset.clicked = 1">Tap</button>');
    await page.evaluate(() => window.scrollTo(80, 150));

    await page.evaluate(`(${source})(300, 230, '59,130,246', 'crosshair-coordinates', 1500)`);
    const marker = page.locator('body > div[aria-hidden="true"]');
    expect(await marker.textContent()).toBe("Viewport: 300, 230\nPage: 380, 380");
    const label = await marker.getByText(/Viewport:/).boundingBox();
    expect(label!.x + label!.width).toBeLessThanOrEqual(320);
    expect(label!.y + label!.height).toBeLessThanOrEqual(240);
    await page.mouse.click(300, 230);
    expect(await page.getByRole("button").getAttribute("data-clicked")).toBe("1");
    await page.clock.runFor(1499);
    expect(await marker.evaluate((element) => element.style.opacity)).toBe("1");
    await page.clock.runFor(1);
    expect(await marker.evaluate((element) => element.style.opacity)).toBe("0");
    await page.clock.runFor(550);
    expect(await marker.count()).toBe(0);

    await page.evaluate(`(${source})(300, 230, '59,130,246', 'circle', 550)`);
    const circle = page.locator("body > div").first();
    expect(await page.locator("body > div").count()).toBe(2);
    expect(await circle.evaluate((element) => element.style.backgroundColor)).toBe("rgba(59, 130, 246, 0.7)");
    await page.clock.runFor(549);
    expect(await circle.evaluate((element) => element.style.opacity)).toBe("1");
    await page.clock.runFor(551);
    expect(await page.locator("body > div").count()).toBe(0);
  } finally {
    await page.close();
  }
}, 15000);

it("activates the tap target when the native script is wrapped as a JSON expression", async () => {
  const page = await engine.newPage();
  try {
    const handlers = [
      "android/src/main/java/com/kelpie/browser/handlers/InteractionHandler.kt",
      "apple/ios/Handlers/InteractionHandler.swift",
      "apple/macos/Handlers/InteractionHandler.swift",
    ];
    for (const handler of handlers) {
      const source = await readFile(new URL("../../../core/" + handler, import.meta.url), "utf8");
      const template = /private (?:fun|func) tapScript\([\s\S]*?"""([\s\S]*?)"""/.exec(source)?.[1];
      if (!template) throw new Error("Missing tap script in " + handler);
      const script = template
        .replace(/^\s*(?:\\\(\w+\(\)\)|\$\{\w+\(\)\})\s*$/gm, "")
        .replace(/\\\(execution\.\w+\)|\$\{execution\.\w+\}/g, "30");
      await page.setContent('<button id="target" style="width:80px;height:60px" onclick="this.dataset.clicked = 1">Tap</button>');
      await page.evaluate("window.kelpieTapDiagnostics = (target) => target?.id");
      expect(await page.evaluate("JSON.stringify((" + script + "))"), handler).toBe('"target"');
      expect(await page.locator("#target").getAttribute("data-clicked"), handler).toBe("1");
    }
  } finally {
    await page.close();
  }
}, 15000);
describe("fixed native atomic DOM actions", () => {
  it("appends through a native setter and refuses replaced or non-text targets", async () => {
    const page = await engine.newPage();
    try {
      await page.setContent('<input id="text" value="initial"><input id="number" type="number" value="12"><input id="file" type="file"><input id="readonly" onfocus="this.readOnly=true"><button id="button">Click</button>');
      await page.evaluate(`(${rememberNativeSnapshot.toString()})({ snapshot: {}, targets: Object.fromEntries([...document.querySelectorAll("input,button")].map((el) => [el.id, el])) })`);
      // Serialize the actual generated function, as native platforms do.
      const invoke = (ref: string, method = "tab.type", text = "!"): Promise<unknown> => page.evaluate(`(${actOnNativeReference.toString()})(${JSON.stringify(ref)},"__kelpieBrowserControlRefs",${JSON.stringify(method)},${JSON.stringify(text)})`);
      await page.evaluate(() => { const el = document.querySelector<HTMLInputElement>("#text")!; Object.defineProperty(el, "value", { get: () => "initial", set: () => { throw new Error("React own setter must not run"); } }); });
      expect(await invoke("text")).toEqual({ ok: true });
      expect(await page.evaluate(() => Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")!.get!.call(document.querySelector("#text")))).toBe("initial!");
      for (const ref of ["number", "file"]) expect(await invoke(ref)).toEqual({ error: "UNSUPPORTED", mayHaveCompleted: false });
      expect(await invoke("readonly")).toEqual({ error: "UNSUPPORTED", mayHaveCompleted: true });
      await page.evaluate(() => { const el = document.querySelector("#button")!; el.replaceWith(el.cloneNode(true)); document.querySelector("#button")!.setAttribute("data-sn-ref", "button"); });
      expect(await invoke("button", "tab.click")).toEqual({ error: "STALE_REFERENCE", mayHaveCompleted: false });
      await page.evaluate(() => window.dispatchEvent(new PageTransitionEvent("pagehide", { persisted: true })));
      expect(await invoke("text")).toEqual({ error: "STALE_REFERENCE", mayHaveCompleted: false });
    } finally { await page.close(); }
  });
});
const fixture = `<title>Control fixture</title><h1>Observe</h1>
<label>Email<input id="email" value="INITIAL_SECRET"></label>
<label>Password<input type="password" value="PASSWORD_SECRET"></label>
<textarea placeholder="Notes">TEXTAREA_SECRET</textarea>
<div contenteditable="true" role="textbox" aria-label="Draft">EDITABLE_SECRET<span id="private-label">EDITABLE_LABEL_SECRET</span><p>EDITABLE_DESCENDANT_SECRET</p><button>EDITABLE_BUTTON_SECRET</button></div>
<button aria-labelledby="private-label">Public action</button>
<button id="save">Save</button><button>Save draft</button>
<button>Duplicate</button><button>Duplicate</button>
<label>Agree<input id="agree" type="checkbox"></label><select id="choice"><option value="a">Alpha</option><option value="b">Beta</option></select>
<p id="count">0</p><div style="visibility:hidden"><p>HIDDEN_SECRET</p></div>
<svg width="24" height="24" aria-label="Accessible logo"><title>Ignored SVG title</title><rect width="24" height="24"/></svg>
<svg width="24" height="24"><title>Accessible SVG title</title><rect width="24" height="24"/></svg>
<svg width="24" height="24"><rect width="24" height="24"/></svg>
<svg hidden width="24" height="24"><title>HIDDEN_SECRET</title></svg>
<script>document.querySelector('#save').onclick=()=>document.querySelector('#count').textContent=String(Number(document.querySelector('#count').textContent)+1);</script>`;

function nativeBackend(pages: Map<string, Page>): BrowserControlBackend {
  return createKelpieBrowserBackend({ methods: new Set(["evaluate", "getTabs", "getCurrentUrl", "navigate", "click", "type", "screenshot", "scroll"]), async call(method, params) {
    if (method === "getTabs") return { success: true, tabs: [...pages.keys()].map((id) => ({ id })) };
    const page = pages.get(String(params.tabId));
    if (!page) throw new Error("unknown tab");
    if (method === "evaluate") return { success: true, result: await page.evaluate(String(params.expression)) };
    if (method === "getCurrentUrl") return { success: true, url: page.url(), title: await page.title() };
    if (method === "navigate") await page.goto(String(params.url));
    if (method === "click") await page.locator(String(params.selector)).click();
    if (method === "type") {
      const target = page.locator(String(params.selector));
      await target.press("End");
      await target.pressSequentially(String(params.text));
    }
    if (method === "screenshot") return { success: true, image: (await page.screenshot()).toString("base64"), format: "png" };
    if (method === "scroll") await page.mouse.wheel(Number(params.deltaX), Number(params.deltaY));
    return { success: true };
  } });
}

for (const adapter of ["playwright", "native-transport"] as const) {
  describe(`${adapter} portable conformance`, () => {
    let page: Page;
    let tab: BrowserTabClient;
    let other: BrowserTabClient;
    beforeAll(async () => {
      const context = await engine.newContext();
      page = await context.newPage();
      const second = await context.newPage();
      await page.setContent(fixture);
      await second.setContent(fixture);
      const pages = new Map([["a", page], ["b", second]]);
      const backend = adapter === "playwright" ? createPlaywrightBrowserBackend({
        listTabs: async () => [...pages.keys()].map((id) => ({ id })),
        getPage: async (id) => { const found = pages.get(id); if (!found) throw new Error("unknown tab"); return found; },
      }) : nativeBackend(pages);
      const client = createBrowserClient(createBrowserControlProxy(backend));
      tab = await client.tabs.get("a");
      other = await client.tabs.get("b");
    });
    it("omits all form values and hidden content and obeys total text bounds", async () => {
      const snapshot = await tab.snapshot({ maxChars: 800 });
      expect(snapshot.text.length).toBeLessThanOrEqual(800);
      expect(JSON.stringify(snapshot)).not.toMatch(/INITIAL_SECRET|PASSWORD_SECRET|TEXTAREA_SECRET|EDITABLE_SECRET|EDITABLE_DESCENDANT_SECRET|EDITABLE_BUTTON_SECRET|HIDDEN_SECRET/);
      expect(snapshot.elements?.some((element) => element.name === "Email")).toBe(true);
      const short = await tab.snapshot({ maxElements: 2 });
      expect(short.elements).toHaveLength(2);
      expect(short.truncated).toBe(true);
    });
    it("discloses discarded public text without treating omitted editor values as truncation", async () => {
      try {
        await page.setContent(`<p>${"public ".repeat(4000)}</p>`);
        const long = await tab.snapshot();
        expect(long.truncated).toBe(true);
        expect(long.elements?.[0]?.name.length).toBeLessThanOrEqual(256);
        await page.setContent(`<div contenteditable="true" role="textbox" aria-label="Draft">${"PRIVATE_SECRET".repeat(2000)}</div>`);
        const privateSnapshot = await tab.snapshot();
        expect(privateSnapshot.truncated).toBe(false);
        expect(JSON.stringify(privateSnapshot)).not.toContain("PRIVATE_SECRET");
      } finally { await page.setContent(fixture); }
    });
    it("omits inherited editor values used as external accessible labels", async () => {
      const snapshot = await tab.snapshot();
      expect(snapshot.elements?.some((element) => element.name === "Public action")).toBe(true);
      expect(JSON.stringify(snapshot)).not.toContain("EDITABLE_LABEL_SECRET");
    });
    it("includes visible named SVGs with accessible-name precedence", async () => {
      const snapshot = await tab.snapshot();
      expect(snapshot.elements?.filter((element) => element.role === "img").map((element) => element.name))
        .toEqual(["Accessible logo", "Accessible SVG title"]);
      expect(snapshot.text).not.toMatch(/Ignored SVG title|HIDDEN_SECRET/);
    });
    it("rejects cross-tab refs and appends to the observed editable element", async () => {
      const snapshot = await tab.snapshot();
      const email = snapshot.elements?.find((element) => element.name === "Email");
      expect(email).toBeDefined();
      await expect(other.typeText(email!.ref, "wrong")).rejects.toMatchObject({ code: "STALE_REFERENCE", mayHaveCompleted: false });
      await tab.typeText(email!.ref, "-append");
      expect(await page.locator("#email").inputValue()).toBe("INITIAL_SECRET-append");
      await expect(tab.typeText(email!.ref, "-duplicate")).rejects.toMatchObject({ code: "STALE_REFERENCE" });
    });
    it("rejects an identically replaced node and a prior snapshot ref", async () => {
      const observed = await tab.snapshot();
      const button = observed.elements!.find((element) => element.name === "Save")!;
      await page.locator("#save").evaluate((el) => { el.replaceWith(el.cloneNode(true)); });
      await expect(tab.click(button.ref)).rejects.toMatchObject({ code: "STALE_REFERENCE" });
      const current = await tab.snapshot();
      const live = current.elements!.find((element) => element.name === "Save")!;
      await tab.snapshot();
      await expect(tab.click(live.ref)).rejects.toMatchObject({ code: "STALE_REFERENCE" });
    });
    it("returns binary screenshots and refuses unsupported methods", async () => {
      expect((await tab.screenshot()).slice(0, 4)).toEqual(Uint8Array.from([137, 80, 78, 71]));
      if (adapter === "native-transport") await expect(tab.playwright.getByRole("button").click()).rejects.toMatchObject({ code: "UNSUPPORTED", mayHaveCompleted: false });
    });
    it("invalidates refs on navigation", async () => {
      const observed = await tab.snapshot();
      const ref = observed.elements![0]!.ref;
      await tab.goto("data:text/html,<title>Next</title><button>Next</button>");
      expect(await tab.title()).toBe("Next");
      await expect(tab.click(ref)).rejects.toMatchObject({ code: "STALE_REFERENCE" });
    });
  });
}

describe("Playwright semantic conformance", () => {
  it("enforces exact names and strict ambiguity, fill versus append, checkbox and select", async () => {
    const page = await engine.newPage();
    await page.setContent(fixture);
    const tab = await createBrowserClient(createBrowserControlProxy(createPlaywrightBrowserBackend({ listTabs: async () => [{ id: "a" }], getPage: async () => page }))).tabs.get("a");
    await tab.playwright.getByRole("button", { name: "Save", exact: true }).click();
    expect(await page.locator("#count").innerText()).toBe("1");
    await expect(tab.playwright.getByRole("button", { name: "Duplicate", exact: true }).click({ timeoutMs: 50 })).rejects.toMatchObject({ code: "COMMAND_FAILED" });
    const email = tab.playwright.getByLabel("Email", { exact: true });
    await email.fill("replaced");
    await email.pressSequentially("-append");
    expect(await page.locator("#email").inputValue()).toBe("replaced-append");
    await tab.playwright.getByLabel("Agree").check();
    expect(await page.locator("#agree").isChecked()).toBe(true);
    await tab.playwright.getByLabel("Agree").uncheck();
    expect(await page.locator("#agree").isChecked()).toBe(false);
    expect(await tab.playwright.locator("#choice").selectOption("b")).toEqual(["b"]);
    await expect(tab.playwright.getByText("Never present", { exact: true }).waitFor({ timeoutMs: 25 })).rejects.toMatchObject({ code: "COMMAND_FAILED", mayHaveCompleted: false });
    await page.close();
  });
});
