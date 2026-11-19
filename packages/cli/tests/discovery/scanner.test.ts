import { EventEmitter } from "node:events";
import type { NetworkInterfaceInfoIPv4 } from "node:os";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { scanForDevices } from "../../src/discovery/scanner.js";

const fixture = vi.hoisted(() => ({ connect: vi.fn(), networkInterfaces: vi.fn() }));
vi.mock("bonjour-service", () => ({
  default: { Bonjour: function (options: unknown) { return fixture.connect(options); } },
}));
vi.mock("node:os", () => ({ networkInterfaces: fixture.networkInterfaces }));

const lan = "192.0.2.1";
const virtual = "198.51.100.1";
const interfaceInfo = (address: string): NetworkInterfaceInfoIPv4 => ({
  address, family: "IPv4", netmask: "255.255.255.0", internal: false, mac: "", cidr: null,
});

function listener() {
  const query = vi.fn();
  const mdns = Object.assign(new EventEmitter(), { query });
  const stop = vi.fn();
  const browser = Object.assign(new EventEmitter(), { stop, mdns });
  return { mdns, query, stop, browser, find: vi.fn(() => browser), destroy: vi.fn() };
}

beforeEach(() => {
  vi.useFakeTimers();
  vi.clearAllMocks();
  fixture.networkInterfaces.mockReturnValue({ lan: [interfaceInfo(lan)] });
});
afterEach(() => { vi.useRealTimers(); });

it("reports a bind error and tears down the browse once", async () => {
  const connection = listener();
  const { mdns, stop, destroy } = connection;
  fixture.connect.mockReturnValue(connection);
  const error = Object.assign(new Error("bind failed"), { code: "EADDRINUSE" });
  const result = scanForDevices(3000);
  mdns.emit("error", error);
  expect(await result).toEqual({ devices: [], interfaces: [{ address: lan, error: "EADDRINUSE" }] });
  await vi.runAllTimersAsync();
  expect(stop).toHaveBeenCalledTimes(1);
  expect(destroy).toHaveBeenCalledTimes(1);
});

it("reports a failed query send instead of returning an empty successful scan", async () => {
  const connection = listener();
  fixture.connect.mockReturnValue(connection);
  const error = Object.assign(new Error("send failed"), { code: "ENETUNREACH" });
  connection.query.mockImplementation((_, __, callback: (error: Error) => void) => callback(error));
  const result = scanForDevices(1000);
  await vi.advanceTimersByTimeAsync(500);
  expect(await result).toEqual({ devices: [], interfaces: [{ address: lan, error: "ENETUNREACH" }] });
  expect(connection.query).toHaveBeenCalledWith("_kelpie._tcp.local", "PTR", expect.any(Function));
});

it("browses each IPv4 interface independently and prefers a responding advertised address", async () => {
  fixture.networkInterfaces.mockReturnValue({
    lan: [interfaceInfo(lan)],
    virtual: [interfaceInfo(virtual), { ...interfaceInfo("127.0.0.1"), internal: true }],
  });
  const wired = listener();
  const adapter = listener();
  fixture.connect.mockReturnValueOnce(wired).mockReturnValueOnce(adapter);
  const result = scanForDevices(1000);
  expect(fixture.connect.mock.calls).toEqual([
    [{ interface: lan, bind: "0.0.0.0" }],
    [{ interface: virtual, bind: "0.0.0.0" }],
  ]);
  adapter.mdns.emit("warning", Object.assign(new Error("join failed"), { syscall: "addMembership", code: "ENODEV" }));
  const service = {
    name: "Mac",
    port: 8420,
    addresses: [virtual, "192.0.2.2"],
    referer: { address: "192.0.2.2" },
  };
  wired.browser.emit("up", service);
  wired.browser.emit("txt-update", { ...service, txt: { id: "mac", platform: "macos" } });
  wired.browser.emit("up", { ...service, txt: { id: "mac" } });
  wired.browser.emit("up", { ...service, port: 18476, txt: { id: "mac", platform: "macos" } });
  await vi.advanceTimersByTimeAsync(1000);
  expect(await result).toEqual({
    devices: [8420, 18476].map((port) =>
      expect.objectContaining({ id: "mac", ip: "192.0.2.2", platform: "macos", port })),
    interfaces: [{ address: lan }, { address: virtual, error: "ENODEV" }],
  });
  expect(wired.destroy).toHaveBeenCalledTimes(1);
  expect(adapter.destroy).toHaveBeenCalledTimes(1);
});
