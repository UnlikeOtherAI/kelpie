import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import { pathToFileURL } from "node:url";

import { control, expectControlError, mcpRequest, rawRequest, resultValue, sameUrl, waitFor } from "./http.mjs";
import { decodePng } from "./png.mjs";

function assertion(condition, message) {
  assert.equal(condition, true, message);
}

function imageFrom(value) {
  if (typeof value?.image === "string") return value.image;
  if (typeof value?.result?.image === "string") return value.result.image;
  if (typeof value?.structuredContent?.image === "string") return value.structuredContent.image;
  for (const item of value?.content ?? []) {
    if (item?.type === "image" && typeof item.data === "string") return item.data;
    if (item?.type === "text") {
      try {
        const parsed = JSON.parse(item.text);
        if (typeof parsed.image === "string") return parsed.image;
      } catch { /* not JSON screenshot content */ }
    }
  }
  throw new Error("Screenshot response did not contain base64 image data");
}

function tabSnapshot(response) {
  const value = resultValue(response);
  const tab = value.tab ?? value;
  if (typeof tab?.id !== "string" || !Number.isSafeInteger(tab.generation)) {
    throw new Error(`new-tab did not return a tab lease: ${JSON.stringify(response)}`);
  }
  return tab;
}

function tabsFrom(response) {
  const value = resultValue(response);
  if (!Array.isArray(value.tabs)) throw new Error(`get-tabs did not return tabs: ${JSON.stringify(response)}`);
  return value.tabs;
}

function activeTab(response) {
  const tab = tabsFrom(response).find(candidate => candidate.active);
  if (typeof tab?.id !== "string" || !Number.isInteger(tab.generation)) {
    throw new Error(`get-tabs did not return an active tab lease: ${JSON.stringify(response)}`);
  }
  return tab;
}

// `evaluate` answers `{ result: <value> }` (docs/api/browser.md). Unwrap once
// only: a described value such as `{ type: "nonfinite", value: "NaN" }` is
// itself the result, not another envelope.
function evalResult(response) {
  return resultValue(response);
}

async function requireUrl(readiness, expected, tabIdValue = undefined) {
  await waitFor(async () => {
    const state = await control(readiness, "get-current-url", tabIdValue === undefined ? {} : { tabId: tabIdValue });
    return sameUrl(resultValue(state).url, expected);
  }, `URL ${expected}`);
}

async function runSecurity(readiness) {
  const health = await rawRequest({ port: readiness.port, path: "/health", method: "GET" });
  assert.equal(health.status, 200, "health must remain public on loopback");

  const discovery = await rawRequest({
    port: readiness.port,
    path: "/v1/get-device-info",
    headers: { "content-type": "application/json" },
    body: "{}",
  });
  assert.equal(discovery.status, 200, "device discovery must remain public on loopback");
  assert.equal(discovery.json?.success, true, "public device discovery must return a valid response");

  const denied = await rawRequest({
    port: readiness.port,
    path: "/v1/get-tabs",
    headers: { "content-type": "application/json" },
    body: "{}",
  });
  assertion(denied.status === 401 || denied.status === 403, "missing bearer token must be rejected");

  for (const [name, headers] of Object.entries({
    "wrong bearer": { authorization: "Bearer wrong", "content-type": "application/json" },
    "browser origin": { authorization: `Bearer ${readiness.token}`, origin: "http://fixture.invalid", "content-type": "application/json" },
    "forged host": { authorization: `Bearer ${readiness.token}`, host: "fixture.invalid", "content-type": "application/json" },
  })) {
    const response = await rawRequest({ port: readiness.port, path: "/v1/get-tabs", headers, body: "{}" });
    assertion(response.status >= 400, `${name} must be rejected`);
  }

  const malformed = await rawRequest({
    port: readiness.port,
    path: "/v1/navigate",
    headers: { authorization: `Bearer ${readiness.token}`, "content-type": "application/json" },
    body: "{",
  });
  assertion(malformed.status >= 400, "malformed JSON must be rejected");

  const oversized = await rawRequest({
    port: readiness.port,
    path: "/v1/navigate",
    headers: { authorization: `Bearer ${readiness.token}`, "content-type": "application/json" },
    body: JSON.stringify({ url: "x".repeat(1_100_000) }),
  });
  assertion(oversized.status >= 400, "oversized request must be rejected");

  const wrongType = await rawRequest({
    port: readiness.port,
    path: "/v1/navigate",
    headers: { authorization: `Bearer ${readiness.token}`, "content-type": "application/json" },
    body: JSON.stringify({ url: 42 }),
  });
  assertion(wrongType.status >= 400, "wrong argument types must be rejected");
}

async function runBrowserActions(readiness, fixtureUrl) {
  await control(readiness, "navigate", { url: fixtureUrl });
  await requireUrl(readiness, fixtureUrl);
  await control(readiness, "wait-for-element", { selector: "#trusted-button", timeout: 10_000 });
  const text = resultValue(await control(readiness, "get-page-text", {}));
  assertion(JSON.stringify(text).includes("Kelpie Windows acceptance fixture"), "page text must expose fixture content");
  const accessibility = resultValue(await control(readiness, "get-accessibility-tree", { interactableOnly: true }));
  assertion(JSON.stringify(accessibility).includes("Trusted action"), "accessibility tree must expose the fixture button");
  const found = resultValue(await control(readiness, "find-element", { text: "Trusted action", role: "button" }));
  assertion(found.selector !== undefined || found.element?.selector !== undefined, "find-element must return an actionable selector");
  await control(readiness, "resize-viewport", { width: 960, height: 640 });
  const viewport = resultValue(await control(readiness, "get-viewport", {}));
  assert.equal(viewport.width, 960, "viewport resize must report its new width");
  await control(readiness, "reset-viewport", {});

  const evaluated = await control(readiness, "evaluate", { expression: "({ heading: document.querySelector('#heading').textContent, number: 7 })" });
  assert.deepEqual(evalResult(evaluated), { heading: "Kelpie Windows acceptance fixture", number: 7 }, "evaluation must return JSON values");
  assert.deepEqual(evalResult(await control(readiness, "evaluate", { expression: "undefined" })), { type: "undefined" },
    "evaluation must describe undefined without a second execution");
  assert.deepEqual(evalResult(await control(readiness, "evaluate", { expression: "NaN" })), { type: "nonfinite", value: "NaN" },
    "evaluation must describe non-finite values");
  assert.deepEqual(evalResult(await control(readiness, "evaluate", { expression: "12n" })), { type: "bigint", value: "12" },
    "evaluation must describe bigint values");
  assert.equal(evalResult(await control(readiness, "evaluate", { expression: "(()=>{const value={};value.self=value;return value})()" })).type,
    "cyclic", "evaluation must describe cyclic values");
  assert.deepEqual(evalResult(await control(readiness, "evaluate", { expression: "document.querySelector('#heading')" })),
    { type: "node", nodeName: "H1", nodeType: 1 }, "evaluation must describe DOM nodes");
  await expectControlError(readiness, "evaluate", { expression: "throw new Error('acceptance-error')" }, "JAVASCRIPT_ERROR");

  await control(readiness, "click", { selector: "#trusted-button" });
  await control(readiness, "type", { selector: "#text-input", text: "Žluťoučký kůň" });
  const inputResult = await control(readiness, "evaluate", { expression: "({ ...window.fixture, value: document.querySelector('#text-input').value })" });
  const inputValue = evalResult(inputResult);
  assert.equal(inputValue.clickTrusted, true, "click must reach the page as trusted native input");
  assert.equal(inputValue.value, "Žluťoučký kůň", "typing must retain Unicode text");

  await control(readiness, "fill", { selector: "#text-input", value: "filled value" });
  let formValue = evalResult(await control(readiness, "evaluate", {
    expression: "({ value: document.querySelector('#text-input').value, inputTrusted: window.fixture.inputTrusted })",
  }));
  assert.deepEqual(formValue, { value: "filled value", inputTrusted: true },
    "fill must replace the value and emit a trusted input event");
  await control(readiness, "fill", { selector: "#text-input", value: "" });
  assert.equal(evalResult(await control(readiness, "evaluate", { expression: "document.querySelector('#text-input').value" })), "",
    "fill must clear a field when given an empty value");

  await control(readiness, "select-option", { selector: "#select-input", value: "second" });
  formValue = evalResult(await control(readiness, "evaluate", {
    expression: "({ value: document.querySelector('#select-input').value, trusted: window.fixture.selectTrusted })",
  }));
  assert.deepEqual(formValue, { value: "second", trusted: true },
    "select-option must select the requested option with a trusted change event");
  await control(readiness, "check", { selector: "#check-input" });
  formValue = evalResult(await control(readiness, "evaluate", {
    expression: "({ checked: document.querySelector('#check-input').checked, trusted: window.fixture.checkTrusted })",
  }));
  assert.deepEqual(formValue, { checked: true, trusted: true }, "check must emit a trusted change event");
  await control(readiness, "uncheck", { selector: "#check-input" });
  assert.equal(evalResult(await control(readiness, "evaluate", { expression: "document.querySelector('#check-input').checked" })), false,
    "uncheck must clear the checkbox");
  await expectControlError(readiness, "fill", { selector: "#disabled-input", value: "must fail" });
  await expectControlError(readiness, "click", { selector: "#missing-target" }, "ELEMENT_NOT_FOUND");

  // press-key targets the focused element and the fixture listens on the text
  // input, but the check/uncheck clicks above left focus on the checkbox.
  await control(readiness, "click", { selector: "#text-input" });
  await control(readiness, "evaluate", { expression: "window.fixture.keyTrusted = null; window.fixture.lastKey = null; true" });
  const keyTab = activeTab(await control(readiness, "get-tabs", {}));
  const pressed = await control(readiness, "press-key", {
    tabId: keyTab.id, generation: keyTab.generation, key: "A", code: "KeyA",
  });
  assert.equal(resultValue(pressed).input?.trusted, true, "press-key must confirm native input completion");
  const keyResult = await control(readiness, "evaluate", { expression: "({ keyTrusted: window.fixture.keyTrusted, lastKey: window.fixture.lastKey })" });
  const keyValue = evalResult(keyResult);
  assert.equal(keyValue.keyTrusted, true, "press-key must reach the page as a trusted native keydown");
  assert.equal(keyValue.lastKey, "A", "press-key must deliver the requested key");

  await control(readiness, "scroll", { deltaY: 800, deltaX: 0 });
  const scrollResult = await control(readiness, "evaluate", { expression: "window.scrollY > 0" });
  assert.equal(evalResult(scrollResult), true, "scroll must move the document");

  const screenshot = await control(readiness, "screenshot", { format: "png" });
  const decoded = decodePng(Buffer.from(imageFrom(screenshot), "base64"));
  assertion(decoded.width > 0 && decoded.height > 0, "screenshot must decode to a non-empty PNG");
  await expectControlError(readiness, "screenshot", { format: "jpeg" });

  // A later navigation must win even when the earlier page is still loading.
  const slowNavigation = control(readiness, "navigate", { url: `${fixtureUrl}/slow` });
  await new Promise(resolve => setTimeout(resolve, 100));
  await control(readiness, "navigate", { url: fixtureUrl });
  await Promise.allSettled([slowNavigation]);
  await new Promise(resolve => setTimeout(resolve, 2_200));
  await requireUrl(readiness, fixtureUrl);

  await control(readiness, "click", { selector: "#next-link" });
  await requireUrl(readiness, `${fixtureUrl}/next`);
  await control(readiness, "back", {});
  await requireUrl(readiness, fixtureUrl);
  await control(readiness, "forward", {});
  await requireUrl(readiness, `${fixtureUrl}/next`);
  await control(readiness, "reload", {});

  await control(readiness, "navigate", { url: fixtureUrl });
  await control(readiness, "click", { selector: "#dialog-button" });
  await waitFor(async () => {
    const dialog = resultValue(await control(readiness, "get-dialog", {}));
    return dialog.showing === true && dialog.dialog !== undefined;
  }, "native dialog observation");
  await control(readiness, "handle-dialog", { action: "accept" });
  await waitFor(async () => evalResult(await control(readiness, "evaluate", { expression: "window.fixture.dialogHandled" })) === true,
    "dialog acceptance");

  await control(readiness, "set-cookie", {
    name: "acceptance_cookie", value: "present", domain: "127.0.0.1", path: "/", httpOnly: true,
    sameSite: "Lax", secure: false, expires: "2030-01-01T00:00:00.000Z",
  });
  const cookies = resultValue(await control(readiness, "get-cookies", { url: fixtureUrl }));
  const cookie = (cookies.cookies ?? []).find(item => item.name === "acceptance_cookie");
  assert.equal(cookie?.httpOnly, true, "cookie manager must retain httpOnly");
  assert.equal(String(cookie?.sameSite).toLowerCase(), "lax", "cookie manager must retain sameSite");
  await expectControlError(readiness, "set-cookie", {
    // Epoch seconds are a valid expiry (a past one deletes the cookie); an
    // unparseable date is not.
    name: "invalid_cookie", value: "present", domain: "127.0.0.1", expires: "not a date",
  });
  await control(readiness, "set-storage", { type: "local", key: "acceptance", value: "stored" });
  const storage = resultValue(await control(readiness, "get-storage", { type: "local", key: "acceptance" }));
  assert.equal(storage.entries?.acceptance, "stored", "local storage must round-trip");

  const consoleEntries = resultValue(await control(readiness, "get-console-messages", { limit: 100 }));
  assertion(Array.isArray(consoleEntries.messages), "console response must contain messages");
  assertion(consoleEntries.messages.some(entry => String(entry.text).includes("kelpie-fixture-console")),
    "native console observer must record the fixture console output");
  await waitFor(async () => {
    const networkEntries = resultValue(await control(readiness, "get-network-log", { limit: 100 }));
    return Array.isArray(networkEntries.entries) && networkEntries.entries.some(entry => entry.url === `${fixtureUrl}/api/ping`);
  }, "native network observation");

  await control(readiness, "bookmarks-add", { url: fixtureUrl, title: "Acceptance fixture" });
  const bookmarks = resultValue(await control(readiness, "bookmarks-list", {}));
  assertion(Array.isArray(bookmarks.bookmarks) && bookmarks.bookmarks.some(item => item.url === fixtureUrl), "bookmark must be stored");
  const history = resultValue(await control(readiness, "history-list", {}));
  assertion(Array.isArray(history.entries) && history.entries.some(item => sameUrl(item.url, fixtureUrl)), "history must contain fixture navigation");
  await control(readiness, "set-home", { url: fixtureUrl });
  const home = resultValue(await control(readiness, "get-home", {}));
  assert.equal(home.url ?? home.home, fixtureUrl, "home page must persist through the browser control surface");

  const firstTabs = tabsFrom(await control(readiness, "get-tabs", {}));
  assert.equal(firstTabs.length, 1, "isolated profile must start with one tab");
  const original = firstTabs[0];
  if (typeof original?.id !== "string" || !Number.isSafeInteger(original.generation)) {
    throw new Error(`get-tabs did not return the original tab lease: ${JSON.stringify(firstTabs)}`);
  }
  const second = tabSnapshot(await control(readiness, "new-tab", { url: fixtureUrl }));
  const third = tabSnapshot(await control(readiness, "new-tab", { url: `${fixtureUrl}/next` }));
  await expectControlError(readiness, "evaluate", { expression: "document.title" }, "TAB_REQUIRED");
  await expectControlError(readiness, "evaluate", {
    tabId: second.id, generation: second.generation + 1, expression: "document.title",
  }, "TAB_STALE");
  await control(readiness, "switch-tab", { tabId: original.id, generation: original.generation });
  for (const tab of [second, third, original, second]) {
    await control(readiness, "switch-tab", { tabId: tab.id, generation: tab.generation });
  }
  await control(readiness, "switch-tab", { tabId: original.id, generation: original.generation });
  await control(readiness, "navigate", {
    tabId: second.id, generation: second.generation, url: `${fixtureUrl}/next`,
  });
  const activeAfterBackground = tabsFrom(await control(readiness, "get-tabs", {})).find(tab => tab.active);
  assert.equal(activeAfterBackground?.id, original.id, "background tab commands must not change native selection");
  await expectControlError(readiness, "switch-tab", { tabId: "no-such-tab", generation: 1 }, "TAB_NOT_FOUND");
  await Promise.all([
    [original, "Kelpie Windows fixture"],
    [second, "Kelpie next page"],
    [third, "Kelpie next page"],
  ].map(async ([tab, expected]) => {
    await waitFor(async () => {
      const response = await control(readiness, "evaluate", {
        tabId: tab.id, generation: tab.generation, expression: "document.title",
      });
      return evalResult(response) === expected;
    }, `background tab ${tab.id} title`);
  }));
  const activeBeforeHiddenShot = activeTab(await control(readiness, "get-tabs", {}));
  const originalImage = imageFrom(await control(readiness, "screenshot", {
    tabId: original.id, generation: original.generation, format: "png",
  }));
  const hiddenImage = imageFrom(await control(readiness, "screenshot", {
    tabId: second.id, generation: second.generation, format: "png",
  }));
  decodePng(Buffer.from(hiddenImage, "base64"));
  assert.notEqual(hiddenImage, originalImage, "hidden tab screenshot must contain its distinct fixture page");
  assert.equal(activeTab(await control(readiness, "get-tabs", {})).id, activeBeforeHiddenShot.id,
    "background screenshot must not change native selection");
  await control(readiness, "click", { tabId: original.id, generation: original.generation, selector: "#popup-button" });
  await waitFor(async () => tabsFrom(await control(readiness, "get-tabs", {})).length >= 4, "popup tab creation");
  for (const tab of [...tabsFrom(await control(readiness, "get-tabs", {}))]) {
    await control(readiness, "close-tab", { tabId: tab.id, generation: tab.generation });
  }
  assert.equal(tabsFrom(await control(readiness, "get-tabs", {})).length, 1, "closing the last tab must replace it with a blank tab");

  await control(readiness, "navigate", { url: fixtureUrl });
}

async function prepareRestoration(readiness, fixtureUrl) {
  const retainedUrl = fixtureUrl;
  const otherUrl = `${fixtureUrl}/next`;
  const closedUrl = `${fixtureUrl}/popup`;
  await control(readiness, "navigate", { url: retainedUrl });
  await requireUrl(readiness, retainedUrl);
  const retained = activeTab(await control(readiness, "get-tabs", {}));
  const other = tabSnapshot(await control(readiness, "new-tab", { url: otherUrl }));
  const closed = tabSnapshot(await control(readiness, "new-tab", { url: closedUrl }));
  await control(readiness, "close-tab", { tabId: closed.id, generation: closed.generation });
  await control(readiness, "switch-tab", { tabId: retained.id, generation: retained.generation });
  await waitFor(async () => {
    const tabs = tabsFrom(await control(readiness, "get-tabs", {}));
    return tabs.some(tab => tab.id === retained.id && sameUrl(tab.url, retainedUrl) && tab.active) &&
      tabs.some(tab => tab.id === other.id && sameUrl(tab.url, otherUrl)) &&
      !tabs.some(tab => tab.id === closed.id);
  }, "persisted two-tab restoration state");
  return {
    retained: { id: retained.id, url: retainedUrl },
    other: { id: other.id, url: otherUrl },
    closed: { id: closed.id, url: closedUrl },
  };
}

async function runMcp(readiness, fixtureUrl) {
  const init = await mcpRequest(readiness, {
    jsonrpc: "2.0", id: 1, method: "initialize",
    params: { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "kelpie-windows-acceptance", version: "1" } },
  });
  assert.equal(init.status, 200, `MCP initialize failed: ${init.text}`);
  const protocolVersion = init.json?.result?.protocolVersion;
  assertion(typeof protocolVersion === "string", "MCP initialize must negotiate a protocol version");
  const notification = await mcpRequest(readiness, { jsonrpc: "2.0", method: "notifications/initialized", params: {} }, protocolVersion);
  assert.equal(notification.status, 202, "MCP notifications must return HTTP 202");
  assert.equal(notification.text, "", "MCP notifications must not return a JSON-RPC body");
  const get = await rawRequest({ port: readiness.port, path: readiness.mcp.endpoint, method: "GET", headers: { authorization: `Bearer ${readiness.token}` } });
  assert.equal(get.status, 405, "stateless MCP transport must reject GET without SSE");

  const listed = await mcpRequest(readiness, { jsonrpc: "2.0", id: 2, method: "tools/list", params: {} }, protocolVersion);
  assert.equal(listed.status, 200, `MCP tools/list failed: ${listed.text}`);
  const tools = listed.json?.result?.tools;
  assertion(Array.isArray(tools) && tools.length > 0, "MCP must list callable tools");
  for (const tool of tools) {
    assertion(typeof tool.name === "string" && tool.name.startsWith("kelpie_"), "MCP tools need kelpie_ names");
    assertion(tool.inputSchema?.type === "object", `MCP tool ${tool.name} needs an object input schema`);
  }
  // Every Windows control exercised above must be exposed through MCP as well.
  // Direct HTTP proves the action works; this inventory check prevents a usable
  // route from being silently unavailable to development/Nessie agents.
  for (const name of [
    "kelpie_navigate", "kelpie_back", "kelpie_forward", "kelpie_reload",
    "kelpie_evaluate", "kelpie_get_page_text", "kelpie_get_accessibility_tree", "kelpie_find_element",
    "kelpie_click", "kelpie_fill", "kelpie_type", "kelpie_select_option", "kelpie_check", "kelpie_uncheck", "kelpie_press_key", "kelpie_scroll", "kelpie_wait_for_element",
    "kelpie_screenshot", "kelpie_get_dialog", "kelpie_handle_dialog",
    "kelpie_get_tabs", "kelpie_new_tab", "kelpie_switch_tab", "kelpie_close_tab",
    "kelpie_get_cookies", "kelpie_set_cookie", "kelpie_get_storage", "kelpie_set_storage",
    "kelpie_get_console_messages", "kelpie_get_network_log",
    "kelpie_bookmarks_add", "kelpie_bookmarks_list", "kelpie_history_list",
    "kelpie_set_home", "kelpie_get_home", "kelpie_resize_viewport", "kelpie_reset_viewport",
  ]) {
    assertion(tools.some(tool => tool.name === name), `required MCP tool ${name} was not listed`);
  }

  const navigate = await mcpRequest(readiness, { jsonrpc: "2.0", id: 3, method: "tools/call", params: { name: "kelpie_navigate", arguments: { url: fixtureUrl } } }, protocolVersion);
  assert.equal(navigate.status, 200, `MCP navigation failed: ${navigate.text}`);
  assert.notEqual(navigate.json?.result?.isError, true, "MCP navigation tool must be callable");
  assert.equal(JSON.parse(navigate.json?.result?.content?.find(item => item.type === "text")?.text ?? "{}").success, true,
    "MCP navigation tool must return a success payload");
  const screenshot = await mcpRequest(readiness, { jsonrpc: "2.0", id: 4, method: "tools/call", params: { name: "kelpie_screenshot", arguments: { format: "png" } } }, protocolVersion);
  assert.equal(screenshot.status, 200, `MCP screenshot failed: ${screenshot.text}`);
  assert.notEqual(screenshot.json?.result?.isError, true, `MCP screenshot tool must be callable: ${screenshot.text.slice(0, 500)}`);
  decodePng(Buffer.from(imageFrom(screenshot.json?.result), "base64"));
}

async function loadNessieClient(nessieRoot) {
  const entry = `${nessieRoot}/packages/mcp-client/dist/index.js`;
  if (!existsSync(entry)) throw new Error(`Nessie MCP client is not built: ${entry}`);
  return import(pathToFileURL(entry).href);
}

export async function runNessieClient(readiness, fixtureUrl, nessieRoot) {
  const { McpClientManager } = await loadNessieClient(nessieRoot);
  const manager = new McpClientManager();
  const id = await manager.open({
    transport: "http", url: `http://127.0.0.1:${readiness.port}${readiness.mcp.endpoint}`,
    headers: { Authorization: `Bearer ${readiness.token}` }, fetchImpl: globalThis.fetch,
  });
  try {
    const tools = await manager.listTools(id, { timeoutMs: 10_000 });
    assertion(tools.some(tool => tool.name === "kelpie_navigate"), "Nessie client did not discover kelpie_navigate");
    const text = await manager.callTool(id, "kelpie_navigate", { url: fixtureUrl }, { timeoutMs: 10_000 });
    assert.notEqual(text.isError, true, "Nessie client navigation must succeed");
    const image = await manager.callTool(id, "kelpie_screenshot", { format: "png" }, { timeoutMs: 10_000 });
    assert.notEqual(image.isError, true, "Nessie client screenshot must succeed");
    decodePng(Buffer.from(imageFrom(image), "base64"));
  } finally {
    await manager.close(id);
  }
}

/**
 * Runs Nessie's actual stdio transport through the CLI alias. The CLI is the
 * only component that reads the local readiness capability; the client gets
 * neither a loopback URL nor a bearer token.
 */
export async function runNessieStdioClient({ cliPath, cliHome, alias, fixtureUrl, nessieRoot }) {
  const { McpClientManager } = await loadNessieClient(nessieRoot);
  const manager = new McpClientManager();
  const id = await manager.open({
    transport: "stdio",
    command: process.execPath,
    args: [cliPath, "--browser", alias, "mcp"],
    env: { ...process.env, KELPIE_HOME: cliHome },
  });
  try {
    const tools = await manager.listTools(id, { timeoutMs: 10_000 });
    assertion(tools.some(tool => tool.name === "kelpie_navigate"), "Nessie stdio client did not discover kelpie_navigate");
    const navigation = await manager.callTool(id, "kelpie_navigate", { url: fixtureUrl }, { timeoutMs: 10_000 });
    assert.notEqual(navigation.isError, true, "Nessie stdio navigation through the CLI must succeed");
    const screenshot = await manager.callTool(id, "kelpie_screenshot", { format: "png" }, { timeoutMs: 10_000 });
    assert.notEqual(screenshot.isError, true, "Nessie stdio screenshot through the CLI must succeed");
    assertion(screenshot.content?.some(item => item.type === "image" && item.mimeType === "image/png"),
      "Nessie stdio screenshot must expose a portable MCP PNG image block");
    decodePng(Buffer.from(imageFrom(screenshot), "base64"));
  } finally {
    await manager.close(id);
  }
}

export async function runLiveAcceptance(readiness, fixtureUrl, nessieRoot) {
  await runSecurity(readiness);
  await runBrowserActions(readiness, fixtureUrl);
  await runMcp(readiness, fixtureUrl);
  await runNessieClient(readiness, fixtureUrl, nessieRoot);
  return prepareRestoration(readiness, fixtureUrl);
}
