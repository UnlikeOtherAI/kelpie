import { describe, it, expect, vi, beforeEach } from "vitest";

vi.mock("../../src/discovery/local-probe.js", () => ({
  probeHealth: vi.fn(),
}));

import { probeHealth } from "../../src/discovery/local-probe.js";
import { waitForBoundPort, reachablePorts } from "../../src/commands/browser.js";

const mockProbe = vi.mocked(probeHealth);

/** Make exactly the given ports respond to /health. */
function reachable(...ports: number[]): void {
  mockProbe.mockImplementation(async (port: number) => ports.includes(port));
}

describe("reachablePorts", () => {
  beforeEach(() => mockProbe.mockReset());

  it("returns only the reachable ports", async () => {
    reachable(8420, 8422);
    const set = await reachablePorts([8420, 8421, 8422]);
    expect([...set].sort((a, b) => a - b)).toEqual([8420, 8422]);
  });
});

describe("waitForBoundPort", () => {
  beforeEach(() => mockProbe.mockReset());

  it("records the requested port when nothing held it before launch", async () => {
    reachable(8420);
    expect(await waitForBoundPort(8420, new Set())).toBe(8420);
  });

  it("records the fallback port when a stale instance held the requested port", async () => {
    // Both up after launch, but 8420 was already reachable pre-launch.
    reachable(8420, 8421);
    expect(await waitForBoundPort(8420, new Set([8420]))).toBe(8421);
  });

  it("does not mistake a recovered stale instance on the requested port for the new one", async () => {
    // 8420 (stale) correctly captured pre-launch; new instance bound 8421.
    reachable(8420, 8421);
    expect(await waitForBoundPort(8420, new Set([8420]))).not.toBe(8420);
  });

  it("returns undefined when no new instance binds before the deadline", async () => {
    reachable(8420); // only the pre-existing instance stays up
    let calls = 0;
    const clock = (): number => (calls++ === 0 ? 0 : 999_999);
    expect(await waitForBoundPort(8420, new Set([8420]), clock)).toBeUndefined();
  });
});
