import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import type { DiscoveredDevice } from "../../src/types.js";

const { sendCommand } = vi.hoisted(() => ({ sendCommand: vi.fn() }));
vi.mock("../../src/client/http-client.js", () => ({ sendCommand }));

const { createMcpServer } = await import("../../src/mcp/server.js");
const { browserTools, requestTimeoutMs } = await import("../../src/mcp/tools.js");

const pinned: DiscoveredDevice = {
  id: "device-1",
  name: "probe",
  ip: "127.0.0.1",
  port: 8420,
  platform: "windows",
  model: "Kelpie windows",
  width: 0,
  height: 0,
  version: "0.1.1",
  lastSeen: Date.now(),
};

describe("MCP request timeouts", () => {
  let client: Client;

  beforeEach(async () => {
    sendCommand.mockReset();
    sendCommand.mockResolvedValue({ ok: true, status: 200, data: { success: true } });
    const server = createMcpServer(pinned);
    const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
    client = new Client({ name: "timeout-test", version: "1" });
    await Promise.all([server.connect(serverTransport), client.connect(clientTransport)]);
  });

  afterEach(async () => {
    await client.close();
  });

  it("waits for the tool's own timeout plus a margin", async () => {
    await client.callTool({ name: "kelpie_wait_for_element", arguments: { selector: "#late", timeout: 20_000 } });
    expect(sendCommand).toHaveBeenCalledWith(pinned, "waitForElement", { selector: "#late", timeout: 20_000 }, 25_000);
  });

  it("waits for the device default plus a margin when the timeout is omitted", async () => {
    await client.callTool({ name: "kelpie_wait_for_navigation", arguments: {} });
    expect(sendCommand).toHaveBeenCalledWith(pinned, "waitForNavigation", {}, 15_000);
  });

  it("keeps the CLI default for a tool that takes no timeout", async () => {
    await client.callTool({ name: "kelpie_navigate", arguments: { url: "https://example.test" } });
    expect(sendCommand).toHaveBeenCalledWith(pinned, "navigate", { url: "https://example.test" }, 10_000);
  });

  it("rejects a timeout above the 30 s maximum before calling the device", async () => {
    // The SDK answers a schema violation with an error result (or rejects, in
    // older versions); either way the device must never see the call.
    const rejected = await client
      .callTool({ name: "kelpie_wait_for_element", arguments: { selector: "#x", timeout: 30_001 } })
      .then((result) => result.isError === true, () => true);
    expect(rejected).toBe(true);
    expect(sendCommand).not.toHaveBeenCalled();
  });
});

describe("requestTimeoutMs", () => {
  it("applies to every tool that declares a timeout, and only those", () => {
    const withTimeout = browserTools.filter((tool) => "timeout" in tool.schema).map((tool) => tool.name);
    expect(withTimeout).toEqual(["kelpie_click", "kelpie_fill", "kelpie_wait_for_element", "kelpie_wait_for_navigation"]);
    for (const tool of browserTools) {
      const expected = "timeout" in tool.schema ? 35_000 : 10_000;
      expect(requestTimeoutMs(tool, { timeout: 30_000 })).toBe(expected);
    }
  });

  it("bounds a timeout that bypassed the schema", () => {
    const click = browserTools.find((tool) => tool.name === "kelpie_click")!;
    expect(requestTimeoutMs(click, { timeout: 90_000 })).toBe(35_000);
  });
});
