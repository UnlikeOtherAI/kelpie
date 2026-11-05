import { createKelpieBrowserBackend } from "./fixtures/native-browser.js";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { chromium } from "playwright-core";
import type { Browser, Page } from "playwright-core";
import {
  createBrowserClient, createBrowserControlProxy, createPlaywrightBrowserBackend,
} from "../src/browser-control/index.js";
import type { BrowserControlBackend, BrowserTabClient } from "../src/browser-control/index.js";
import { fixedObservationExpression } from "../src/browser-control/observation-source.js";
import type { BrowserExtraction, BrowserPageStatus, BrowserReadiness } from "../src/browser-control/observations.js";
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


describe("bounded portable observations", () => {
  for (const adapter of ["playwright", "native-transport"] as const) {
    it(adapter + " prioritizes scoped action evidence without values", async () => {
      const page = await engine.newPage();
      try {
        await page.setContent('<aside><button>Outside</button></aside><main>' +
          '<p>Navigation prose</p>'.repeat(80) + '<h1>Report</h1><button>Export</button>' +
          '<input value="PRIVATE_CANARY"><div contenteditable="true"><span id="private-name">EDITOR_CANARY</span></div>' +
          '<button aria-labelledby="private-name">Public fallback</button></main>');
        const pages = new Map([["a", page]]);
        const backend = adapter === "playwright" ? createPlaywrightBrowserBackend({ listTabs: async () => [{ id: "a" }], getPage: async () => page }) : nativeBackend(pages);
        const client = createBrowserClient(createBrowserControlProxy(backend));
        const tab = await client.tabs.get("a");
        const snapshot = await tab.snapshot({ scope: "main", maxElements: 3 });
        expect(snapshot.elements?.[0]?.name).toBe("Export");
        expect(snapshot.truncated).toBe(true);
        expect(snapshot.text).not.toMatch(/Outside|PRIVATE_CANARY|EDITOR_CANARY/);
        const ordered = await tab.snapshot({ scope: "main", maxElements: 1, prioritize: false });
        expect(ordered.elements?.[0]?.name).toContain("Navigation prose");
        await expect(tab.snapshot({ scope: "button" })).rejects.toThrow();
      } finally { await page.close(); }
    });
    it(adapter + " extracts nested records with explicit ambiguity and publisher provenance", async () => {
      const page = await engine.newPage();
      try {
        await page.setContent(`<meta property="og:site_name" content="Fixture Publisher">
          <script type="application/ld+json">{"@graph":[{"@type":["Article","NewsArticle"],"headline":"Public headline","publisher":{"name":"Fixture Publisher"},"author":[{"name":"Writer"}],"password":"JSON_PRIVATE_CANARY","articleBody":"BODY_PRIVATE_CANARY"}]}</script>
          <main><article><h2>Alpha</h2><a href="/alpha">Read</a><ul><li><span>A</span></li><li><span>B</span></li></ul><input value="INPUT_PRIVATE_CANARY"></article>
          <article><h2>Beta</h2><a href="/beta">Read</a></article><p hidden>HIDDEN_PRIVATE_CANARY</p>
          <div contenteditable="true"><p>EDITOR_PRIVATE_CANARY</p></div></main>`);
        const backend = adapter === "playwright" ? createPlaywrightBrowserBackend({ listTabs: async () => [{ id: "a" }], getPage: async () => page }) : nativeBackend(new Map([["a", page]]));
        const tab = await createBrowserClient(createBrowserControlProxy(backend)).tabs.get("a");
        const result = await tab.extract({ scope: "main", metadata: true, fields: [
          { name: "records", selector: "article", source: "text", multiple: true, fields: [
            { name: "title", selector: "h2", source: "text" },
            { name: "link", selector: "a", source: "href" },
            { name: "items", selector: "li", source: "text", multiple: true, fields: [{ name: "label", selector: "span", source: "text" }] },
          ] },
          { name: "ambiguous", selector: "h2", source: "text" },
          { name: "missing", selector: ".missing", source: "text" },
          { name: "public", selector: "article", source: "text", multiple: true },
        ] });
        expect(result.fields[0]?.records?.[0]?.[0]?.values).toEqual(["Alpha"]);
        expect(result.fields[0]?.records?.[0]?.[1]?.values).toEqual(["/alpha"]);
        expect(result.fields[0]?.records?.[0]?.[2]?.records?.map((row) => row[0]?.values[0])).toEqual(["A", "B"]);
        expect(result.fields[1]?.status).toBe("ambiguous");
        expect(result.fields[1]?.values).toEqual([]);
        expect(result.fields[2]?.status).toBe("missing");
        expect(result.fields[0]?.provenance).toEqual({ selector: "article", source: "text", matches: 2 });
        expect(result.metadata.some((entry) => entry.key === "publisher" && entry.value === "Fixture Publisher" && entry.authority === "publisher-claim")).toBe(true);
        expect(result.metadata.some((entry) => entry.key === "headline" && entry.attribute.startsWith("json:"))).toBe(true);
        expect(result.metadata.filter((entry) => entry.key === "@type").map((entry) => entry.value)).toEqual(["Article", "NewsArticle"]);
        expect(JSON.stringify(result)).not.toContain("PRIVATE_CANARY");
        const bounded = await tab.extract({ maxChars: 256, fields: [{ name: "all", selector: "main", source: "text" }] });
        expect(bounded.fields[0]?.values.join("").length).toBeLessThanOrEqual(256);
      } finally { await page.close(); }
    });
    it(adapter + " reports explicit readiness and unavailable diagnostics", async () => {
      const page = await engine.newPage();
      try {
        await page.setContent('<dialog open>Confirm</dialog><div aria-busy="true">Loading</div><input aria-invalid="true" value="PRIVATE_CANARY"><button hidden>Ready</button>');
        const backend = adapter === "playwright" ? createPlaywrightBrowserBackend({ listTabs: async () => [{ id: "a" }], getPage: async () => page }) : nativeBackend(new Map([["a", page]]));
        const tab = await createBrowserClient(createBrowserControlProxy(backend)).tabs.get("a");
        const status = await tab.status();
        expect(status.dialogs).toBe(1);
        expect(status.busyRegions).toBe(1);
        expect(status.network).toEqual({ availability: "unavailable" });
        expect(status.errors).toEqual({ availability: "unavailable" });
        expect(JSON.stringify(status)).not.toContain("PRIVATE_CANARY");
        expect((await tab.ready({ state: "complete", selector: "button" })).ready).toBe(false);
        await page.locator("button").evaluate((el) => { el.removeAttribute("hidden"); });
        expect((await tab.ready({ state: "complete", selector: "button" })).ready).toBe(true);
        await page.evaluate(() => document.body.append(document.createElement("button")));
        expect((await tab.ready({ state: "complete", selector: "button" })).matches).toBe(2);
        expect((await tab.ready({ state: "complete", selector: "button" })).ready).toBe(false);
      } finally { await page.close(); }
    });
  }
});


describe("bounded observation work on real DOMs", () => {
  it("returns incomplete evidence when large/deep DOMs prevent proving uniqueness", async () => {
    const page = await engine.newPage();
    try {
      await page.setContent('<title>Large</title><meta name="description" content="Early publisher claim">' + "<p>x</p>".repeat(15_000) + '<button id="late">Late</button><dialog open>Late dialog</dialog>');
      const ready = await page.evaluate<BrowserReadiness>(fixedObservationExpression("ready", { state: "complete", selector: "#late" }));
      expect(ready.ready).toBe(false); expect(ready.incomplete).toBe(true);
      const extraction = await page.evaluate<BrowserExtraction>(fixedObservationExpression("extract", { fields: [{ name: "late", selector: "#late", source: "text" }] }));
      expect(extraction.fields[0]?.status).toBe("incomplete"); expect(extraction.truncated).toBe(true);
      const metadata = await page.evaluate<BrowserExtraction>(fixedObservationExpression("extract", { metadata: true, fields: [{ name: "none", selector: ".absent", source: "text" }] }));
      expect(metadata.truncated).toBe(true);
      expect(metadata.metadata.some((item) => item.value === "Early publisher claim")).toBe(true);
      for (const item of metadata.metadata) { expect(item.provenanceComplete).toBe(false); expect(item.index).toBeUndefined(); }
      const status = await page.evaluate<BrowserPageStatus>(fixedObservationExpression("status"));
      expect(status.dialogs).toBe(0); expect(status.truncated).toBe(true);
      const snapshot = await page.evaluate<{ snapshot: { truncated: boolean } }>(fixedObservationExpression("snapshot", { prefix: "bounded", maxElements: 8 }));
      expect(snapshot.snapshot.truncated).toBe(true);
      await page.setContent("<div>".repeat(100) + '<button id="deep">Deep</button>' + "</div>".repeat(100));
      const deep = await page.evaluate<BrowserReadiness>(fixedObservationExpression("ready", { state: "complete", selector: "#deep" }));
      expect(deep.ready).toBe(false); expect(deep.incomplete).toBe(true);
    } finally { await page.close(); }
  });
  it("does not copy oversized script text or materialize unbounded collections", async () => {
    const page = await engine.newPage();
    try {
      await page.setContent('<script type="application/ld+json">{"name":"' + "x".repeat(1_000_000) + '"}</script><p>Public</p><input value="PRIVATE_BOUND_CANARY"><div contenteditable>PRIVATE_BOUND_CANARY</div>');
      const expression = fixedObservationExpression("extract", { metadata: true, fields: [{ name: "public", selector: "p", source: "text" }] });
      const result = await page.evaluate<{ result: BrowserExtraction; copied: number }>(`(() => {
        const descriptor = Object.getOwnPropertyDescriptor(Node.prototype, "textContent");
        const from = Array.from, documentQuery = Document.prototype.querySelectorAll, elementQuery = Element.prototype.querySelectorAll;
        const substring = CharacterData.prototype.substringData;
        let copied = 0;
        const refuse = () => { throw new Error("unbounded collection/text access"); };
        Array.from = refuse; Document.prototype.querySelectorAll = refuse; Element.prototype.querySelectorAll = refuse;
        Object.defineProperty(Node.prototype, "textContent", { configurable: true, get: refuse });
        CharacterData.prototype.substringData = function(offset, count) { copied += count; if (copied > 65536) throw new Error("copy budget"); return substring.call(this, offset, count); };
        try { return { result: ${expression}, copied }; }
        finally { Array.from = from; Document.prototype.querySelectorAll = documentQuery; Element.prototype.querySelectorAll = elementQuery;
          Object.defineProperty(Node.prototype, "textContent", descriptor); CharacterData.prototype.substringData = substring; }
      })()`);
      expect(result.result.fields[0]?.values).toEqual(["Public"]);
      expect(result.result.metadata).toEqual([]); expect(result.result.truncated).toBe(true);
      expect(result.copied).toBeLessThanOrEqual(65_536);
      expect(JSON.stringify(result)).not.toContain("PRIVATE_BOUND_CANARY");
    } finally { await page.close(); }
  });
  it("treats ancestor opacity/collapse consistently and checks readiness viewport", async () => {
    const page = await engine.newPage();
    try {
      await page.setContent('<main><button id="normal">Visible</button><div style="opacity:0"><button id="transparent">Transparent</button><span aria-busy="true">Loading</span></div>' +
        '<div style="visibility:collapse"><span aria-busy="true">Collapsed</span></div><button id="offscreen" style="position:absolute;top:3000px">Offscreen</button>' +
        '<div style="width:20px;height:20px;overflow:hidden"><button id="clipped" style="transform:translateX(300px)">Clipped</button></div><article><h2>Scoped title</h2></article></main>');
      for (const selector of ["#transparent", "#offscreen", "#clipped"]) expect((await page.evaluate<BrowserReadiness>(fixedObservationExpression("ready", { state: "complete", selector }))).ready).toBe(false);
      expect((await page.evaluate<BrowserReadiness>(fixedObservationExpression("ready", { state: "complete", selector: "#normal" }))).ready).toBe(true);
      expect((await page.evaluate<BrowserPageStatus>(fixedObservationExpression("status"))).busyRegions).toBe(0);
      const records = await page.evaluate<BrowserExtraction>(fixedObservationExpression("extract", { scope: "main", fields: [{ name: "records", selector: "article", source: "text", multiple: true, fields: [{ name: "title", selector: ":scope > h2", source: "text" }] }] }));
      expect(records.fields[0]?.records?.[0]?.[0]?.values).toEqual(["Scoped title"]);
      await expect(page.evaluate(fixedObservationExpression("extract", { fields: [{ name: "unsupported", selector: ":scope > article > h2", source: "text" }] }))).rejects.toThrow("UNSUPPORTED_SCOPE_SELECTOR");
    } finally { await page.close(); }
  });
});


describe("metadata source positions and scoped root fields", () => {
  it("counts raw metadata sources before filtering private or empty records", async () => {
    const page = await engine.newPage();
    try {
      await page.setContent('<main><div contenteditable="true"><meta property="og:site_name" content="PRIVATE_INDEX_CANARY">' +
        '<script type="application/ld+json">{"name":"PRIVATE_INDEX_CANARY"}</script></div>' +
        '<meta property="og:site_name" content=""><script type="application/ld+json">{}</script>' +
        '<meta property="og:site_name" content="Public Publisher"><script type="application/ld+json">{"name":"Public Article"}</script><p>Public</p></main>');
      const result = await page.evaluate<BrowserExtraction>(fixedObservationExpression("extract", { metadata: true, fields: [{ name: "text", selector: "p", source: "text" }] }));
      expect(result.metadata.find((item) => item.key === "publisher" && item.value === "Public Publisher")).toMatchObject({ provenanceComplete: true, index: 2 });
      expect(result.metadata.find((item) => item.key === "name" && item.value === "Public Article")).toMatchObject({ provenanceComplete: true, index: 2 });
      expect(JSON.stringify(result)).not.toContain("PRIVATE_INDEX_CANARY");
    } finally { await page.close(); }
  });
  it("selects only explicit :scope roots and refuses nested or escaped scope syntax", async () => {
    const page = await engine.newPage();
    try {
      await page.setContent('<main><article id="record" class="foo"><h2>Record text</h2><input value="PRIVATE_SCOPE_CANARY"></article></main>');
      const result = await page.evaluate<BrowserExtraction>(fixedObservationExpression("extract", { scope: "#record", fields: [
        { name: "root", selector: ":scope", source: "text" }, { name: "descendants", selector: "article", source: "text" },
      ] }));
      expect(result.fields[0]?.values).toEqual(["Record text"]);
      expect(result.fields[1]?.status).toBe("missing");
      expect(JSON.stringify(result)).not.toContain("PRIVATE_SCOPE_CANARY");
      const nested = await page.evaluate<BrowserExtraction>(fixedObservationExpression("extract", { scope: "main", fields: [
        { name: "records", selector: "article", source: "text", multiple: true, fields: [{ name: "self", selector: ":SCOPE", source: "text" }] },
      ] }));
      expect(nested.fields[0]?.records?.[0]?.[0]?.values).toEqual(["Record text"]);
      for (const selector of [":scope > .foo:not(:scope)", ":scope > .foo:is(:SCOPE)"]) {
        await expect(page.evaluate(fixedObservationExpression("extract", { scope: "main", fields: [{ name: "reject", selector, source: "text" }] }))).rejects.toThrow("UNSUPPORTED_SCOPE_SELECTOR");
      }
      const escaped = ":" + String.fromCharCode(92) + "73 cope";
      await expect(page.evaluate(fixedObservationExpression("extract", { scope: "main", fields: [{ name: "reject", selector: escaped, source: "text" }] }))).rejects.toThrow("UNSUPPORTED_SELECTOR_ESCAPE");
    } finally { await page.close(); }
  });
});
