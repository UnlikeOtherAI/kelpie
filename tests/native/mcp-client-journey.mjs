import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { pathToFileURL } from "node:url";
import { runInferenceJourney } from "./inference-journey.mjs";

const readiness = JSON.parse(await readFile(process.argv[2], "utf8"));
const require = createRequire(new URL("../../packages/cli/package.json", import.meta.url));
const { Client } = await import(pathToFileURL(require.resolve("@modelcontextprotocol/sdk/client/index.js")));
const { StreamableHTTPClientTransport } = await import(pathToFileURL(require.resolve("@modelcontextprotocol/sdk/client/streamableHttp.js")));
const client = new Client({ name: "kelpie-native-contract", version: "1" });
const transport = new StreamableHTTPClientTransport(new URL(`http://127.0.0.1:${readiness.port}/mcp`), {
  requestInit: { headers: { authorization: `Bearer ${readiness.token}` } },
});
try {
  // The standard client performs initialize and notifications/initialized itself.
  await client.connect(transport);
  const { tools } = await client.listTools();
  assert.deepEqual(tools.map(tool => tool.name), ["kelpie_browser_control", "kelpie_extensions", "kelpie_extension_tools", "kelpie_extension"]);
  const result = await client.callTool({ name: "kelpie_browser_control", arguments: { request: { version: 1, method: "capabilities" } } });
  assert.equal(result.isError, false);
  const envelope = JSON.parse(result.content.find(block => block.type === "text").text);
  assert.equal(envelope.ok, true);
  const extensions = await client.callTool({ name: "kelpie_extensions", arguments: {} });
  assert.equal(extensions.isError, false);
  const names = JSON.parse(extensions.content.find(block => block.type === "text").text).value;
  assert.ok(names.includes("kelpie_get_capabilities"));
  const rich = await client.callTool({ name: "kelpie_extension", arguments: { name: "kelpie_get_capabilities", arguments: {} } });
  assert.equal(rich.isError, false);
  if (process.platform === "win32" && names.includes("kelpie_ai_ask")) await runInferenceJourney(client);
  const notification = await fetch(`http://127.0.0.1:${readiness.port}/mcp`, {
    method: "POST", headers: { authorization: `Bearer ${readiness.token}`, "content-type": "application/json", accept: "application/json, text/event-stream", "mcp-protocol-version": "2025-06-18" },
    body: JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }),
  });
  assert.equal(notification.status, 202);
  assert.equal(await notification.text(), "");
  console.log("Standard native MCP client journey passed", { catalogBytes: Buffer.byteLength(JSON.stringify(tools)), extensions: names.length, browserMethods: envelope.value.methods });
} finally { await client.close(); }
