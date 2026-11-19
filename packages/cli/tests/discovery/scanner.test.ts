import { EventEmitter } from "node:events";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { scanForDevices } from "../../src/discovery/scanner.js";

const fixture = vi.hoisted(() => ({ find: vi.fn(), destroy: vi.fn() }));
vi.mock("bonjour-service", () => ({
  default: { Bonjour: class { find = fixture.find; destroy = fixture.destroy; } },
}));

const mdns = new EventEmitter();
const query = vi.fn();
const stop = vi.fn();

beforeEach(() => {
  vi.useFakeTimers();
  vi.clearAllMocks();
  mdns.removeAllListeners();
  fixture.find.mockReturnValue(Object.assign(new EventEmitter(), { stop, mdns: Object.assign(mdns, { query }) }));
});
afterEach(() => { vi.useRealTimers(); });

it("reports a bind error and tears down the browse once", async () => {
  const error = Object.assign(new Error("bind failed"), { code: "EADDRINUSE" });
  const result = expect(scanForDevices(3000)).rejects.toBe(error);
  mdns.emit("error", error);
  await result;
  await vi.runAllTimersAsync();
  expect(stop).toHaveBeenCalledTimes(1);
  expect(fixture.destroy).toHaveBeenCalledTimes(1);
});

it("reports a failed query send instead of returning an empty successful scan", async () => {
  const error = Object.assign(new Error("send failed"), { code: "ENETUNREACH" });
  query.mockImplementation((_, __, callback: (error: Error) => void) => callback(error));
  const result = expect(scanForDevices(1000)).rejects.toBe(error);
  await vi.advanceTimersByTimeAsync(500);
  await result;
  expect(query).toHaveBeenCalledWith("_kelpie._tcp.local", "PTR", expect.any(Function));
});
