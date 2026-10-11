import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { Command } from "commander";
import { registerMcp } from "../../src/commands/mcp.js";

const mocks = vi.hoisted(() => ({
  getDevice: vi.fn(), localBrowserDevice: vi.fn(), createMcpServer: vi.fn(), startStdio: vi.fn(),
}));
vi.mock("../../src/discovery/registry.js", () => ({ getDevice: mocks.getDevice }));
vi.mock("../../src/commands/helpers.js", async (original) => ({
  ...await original<object>(), localBrowserDevice: mocks.localBrowserDevice,
}));
vi.mock("../../src/mcp/server.js", () => ({ createMcpServer: mocks.createMcpServer }));
vi.mock("../../src/mcp/transport.js", () => ({ DEFAULT_MCP_BIND_HOST: "127.0.0.1", startStdio: mocks.startStdio }));

function command(): Command {
  const program = new Command().option("--device <device>").option("--browser <browser>")
    .option("--port <port>", "Device port", "8420").option("--format <format>", "Output", "json");
  registerMcp(program);
  return program;
}

beforeEach(() => { vi.clearAllMocks(); });
afterEach(() => { process.exitCode = 0; vi.restoreAllMocks(); });

it("pins the explicit device and port through the ordinary pairing resolver", async () => {
  const target = { id: "paired", platform: "macos", ip: "192.168.1.229", port: 8430 };
  mocks.getDevice.mockResolvedValue(target);
  await command().parseAsync(["--device", "192.168.1.229", "--port", "8430", "mcp"], { from: "user" });
  expect(mocks.getDevice).toHaveBeenCalledWith("192.168.1.229", { port: 8430 });
  expect(mocks.createMcpServer).toHaveBeenCalledWith(target, undefined);
  expect(mocks.startStdio).toHaveBeenCalledTimes(1);
});

it("refuses an unresolved explicit target without starting an unpinned server", async () => {
  mocks.getDevice.mockResolvedValue(undefined);
  vi.spyOn(process.stdout, "write").mockImplementation(() => true);
  await command().parseAsync(["--device", "missing", "mcp"], { from: "user" });
  expect(process.exitCode).toBe(4);
  expect(mocks.createMcpServer).not.toHaveBeenCalled();
  expect(mocks.startStdio).not.toHaveBeenCalled();
});

it("keeps local browser precedence and leaves unspecified MCP targets unpinned", async () => {
  const local = { id: "local", platform: "macos" };
  mocks.localBrowserDevice.mockResolvedValue(local);
  await command().parseAsync(["--browser", "local", "--device", "ignored", "mcp"], { from: "user" });
  expect(mocks.getDevice).not.toHaveBeenCalled();
  expect(mocks.createMcpServer).toHaveBeenLastCalledWith(local, undefined);
  await command().parseAsync(["mcp"], { from: "user" });
  expect(mocks.createMcpServer).toHaveBeenLastCalledWith(undefined, undefined);
});
