import assert from "node:assert/strict";
import { once } from "node:events";
import { createServer } from "node:http";

import { control, expectControlError, mcpRequest, resultValue, waitFor } from "./http.mjs";

async function listen(handler) {
  const server = createServer(handler);
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  return { server, url: `http://127.0.0.1:${server.address().port}` };
}

async function startDiagnosticFixture() {
  const api = await listen((request, response) => {
    if (request.url.endsWith("/offline")) {
      request.socket.destroy();
      return;
    }
    const status = request.url.endsWith("/missing") ? 404
      : request.url.endsWith("/unavailable") ? 503 : 204;
    request.resume();
    response.writeHead(status, { "Access-Control-Allow-Origin": "*", "Cache-Control": "no-store" });
    response.end(status === 204 ? "" : "{}");
  });
  const pages = await listen((request, response) => {
    if (request.url === "/favicon.ico") {
      response.writeHead(204).end();
      return;
    }
    if (request.url === "/module.js") {
      response.writeHead(200, { "Content-Type": "text/javascript" }).end("export {};");
      return;
    }
    const tab = request.url === "/a" ? "a" : "b";
    const origin = `${api.url}/${tab}`;
    response.writeHead(200, { "Content-Type": "text/html" });
    response.end(`<!doctype html><title>Diagnostics ${tab}</title>
      <script>
        window.runDiagnostics = async () => {
          console.warn("diagnostic-warning-${tab}");
          console.error("diagnostic-error-${tab}");
          const preload = document.createElement("link");
          preload.rel = "modulepreload";
          preload.href = "/module.js";
          document.head.append(preload);
          const missing = await fetch(${JSON.stringify(origin + "/missing")}, { method: "POST", body: "{}" });
          await missing.text();
          const ok = await fetch(${JSON.stringify(origin + "/ok")});
          const unavailable = await new Promise((resolve, reject) => {
            const xhr = new XMLHttpRequest();
            xhr.open("GET", ${JSON.stringify(origin + "/unavailable")});
            xhr.onload = () => resolve(xhr.status);
            xhr.onerror = reject;
            xhr.send();
          });
          const offline = await fetch(${JSON.stringify(origin + "/offline")}).then(() => false, () => true);
          return {missing: missing.status, ok: ok.status, unavailable, offline};
        };
      </script>`);
  });
  return {
    url: pages.url,
    api: api.url,
    close: () => {
      pages.server.close();
      api.server.close();
    },
  };
}

async function callDiagnosticTool(readiness, name, args) {
  const response = await mcpRequest(readiness, {
    jsonrpc: "2.0", id: 11, method: "tools/call",
    params: { name: "kelpie_extension", arguments: { name, arguments: args } },
  });
  assert.equal(response.status, 200, response.text);
  assert.ok(response.json?.result, response.text);
  assert.notEqual(response.json.result.isError, true, response.text);
  const result = response.json?.result;
  const decoded = result?.structuredContent ?? JSON.parse(result?.content?.find(item => item.type === "text")?.text ?? "{}");
  return decoded.value ?? decoded;
}

export async function runBrowserDiagnostics(readiness) {
  const fixture = await startDiagnosticFixture();
  const tabs = [];
  let verificationError;
  try {
    for (const label of ["a", "b"]) {
      // Attach the DevTools observer before navigation so initial resources are captured.
      const created = resultValue(await control(readiness, "new-tab", { url: "about:blank" }));
      const tab = created.tabId ?? created.tab?.id ?? created.id;
      assert.equal(typeof tab, "string");
      tabs.push(tab);
      await control(readiness, "switch-tab", { tabId: tab });
      await control(readiness, "navigate", { tabId: tab, url: `${fixture.url}/${label}` });
      const observed = resultValue(await control(readiness, "evaluate", {
        tabId: tab, expression: "window.runDiagnostics()",
      }));
      assert.deepEqual(observed, {missing: 404, ok: 204, unavailable: 503, offline: true});
    }
    const [first, second] = tabs;
    const marker = (rows, text) => rows.some(row => row.text === text);
    for (const [id, label] of [[first, "a"], [second, "b"]]) {
      await waitFor(async () => {
        const log = await control(readiness, "get-network-log", { tabId: id });
        const matching = log.entries.find(entry => entry.url === `${fixture.api}/${label}/offline`);
        if (!matching?.failure) {
          throw new Error(JSON.stringify(log.entries.map(({url, status, type, failure}) => ({url, status, type, failure}))));
        }
        return true;
      }, `transport failure for tab ${label}`);
    }

    const consoleLog = await control(readiness, "get-console-messages", { tabId: first });
    assert.ok(marker(consoleLog.messages, "diagnostic-warning-a"));
    assert.ok(marker(consoleLog.messages, "diagnostic-error-a"));
    assert.ok(consoleLog.messages.every(message => message.tabId === first));
    assert.ok(!marker(consoleLog.messages, "diagnostic-error-b"));
    const errors = await callDiagnosticTool(readiness, "kelpie_get_js_errors", { tabId: second });
    assert.ok(marker(errors.errors, "diagnostic-error-b"));
    assert.ok(!marker(errors.errors, "diagnostic-error-a"));
    const absent = await callDiagnosticTool(readiness, "kelpie_get_console_messages", {
      tabId: second, since: "2099-01-01T00:00:00.000Z",
    });
    assert.equal(absent.count, 0);
    assert.equal(absent.hasMore, false);

    const network = await control(readiness, "get-network-log", { tabId: first });
    assert.ok(network.entries.every(entry => entry.tabId === first));
    const lookup = (rows, path) => rows.find(entry => entry.url === `${fixture.api}/a/${path}`);
    const missing = lookup(network.entries, "missing");
    assert.ok(missing, JSON.stringify(network.entries));
    assert.equal(missing.status, 404);
    assert.equal(missing.method, "POST");
    assert.equal(missing.type, "fetch");
    const unavailable = lookup(network.entries, "unavailable");
    assert.equal(unavailable.status, 503);
    assert.equal(unavailable.method, "GET");
    assert.equal(unavailable.type, "xhr");
    assert.equal(lookup(network.entries, "ok").status, 204);
    assert.equal(lookup(network.entries, "offline").status, null);
    assert.ok(network.entries.some(entry => entry.url.endsWith("/module.js") && entry.type === "script"));
    assert.ok(network.entries.every(entry => entry.timing.total >= 0));

    const httpFailed = await control(readiness, "get-network-log", { tabId: first, status: "error" });
    const failed = await callDiagnosticTool(readiness, "kelpie_get_network_log", { tabId: first, status: "error" });
    assert.ok(lookup(failed.entries, "missing"));
    assert.ok(lookup(failed.entries, "unavailable"));
    assert.ok(lookup(failed.entries, "offline").failure);
    assert.deepEqual(failed, httpFailed);
    assert.ok(!lookup(failed.entries, "ok"));
    assert.equal(failed.summary.errors, network.summary.errors);
    assert.equal(failed.summary.totalRequests, network.summary.totalRequests);
    assert.equal(failed.count, failed.summary.errors);
    const limited = await control(readiness, "get-network-log", { tabId: first, status: "error", limit: 1 });
    assert.equal(limited.count, 1);
    assert.equal(limited.hasMore, true);
    assert.equal(limited.summary.errors, failed.summary.errors);

    const browserWide = await control(readiness, "get-network-log");
    for (const tabId of tabs) {
      assert.ok(browserWide.entries.some(entry => entry.tabId === tabId));
    }

    await control(readiness, "close-tab", { tabId: first });
    tabs.shift();
    await expectControlError(readiness, "get-console-messages", { tabId: first }, "TAB_NOT_FOUND");
    await expectControlError(readiness, "get-network-log", { tabId: first }, "TAB_NOT_FOUND");
    console.log("Native diagnostics passed for two tabs via HTTP and MCP");
  } catch (error) {
    verificationError = error;
    throw error;
  } finally {
    try {
      for (const tabId of tabs.reverse()) await control(readiness, "close-tab", { tabId });
    } catch (cleanupError) {
      if (!verificationError) throw cleanupError;
    } finally {
      fixture.close();
    }
  }
}
