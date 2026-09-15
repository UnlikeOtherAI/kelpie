import { afterEach, describe, expect, it } from "vitest";
import { createServer, type Server } from "node:http";
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { spawn, type ChildProcess } from "node:child_process";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

interface RpcResponse { id?: number; result?: unknown; error?: unknown }

function readLine(child: ChildProcess, id: number): Promise<RpcResponse> {
  return new Promise((resolveResponse, reject) => {
    let buffer = "";
    const timer = setTimeout(() => reject(new Error("Timed out waiting for MCP response")), 10_000);
    child.stdout!.on("data", (chunk: Buffer) => {
      buffer += chunk.toString();
      for (const line of buffer.split("\n")) {
        if (!line.trim()) continue;
        try {
          const response = JSON.parse(line) as RpcResponse;
          if (response.id === id) { clearTimeout(timer); resolveResponse(response); }
        } catch { /* MCP stdout is line-delimited JSON; ignore incomplete data. */ }
      }
      buffer = buffer.includes("\n") ? buffer.slice(buffer.lastIndexOf("\n") + 1) : buffer;
    });
    child.once("error", reject);
  });
}

async function listen(server: Server): Promise<number> {
  await new Promise<void>((resolveListen) => server.listen(0, "127.0.0.1", resolveListen));
  const address = server.address();
  if (!address || typeof address === "string") throw new Error("No TCP address");
  return address.port;
}

describe("Windows local alias MCP stdio", () => {
  const children: ChildProcess[] = [];
  const servers: Server[] = [];
  const roots: string[] = [];
  afterEach(async () => {
    for (const child of children) child.kill();
    await Promise.all(servers.map((server) => new Promise<void>((resolveClose) => server.close(() => resolveClose()))));
    await Promise.all(roots.map((root) => rm(root, { recursive: true, force: true })));
  });

  it("uses the chosen readiness capability without a device argument", async () => {
    const token = "a".repeat(48);
    let authorized = false;
    const server = createServer((request, response) => {
      if (request.headers.authorization !== `Bearer ${token}`) { response.writeHead(401); response.end(JSON.stringify({ success: false })); return; }
      if (request.url !== "/v1/navigate") { response.writeHead(404); response.end(); return; }
      authorized = true;
      let body = "";
      request.on("data", (chunk: Buffer) => { body += chunk.toString(); });
      request.on("end", () => { response.setHeader("content-type", "application/json"); response.end(JSON.stringify({ success: true, url: JSON.parse(body).url })); });
    });
    servers.push(server);
    const port = await listen(server);
    const root = await mkdtemp(join(tmpdir(), "kelpie-mcp-alias-")); roots.push(root);
    const profile = join(root, "profile"); await mkdir(profile);
    await writeFile(join(profile, "readiness.json"), JSON.stringify({ version: 1, launchId: "launch-1", deviceId: "device-1", port, token, controlMode: "loopback", mcp: { http: true, stdio: false, endpoint: "/mcp" } }));
    await writeFile(join(root, "browsers.json"), JSON.stringify({ aliases: { win: { platform: "windows", profileDir: profile } }, running: { win: { port, lastLaunchedAt: new Date().toISOString(), launchId: "launch-1", readinessFile: join(profile, "readiness.json"), deviceId: "device-1" } } }));
    const child = spawn(process.execPath, ["--import", "tsx", resolve("src/index.ts"), "--browser", "win", "mcp"], { cwd: process.cwd(), env: { ...process.env, KELPIE_HOME: root }, stdio: ["pipe", "pipe", "pipe"] });
    children.push(child);
    child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "nessie", version: "test" } } }) + "\n");
    await expect(readLine(child, 1)).resolves.toMatchObject({ id: 1, result: expect.any(Object) });
    child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id: 2, method: "tools/list", params: {} }) + "\n");
    const listed = await readLine(child, 2);
    if (!listed.result || typeof listed.result !== "object" || !("tools" in listed.result) || !Array.isArray(listed.result.tools)) throw new Error("Missing MCP tools list");
    expect(listed.result.tools.map((tool) => tool.name)).toContain("kelpie_navigate");
    expect(listed.result.tools.map((tool) => tool.name)).not.toContain("kelpie_ai_ask");
    child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id: 3, method: "tools/call", params: { name: "kelpie_navigate", arguments: { url: "https://example.test" } } }) + "\n");
    const result = await readLine(child, 3);
    expect(result).toMatchObject({ id: 3, result: expect.any(Object) });
    expect(authorized).toBe(true);
  });
});
