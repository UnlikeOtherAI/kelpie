import { createKelpieBrowserBackend } from "./fixtures/native-browser.js";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { chromium } from "playwright-core";
import type { Browser, Page } from "playwright-core";
import {
  createBrowserClient, createBrowserControlProxy, createPlaywrightBrowserBackend,
} from "../src/browser-control/index.js";
import type { BrowserControlBackend, BrowserTabClient } from "../src/browser-control/index.js";
import { actOnNativeReference, rememberNativeSnapshot } from "../src/browser-control/native-reference.js";

let engine: Browser;
beforeAll(async () => { engine = await chromium.launch({ headless: true }); });
afterAll(async () => { await engine?.close(); });
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
<div contenteditable="true" role="textbox" aria-label="Draft">EDITABLE_SECRET<p>EDITABLE_DESCENDANT_SECRET</p><button>EDITABLE_BUTTON_SECRET</button></div>
<button id="save">Save</button><button>Save draft</button>
<button>Duplicate</button><button>Duplicate</button>
<label>Agree<input id="agree" type="checkbox"></label><select id="choice"><option value="a">Alpha</option><option value="b">Beta</option></select>
<p id="count">0</p><div style="visibility:hidden"><p>HIDDEN_SECRET</p></div>
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
