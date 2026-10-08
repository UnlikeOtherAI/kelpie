import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { createMcpServer } from "../../src/mcp/server.js";
import { browserTools } from "../../src/mcp/tools.js";
import { ToolInputError, aiAskBody, aiLoadBody, endpointSaveBody } from "../../src/mcp/ai-endpoint-tools.js";
import { addDevice, clearDevices } from "../../src/discovery/registry.js";
import { BrowserMcpTools, BrowserToolUnsupportedPlatforms, httpToMcp } from "../../../shared/src/index.js";
import type { DiscoveredDevice } from "../../src/types.js";

const NEW_TOOLS = [
  "kelpie_ai_endpoints",
  "kelpie_ai_endpoint_save",
  "kelpie_ai_endpoint_remove",
  "kelpie_ai_endpoint_models",
  "kelpie_ai_endpoint_test",
  "kelpie_ai_endpoint_health",
  "kelpie_ai_cancel",
] as const;

const KEY = "sk-mcp-endpoint-key-0987654321";

const tool = (name: string) => {
  const found = browserTools.find((entry) => entry.name === name);
  if (!found) throw new Error(`missing ${name}`);
  return found;
};

describe("AI endpoint MCP tool catalogue", () => {
  it("registers every new tool in the shared catalogue with an HTTP mapping", () => {
    for (const name of NEW_TOOLS) {
      expect(BrowserMcpTools).toContain(name);
      expect(Object.values(httpToMcp)).toContain(name);
      expect(BrowserToolUnsupportedPlatforms[name]).toEqual(["linux", "windows"]);
      expect(tool(name).platforms).toEqual(["ios", "android", "macos"]);
    }
  });

  it("maps tools to the contract's device methods", () => {
    expect(NEW_TOOLS.map((name) => tool(name).method)).toEqual([
      "ai-endpoints", "ai-endpoint-save", "ai-endpoint-remove", "ai-endpoint-models",
      "ai-endpoint-test", "ai-endpoint-health", "ai-cancel",
    ]);
  });

  it("offers no raw API key field anywhere", () => {
    for (const entry of browserTools.filter((candidate) => candidate.method.startsWith("ai-"))) {
      expect(Object.keys(entry.schema)).not.toContain("apiKey");
    }
    expect(Object.keys(tool("kelpie_ai_endpoint_save").schema)).toEqual(expect.arrayContaining(["apiKeyEnv", "clearApiKey", "baseURL", "name"]));
  });

  it("explains localhost, no fallback, text-only and the action scope", () => {
    expect(tool("kelpie_ai_endpoint_save").description).toMatch(/device running Kelpie.*not on the machine running this MCP client/);
    expect(tool("kelpie_ai_load").description).toMatch(/never falls back/);
    expect(tool("kelpie_ai_ask").description).toMatch(/Text-only models never receive screenshots/);
    expect(tool("kelpie_ai_ask").description).toMatch(/allowActions lets the model click, fill, select and check in the pinned tab only/);
  });

  it("extends kelpie_ai_load and kelpie_ai_ask schemas", () => {
    expect(Object.keys(tool("kelpie_ai_load").schema)).toEqual(expect.arrayContaining(["model", "backend", "endpoint"]));
    expect(Object.keys(tool("kelpie_ai_ask").schema)).toEqual(expect.arrayContaining(["agent", "allowActions", "maxSteps"]));
    expect(tool("kelpie_ai_ask").schema.maxSteps.safeParse(41).success).toBe(false);
    expect(tool("kelpie_ai_ask").schema.maxSteps.safeParse(40).success).toBe(true);
  });
});

describe("AI endpoint MCP bodies", () => {
  it("endpoint save normalises the URL and reads apiKeyEnv from the process environment", () => {
    const body = endpointSaveBody(
      { device: "mac", name: "Studio", baseURL: "http://Studio.local:1234/v1/models", apiKeyEnv: "STUDIO_KEY", capabilities: { vision: null } },
      { STUDIO_KEY: KEY },
    );
    expect(body).toEqual({ name: "Studio", baseURL: "http://studio.local:1234/v1", apiKey: KEY, capabilities: { vision: null } });
  });

  it.each([
    [{ name: "S", baseURL: "ftp://h" }, "INVALID_ENDPOINT_URL"],
    [{ name: "S", baseURL: "http://h", apiKeyEnv: "UNSET_FOR_TEST" }, "INVALID_PARAMS"],
    [{ name: "S", baseURL: "http://h", apiKeyEnv: "K", clearApiKey: true }, "INVALID_PARAMS"],
  ])("endpoint save rejects %j with %s", (args, code) => {
    expect(() => endpointSaveBody(args, { K: KEY })).toThrow(expect.objectContaining({ code }) as ToolInputError);
  });

  it("ai load and ai ask validate their new fields", () => {
    expect(aiLoadBody({ device: "d", backend: "openai", endpoint: "Studio" })).toEqual({ backend: "openai", endpoint: "Studio" });
    expect(aiLoadBody({ model: "gemma-4-e2b-q4" })).toEqual({ model: "gemma-4-e2b-q4" });
    expect(() => aiLoadBody({ backend: "openai" })).toThrow(ToolInputError);
    expect(() => aiLoadBody({})).toThrow(ToolInputError);
    expect(aiAskBody({ device: "d", prompt: "p", agent: true, allowActions: true, maxSteps: 4 })).toEqual({ prompt: "p", agent: true, allowActions: true, maxSteps: 4 });
    expect(() => aiAskBody({ agent: false, allowActions: true })).toThrow(ToolInputError);
  });
});

describe("AI endpoint MCP calls over a real server", () => {
  const device: DiscoveredDevice = {
    id: "mcp-endpoint-device", name: "McpMac", ip: "192.168.1.88", port: 8420, platform: "macos",
    model: "Mac", width: 0, height: 0, version: "1", lastSeen: Date.now(),
  };
  const originalFetch = globalThis.fetch;
  let sentBodies: Record<string, unknown>[] = [];

  async function callTool(name: string, args: Record<string, unknown>): Promise<{ text: string; isError: boolean }> {
    const server = createMcpServer();
    const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
    const client = new Client({ name: "test", version: "1" }, { capabilities: {} });
    await Promise.all([server.connect(serverTransport), client.connect(clientTransport)]);
    try {
      const result = await client.callTool({ name, arguments: args });
      const content = result.content as { type: string; text: string }[];
      return { text: content.map((part) => part.text).join("\n"), isError: result.isError === true };
    } finally {
      await Promise.allSettled([client.close(), server.close()]);
    }
  }

  beforeEach(() => {
    sentBodies = [];
    addDevice(device);
    process.env.KELPIE_MCP_TEST_KEY = KEY;
    globalThis.fetch = vi.fn(async (_url: string | URL | Request, init?: RequestInit) => {
      sentBodies.push(JSON.parse(String(init?.body ?? "{}")) as Record<string, unknown>);
      const echo = { success: false, error: { code: "ENDPOINT_ERROR", message: `upstream rejected ${KEY}` }, apiKey: KEY };
      return new Response(JSON.stringify(echo), { status: 502, headers: { "Content-Type": "application/json" } });
    }) as typeof fetch;
  });

  afterEach(() => {
    globalThis.fetch = originalFetch;
    delete process.env.KELPIE_MCP_TEST_KEY;
    clearDevices();
  });

  it("sends the env key to the device but never returns it", async () => {
    const { text } = await callTool("kelpie_ai_endpoint_save", {
      device: device.id, name: "Studio", baseURL: "http://studio.local:1234", apiKeyEnv: "KELPIE_MCP_TEST_KEY",
    });
    expect(sentBodies[0]).toEqual({ name: "Studio", baseURL: "http://studio.local:1234/v1", apiKey: KEY });
    expect(text).not.toContain(KEY);
    expect(text).toContain("[REDACTED]");
  });

  it("returns input errors as tool errors without contacting the device", async () => {
    const result = await callTool("kelpie_ai_endpoint_save", { device: device.id, name: "S", baseURL: "http://u:p@h/v1" });
    expect(result.isError).toBe(true);
    expect(result.text).toContain("INVALID_ENDPOINT_URL");
    expect(sentBodies).toEqual([]);
  });
});
