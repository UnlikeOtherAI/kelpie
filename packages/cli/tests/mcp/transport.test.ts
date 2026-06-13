import { describe, it, expect } from "vitest";
import { startHttp } from "../../src/mcp/transport.js";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";

// Minimal stub — startHttp must reject *before* connecting the server for the
// safety check to be meaningful.
const stubServer = { connect: async () => undefined } as unknown as McpServer;

describe("MCP HTTP transport binding policy", () => {
  it("refuses non-loopback bind without --unsafe-host", async () => {
    await expect(startHttp(stubServer, 0, { bindHost: "0.0.0.0" })).rejects.toThrow(
      /Refusing to bind/,
    );
  });

  it("refuses link-local non-loopback bind without --unsafe-host", async () => {
    await expect(startHttp(stubServer, 0, { bindHost: "192.168.1.10" })).rejects.toThrow(
      /Refusing to bind/,
    );
  });
});
