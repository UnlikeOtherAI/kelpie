import { describe, expect, it } from "vitest";
import { workerConfigSchema, workerEndpoint } from "../../src/worker/config.js";

const config = { version: 1, backend: "playwright", endpointEnv: "KELPIE_WORKER_ENDPOINT",
  allowedOrigins: ["https://fixture.example"], networkBoundary: "operator-enforced" };
describe("operator worker grants", () => {
  it("defaults to no WebMCP grant and rejects model-owned configuration fields", () => {
    expect(workerConfigSchema.parse(config).webMcpOrigins).toEqual([]);
    for (const extra of [{ owner: "someone" }, { endpoint: "ws://foreign" }, { allowActions: true }]) {
      expect(workerConfigSchema.safeParse({ ...config, ...extra }).success).toBe(false);
    }
  });

  it("requires exact origin subset and an audited encoding for enabled site tools", () => {
    const grant = { ...config, webMcpOrigins: ["https://fixture.example"], webMcpInputEncoding: "json-string" };
    expect(workerConfigSchema.safeParse(grant).success).toBe(true);
    for (const changes of [
      { webMcpOrigins: ["https://foreign.example"] }, { webMcpOrigins: ["https://fixture.example/path"] },
      { webMcpInputEncoding: undefined }, { webMcpInputEncoding: "guess" }, { backend: "lightpanda" },
    ]) expect(workerConfigSchema.safeParse({ ...grant, ...changes }).success).toBe(false);
  });

  it("keeps Lightpanda readers operator-selected and rejects visual/input capabilities", () => {
    const profile = { ...config, backend: "lightpanda" };
    expect(workerConfigSchema.parse(profile).verifiedLightpandaMethods).toEqual([]);
    const readers = ["tab.snapshot", "tab.extract", "tab.status", "tab.ready"];
    expect(workerConfigSchema.parse({ ...profile, verifiedLightpandaMethods: readers }).verifiedLightpandaMethods).toEqual(readers);
    for (const method of ["tab.screenshot", "tab.click", "page.scroll", "tab.webmcp.discover"]) {
      expect(workerConfigSchema.safeParse({ ...profile, verifiedLightpandaMethods: [method] }).success).toBe(false);
    }
  });

  it("resolves endpoint only from operator environment and keeps credential errors generic", () => {
    const parsed = workerConfigSchema.parse(config);
    expect(workerEndpoint(parsed, { KELPIE_WORKER_ENDPOINT: "wss://worker.example/cdp?token=synthetic" })).toBe("wss://worker.example/cdp?token=synthetic");
    for (const endpoint of ["file:///private", "ws://user:SECRET@worker.example/", "https://worker.example/#secret"]) {
      const error = (() => { try { workerEndpoint(parsed, { KELPIE_WORKER_ENDPOINT: endpoint }); } catch (value) { return value; } })();
      expect(String(error)).not.toContain("SECRET");
      expect(String(error)).toContain("invalid");
    }
  });
});
