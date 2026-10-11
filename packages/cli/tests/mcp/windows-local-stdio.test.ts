import { afterEach, describe, expect, it } from "vitest";
import { createServer, type Server } from "node:http";
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

async function listen(server: Server): Promise<number> {
  await new Promise<void>((resolveListen) => server.listen(0, "127.0.0.1", resolveListen));
  const address = server.address();
  if (!address || typeof address === "string") throw new Error("No TCP address");
  return address.port;
}

// The CLI runs as a real child process from source (`node --import tsx`), so
// the test proves the code under test rather than whatever dist was last
// built. Starting that child and transpiling the CLI is nearly all of its cost:
// measured 2.3–6.6 s on Windows (6.6 s with a cold tsx cache), against ~0.2 s
// for the MCP handshake and every tool call together. The 5 s default failed it
// under the parallel suite; this leaves ~3x the worst measurement and still
// fails a child that never answers.
const SPAWNED_CLI_TIMEOUT_MS = 20_000;

describe("Windows local alias MCP stdio", () => {
  const servers: Server[] = [];
  const roots: string[] = [];
  const transports: StdioClientTransport[] = [];
  afterEach(async () => {
    await Promise.all(transports.map(async (transport) => transport.close()));
    await Promise.all(servers.map((server) => new Promise<void>((resolveClose) => server.close(() => resolveClose()))));
    await Promise.all(roots.map((root) => rm(root, { recursive: true, force: true })));
  });

  it("uses the native callable catalogue and protected readiness capability through the MCP SDK", async () => {
    const token = "a".repeat(48);
    let capabilityAuthorized = false;
    let navigationAuthorized = false;
    const server = createServer((request, response) => {
      if (request.headers.authorization !== `Bearer ${token}`) { response.writeHead(401); response.end(JSON.stringify({ success: false })); return; }
      let body = "";
      request.on("data", (chunk: Buffer) => { body += chunk.toString(); });
      request.on("end", () => {
        response.setHeader("content-type", "application/json");
        if (request.url === "/v1/get-capabilities") {
          capabilityAuthorized = true;
          response.end(JSON.stringify({ success: true, supported: ["navigate", "screenshot", "get-capabilities"] }));
          return;
        }
        if (request.url === "/v1/browser-control") {
          const input = JSON.parse(body) as { method: string; params?: { url?: string; selector?: string } };
          const value = input.method === "capabilities" ? { version: 1, methods: ["tab.goto", "tab.screenshot"], extensions: [] }
            : input.method === "tab.screenshot" ? { type: "image", data: "cG5n", mimeType: "image/png" } : null;
          const fail = input.params?.url?.includes("fail");
          response.end(JSON.stringify(fail ? { version: 1, ok: false, error: { code: "COMMAND_FAILED", message: "Observe again", mayHaveCompleted: true } } : { version: 1, ok: true, value }));
          return;
        }
        if (request.url === "/v1/navigate") {
          navigationAuthorized = true;
          const url = JSON.parse(body).url as string;
          response.end(JSON.stringify(url.includes("fail") ? { success: false, error: { code: "NAVIGATION_FAILED" } } : { success: true, url }));
          return;
        }
        if (request.url === "/v1/screenshot") {
          response.end(JSON.stringify({ success: true, image: "cG5n", format: "png", resolution: "viewport" }));
          return;
        }
        response.writeHead(404); response.end(JSON.stringify({ success: false }));
      });
    });
    servers.push(server);
    const port = await listen(server);
    const root = await mkdtemp(join(tmpdir(), "kelpie-mcp-alias-")); roots.push(root);
    const profile = join(root, "profile"); await mkdir(profile);
    await writeFile(join(profile, "readiness.json"), JSON.stringify({ version: 1, launchId: "launch-1", deviceId: "device-1", port, token, controlMode: "loopback", mcp: { http: true, stdio: false, endpoint: "/mcp" } }), { mode: 0o600 });
    await writeFile(join(root, "browsers.json"), JSON.stringify({ aliases: { win: { platform: "windows", profileDir: profile } }, running: { win: { port, lastLaunchedAt: new Date().toISOString(), launchId: "launch-1", readinessFile: join(profile, "readiness.json"), deviceId: "device-1" } } }));

    const transport = new StdioClientTransport({ command: process.execPath, args: ["--import", "tsx", resolve("src/index.ts"), "--browser", "win", "mcp"], cwd: process.cwd(), env: { ...process.env, KELPIE_HOME: root }, stderr: "pipe" });
    transports.push(transport);
    const client = new Client({ name: "nessie-local-test", version: "test" });
    let childErrors = "";
    transport.stderr?.on("data", (chunk: Buffer) => { childErrors += chunk.toString(); });
    try { await client.connect(transport); }
    catch (error) { throw new Error(`${String(error)}\n${childErrors}`, { cause: error }); }
    const tools = await client.listTools();
    expect(capabilityAuthorized).toBe(true);
    expect(tools.tools.map((tool) => tool.name)).toEqual(["kelpie_browser_control", "kelpie_extensions", "kelpie_extension_tools", "kelpie_extension"]);
    expect(tools.tools.map((tool) => tool.name)).not.toContain("kelpie_ai_ask");
    expect(tools.tools.map((tool) => tool.name)).not.toContain("kelpie_find_element");

    expect(tools.tools.map((tool) => tool.name)).toContain("kelpie_browser_control");
    const coreDefinition = tools.tools.find((tool) => tool.name === "kelpie_browser_control")!;
    expect(JSON.stringify(coreDefinition.inputSchema).length).toBeLessThan(24_000);
    expect(JSON.stringify(coreDefinition.inputSchema)).not.toContain("locator.fill");
    const coreCapabilities = await client.callTool({ name: "kelpie_browser_control", arguments: { request: { version: 1, method: "capabilities", params: {} } } });
    const capabilityText = (coreCapabilities.content as { type: string; text?: string }[]).find((item) => item.type === "text")?.text;
    const coreMethods = JSON.parse(capabilityText ?? "{}").value.methods as string[];
    expect(coreMethods).toContain("tab.goto");
    expect(coreMethods).not.toContain("locator.click");
    expect(coreMethods).not.toContain("page.press");
    const coreNavigation = await client.callTool({ name: "kelpie_browser_control", arguments: { request: { version: 1, method: "tab.goto", tabId: "owned-tab", params: { url: "https://example.test/core" } } } });
    expect(coreNavigation.isError).not.toBe(true);
    const coreFailure = await client.callTool({ name: "kelpie_browser_control", arguments: { request: { version: 1, method: "tab.goto", tabId: "owned-tab", params: { url: "https://fail.test" } } } });
    expect(coreFailure.isError).toBe(true);
    expect(JSON.stringify(coreFailure.content)).toContain("mayHaveCompleted");
    const coreScreenshot = await client.callTool({ name: "kelpie_browser_control", arguments: { request: { version: 1, method: "tab.screenshot", tabId: "owned-tab", params: {} } } });
    const coreBlocks = coreScreenshot.content as { type: string; text?: string; data?: string }[];
    expect(coreBlocks.filter((item) => item.type === "image")).toEqual([{ type: "image", data: "cG5n", mimeType: "image/png" }]);
    expect(coreBlocks.filter((item) => item.type === "text").some((item) => item.text?.includes("cG5n"))).toBe(false);
    const invalid = await client.callTool({ name: "kelpie_browser_control", arguments: { request: { version: 1, method: "tab.click", tabId: "owned-tab", params: { ref: "e1", selector: "#guess" } } } });
    expect(invalid.isError).toBe(true);

    const discovery = await client.callTool({ name: "kelpie_extension_tools", arguments: { names: ["kelpie_navigate"] } });
    expect(JSON.stringify(discovery.content)).toContain("url");
    const navigation = await client.callTool({ name: "kelpie_extension", arguments: { name: "kelpie_navigate", arguments: { url: "https://example.test" } } });
    expect(navigation.isError).not.toBe(true);
    expect(navigationAuthorized).toBe(true);
    const failure = await client.callTool({ name: "kelpie_navigate", arguments: { url: "https://fail.test" } });
    expect(failure.isError).toBe(true);
    const screenshot = await client.callTool({ name: "kelpie_screenshot", arguments: {} });
    expect(screenshot.content).toContainEqual({ type: "image", data: "cG5n", mimeType: "image/png" });
    await client.close();
  }, SPAWNED_CLI_TIMEOUT_MS);
});
