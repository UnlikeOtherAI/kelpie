import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { clearDevices } from "../../src/discovery/registry.js";
import { scanForDevices } from "../../src/discovery/scanner.js";
import { probeLocalDevices } from "../../src/discovery/local-probe.js";
import { sendCommand } from "../../src/client/http-client.js";
import { createMcpServer } from "../../src/mcp/server.js";
import type { DiscoveredDevice } from "../../src/types.js";

vi.mock("../../src/discovery/scanner.js", () => ({ scanForDevices: vi.fn() }));
vi.mock("../../src/discovery/local-probe.js", () => ({ probeLocalDevices: vi.fn() }));
vi.mock("../../src/client/http-client.js", () => ({ sendCommand: vi.fn() }));

const local: DiscoveredDevice = {
  id: "local", name: "Local fixture", ip: "127.0.0.1", port: 18429,
  platform: "macos", model: "Fixture", width: 0, height: 0, version: "test", lastSeen: 0,
};
let server: ReturnType<typeof createMcpServer>;
let client: Client;

beforeEach(async () => {
  vi.resetAllMocks();
  clearDevices();
  vi.mocked(scanForDevices).mockResolvedValue([]);
  vi.mocked(probeLocalDevices).mockResolvedValue([]);
  vi.mocked(sendCommand).mockResolvedValue({ ok: false, status: 401, data: { success: false } });
  local.lastSeen = Date.now();
  server = createMcpServer();
  client = new Client({ name: "test", version: "1" });
  const [caller, listener] = InMemoryTransport.createLinkedPair();
  await server.connect(listener);
  await client.connect(caller);
});

afterEach(async () => {
  await client.close();
  await server.close();
});

async function call(name: string, args: Record<string, unknown> = {}) {
  const response = await client.callTool({ name, arguments: args });
  const content = response.content as { type: string; text: string }[];
  return { isError: response.isError, text: content[0].text };
}
const canonical = (method: string, device?: string, params = {}) =>
  call("kelpie_browser_control", { device, request: { version: 1, method, params } });

it("answers documentation and local capabilities without discovery and forwards targeted capabilities", async () => {
  expect(JSON.parse((await canonical("documentation")).text)).toMatchObject({ ok: true, value: expect.stringContaining("Browser control v1") });
  expect(JSON.parse((await canonical("capabilities")).text)).toMatchObject({ ok: true, value: { methods: ["documentation", "capabilities"], extensions: [] } });
  expect(JSON.parse((await canonical("documentation", undefined, { unknown: true })).text)).toMatchObject({ ok: false, error: { code: "INVALID_ARGUMENTS" } });
  expect(scanForDevices).not.toHaveBeenCalled();
  expect(sendCommand).not.toHaveBeenCalled();

  vi.mocked(sendCommand).mockResolvedValue({
    ok: true, status: 200, data: { version: 1, ok: true, value: { version: 1, methods: ["tabs.list"], extensions: ["fixture"] } },
  });
  expect(JSON.parse((await canonical("capabilities", "127.0.0.1:18429")).text)).toMatchObject({ ok: true, value: { methods: ["tabs.list"] } });
  expect(sendCommand).toHaveBeenCalledWith(expect.objectContaining({ ip: "127.0.0.1", port: 18429 }), "browserControl", expect.anything(), expect.anything(), expect.anything());
  expect(scanForDevices).not.toHaveBeenCalled();
});

it("provides empty-list guidance, scan diagnostics, and a loopback fallback without pairing", async () => {
  expect(JSON.parse((await call("kelpie_list_devices")).text)).toMatchObject({ count: 0, hint: expect.stringContaining("kelpie_discover") });
  const missing = await canonical("tabs.list");
  expect(missing).toMatchObject({ isError: true, text: expect.stringContaining("host:port") });
  expect(sendCommand).not.toHaveBeenCalled();

  expect(JSON.parse((await call("kelpie_discover", { timeout: 600 })).text)).toMatchObject({
    count: 0, discovery: { mdns: "ok", serviceType: "_kelpie._tcp", timeoutMs: 600 }, hint: expect.stringContaining("No usable replies"),
  });
  vi.mocked(scanForDevices).mockRejectedValue(Object.assign(new Error("bind failed"), { code: "EADDRINUSE" }));
  vi.mocked(probeLocalDevices).mockResolvedValue([local]);
  expect(JSON.parse((await call("kelpie_discover")).text)).toMatchObject({
    count: 1, discovery: { mdns: "unavailable" }, hint: expect.stringContaining("EADDRINUSE"),
  });
  expect(sendCommand).toHaveBeenCalledWith(local, "getCapabilities", undefined, 1500, { autoPair: false });
  expect(JSON.parse((await call("kelpie_list_devices")).text)).toMatchObject({ count: 1, devices: [{ id: local.id }] });
});
