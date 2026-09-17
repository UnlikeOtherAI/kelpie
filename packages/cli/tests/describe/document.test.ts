import { describe, it, expect } from "vitest";
import os from "node:os";
import path from "node:path";

import {
  buildDescribeDocument,
  DESCRIBE_SCHEMA_VERSION,
  DescribeDocumentSchema,
} from "../../src/describe/document.js";
import type { DiscoveredDevice } from "../../src/types.js";

/**
 * `kelpie describe --json` is a stability contract for external integrators —
 * the first being Nessie's executor, which polls it to learn whether Kelpie is
 * here and what is on the network. These tests pin the states an integrator
 * has to tell apart, and the one thing that must never leave the machine.
 */

const device = (over: Partial<DiscoveredDevice> = {}): DiscoveredDevice => ({
  height: 2556,
  id: "kelpie-ios-9f2a",
  ip: "192.168.1.42",
  lastSeen: Date.parse("2026-09-17T09:59:58.000Z"),
  model: "iPhone 17 Pro",
  name: "Ondrej's iPhone",
  platform: "ios",
  port: 51873,
  runtimeMode: "gui",
  version: "0.1.3",
  width: 1179,
  ...over,
});

const catalog = {
  serverVersion: "0.1.0",
  tools: [
    { name: "kelpie_navigate", description: "Go", inputSchema: { type: "object" } },
    { name: "kelpie_screenshot", description: "Shoot", inputSchema: { type: "object" } },
  ],
};

const deps = (over: Partial<Parameters<typeof buildDescribeDocument>[1]> = {}) => ({
  cliPath: "/opt/homebrew/bin/kelpie",
  cliVersion: "0.1.11",
  isPaired: async () => false,
  listTools: async () => catalog,
  now: () => new Date("2026-09-17T10:00:00.000Z"),
  probeLocal: async () => [],
  scan: async () => [],
  ...over,
});

describe("describe document", () => {
  it("states every fact an integrator needs about a found instance", async () => {
    const doc = await buildDescribeDocument({}, deps({ scan: async () => [device()] }));

    expect(doc.schemaVersion).toBe(DESCRIBE_SCHEMA_VERSION);
    expect(doc.cli).toEqual({ path: "/opt/homebrew/bin/kelpie", version: "0.1.11" });
    expect(doc.discovery.deviceCount).toBe(1);
    expect(doc.discovery.devices[0]).toMatchObject({
      address: "192.168.1.42",
      display: { height: 2556, width: 1179 },
      id: "kelpie-ios-9f2a",
      model: "iPhone 17 Pro",
      name: "Ondrej's iPhone",
      platform: "ios",
      // Every instance picks its own port, so it is stated, never assumed.
      port: 51873,
      runtimeMode: "gui",
      version: "0.1.3",
    });
    expect(doc.discovery.devices[0]?.lastSeenAt).toBe("2026-09-17T09:59:58.000Z");
  });

  it("answers with an empty network rather than failing", async () => {
    // "No devices" is an answer, not an error: an integrator polling this on a
    // schedule must be able to tell it apart from a CLI that could not run.
    const doc = await buildDescribeDocument({}, deps());

    expect(doc.discovery.mdns).toBe("ok");
    expect(doc.discovery.deviceCount).toBe(0);
    expect(doc.discovery.devices).toEqual([]);
  });

  it("says mDNS was unavailable rather than reporting an empty network", async () => {
    // It has not found nothing — it has not looked. A reader that cannot tell
    // these apart would tell a person there are no browsers on their network.
    const doc = await buildDescribeDocument({}, deps({
      scan: async () => { throw new Error("no mDNS responder"); },
    }));

    expect(doc.discovery.mdns).toBe("unavailable");
    expect(doc.discovery.devices).toEqual([]);
  });

  it("finds a local instance the mDNS browse missed", async () => {
    // mDNS is racy for a Kelpie on the same host, which is the case the
    // executor cares about most: the Mac it is running on.
    const doc = await buildDescribeDocument({}, deps({
      probeLocal: async () => [device({ id: "local", ip: "127.0.0.1", port: 8420 })],
      scan: async () => [],
    }));

    expect(doc.discovery.deviceCount).toBe(1);
    expect(doc.discovery.devices[0]).toMatchObject({ address: "127.0.0.1", port: 8420 });
  });

  it("counts one instance once when both sources see it", async () => {
    const both = device({ ip: "127.0.0.1", port: 8420 });
    const doc = await buildDescribeDocument({}, deps({
      probeLocal: async () => [both],
      scan: async () => [both],
    }));

    expect(doc.discovery.deviceCount).toBe(1);
  });

  it("reports a paired instance as paired and an unpaired one as unpaired", async () => {
    // Kelpie refuses every automation method until a person pairs on the
    // device, so discovered and drivable are different facts.
    const paired = await buildDescribeDocument({}, deps({
      isPaired: async () => true,
      scan: async () => [device()],
    }));
    const unpaired = await buildDescribeDocument({}, deps({
      isPaired: async () => false,
      scan: async () => [device()],
    }));

    expect(paired.discovery.devices[0]?.paired).toBe(true);
    expect(unpaired.discovery.devices[0]?.paired).toBe(false);
  });

  it("never carries a token, only the boolean pairing fact", async () => {
    // The secret has to be reachable from the building path or this asserts
    // nothing: it rides on the discovered device, which is where a paired
    // instance’s credential would sit if discovery ever carried one. Copying
    // the device through instead of naming its fields turns this red.
    const secret = "kelpie_tok_SUPERSECRETVALUE";
    const carrying = { ...device(), token: secret, secret } as DiscoveredDevice;
    const doc = await buildDescribeDocument({}, deps({
      isPaired: async () => true,
      scan: async () => [carrying],
    }));

    const serialized = JSON.stringify(doc);
    expect(serialized).not.toContain(secret);
    expect(serialized).not.toContain("token");
    expect(doc.discovery.devices[0]?.paired).toBe(true);
  });

  it("redacts the user's home path out of a handshake failure", async () => {
    // The detail string is built from an error whose message embeds a host
    // path; the document travels to another machine, so it must not.
    const home = os.homedir();
    const doc = await buildDescribeDocument({}, deps({
      listTools: async () => {
        throw new Error(`ENOENT: ${path.join(home, "private", "kelpie")} is missing`);
      },
    }));

    expect(doc.mcp.available).toBe(false);
    expect(doc.mcp.reason).toBe("handshake_failed");
    expect(doc.mcp.detail).not.toContain(home);
    expect(doc.mcp.detail).toContain("~");
  });

  it("states the MCP invocations and a catalog digest that moves with the catalog", async () => {
    const doc = await buildDescribeDocument({}, deps());
    expect(doc.mcp.available).toBe(true);
    expect(doc.mcp.stdio).toEqual({ args: ["mcp"], command: "kelpie" });
    expect(doc.tools?.count).toBe(2);
    expect(doc.tools?.digest).toMatch(/^sha256:[0-9a-f]{64}$/);
    // Not shipped by default: 145 schemas is not something a poller should
    // carry on every call.
    expect(doc.tools?.catalog).toBeUndefined();

    const changed = await buildDescribeDocument({}, deps({
      listTools: async () => ({
        ...catalog,
        tools: [...catalog.tools, { name: "kelpie_new", inputSchema: { type: "object" } }],
      }),
    }));
    expect(changed.tools?.digest).not.toBe(doc.tools?.digest);
  });

  it("includes the catalog only when asked", async () => {
    const doc = await buildDescribeDocument({ includeTools: true }, deps());
    expect(doc.tools?.catalog).toHaveLength(2);
  });

  it("honours the scan budget it was given and states it", async () => {
    let asked = 0;
    const doc = await buildDescribeDocument({ scanTimeoutMs: 8000 }, deps({
      scan: async (ms: number) => { asked = ms; return []; },
    }));

    expect(asked).toBe(8000);
    expect(doc.discovery.scanTimeoutMs).toBe(8000);
  });

  it("emits a document that satisfies its own published grammar", async () => {
    const doc = await buildDescribeDocument({}, deps({ scan: async () => [device()] }));
    expect(() => DescribeDocumentSchema.parse(doc)).not.toThrow();
  });
});
