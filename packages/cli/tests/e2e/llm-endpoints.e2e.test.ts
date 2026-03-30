import { describe, it, expect, beforeAll, beforeEach } from "vitest";
import { testDevice, isDeviceReachable, deviceRequest } from "./setup.js";

describe("E2E: LLM-Optimized Endpoints", () => {
  const device = testDevice();
  let reachable = false;

  beforeAll(async () => {
    reachable = await isDeviceReachable(device);
  });

  beforeEach(async () => {
    if (!reachable) return;
    await deviceRequest(device, "navigate", { url: "https://example.com", timeout: 10000 });
  });

  it("get-accessibility-tree returns semantic tree", async () => {
    if (!reachable) return;
    const { ok, data } = await deviceRequest(device, "get-accessibility-tree", {
      root: "body",
      maxDepth: 3,
    });
    expect(ok).toBe(true);
    expect(data).toHaveProperty("success", true);
    expect(data).toHaveProperty("tree");
    expect(data).toHaveProperty("nodeCount");
    const tree = data.tree as Record<string, unknown>;
    expect(tree).toHaveProperty("role");
  });

  it("get-visible-elements returns viewport elements", async () => {
    if (!reachable) return;
    const { ok, data } = await deviceRequest(device, "get-visible-elements");
    expect(ok).toBe(true);
    expect(data).toHaveProperty("success", true);
    expect(data).toHaveProperty("viewport");
    expect(data).toHaveProperty("elements");
    expect(data).toHaveProperty("count");
    expect(typeof data.count).toBe("number");
  });

  it("get-page-text extracts readable text", async () => {
    if (!reachable) return;
    const { ok, data } = await deviceRequest(device, "get-page-text");
    expect(ok).toBe(true);
    expect(data).toHaveProperty("success", true);
    expect(data).toHaveProperty("title");
    expect(data).toHaveProperty("content");
    expect(data).toHaveProperty("wordCount");
    expect(String(data.content)).toContain("Example Domain");
  });

  it("get-form-state returns form info (empty on example.com)", async () => {
    if (!reachable) return;
    const { ok, data } = await deviceRequest(device, "get-form-state");
    expect(ok).toBe(true);
    expect(data).toHaveProperty("success", true);
    expect(data).toHaveProperty("formCount");
  });

  it("find-element locates element by text", async () => {
    if (!reachable) return;
    const { data } = await deviceRequest(device, "find-element", { text: "Example" });
    expect(data).toHaveProperty("found", true);
    expect(data).toHaveProperty("element");
  });

  it("find-element returns not found for missing text", async () => {
    if (!reachable) return;
    const { data } = await deviceRequest(device, "find-element", { text: "zzz_nonexistent_text_zzz" });
    expect(data).toHaveProperty("found", false);
  });

  it("find-link locates a link by text", async () => {
    if (!reachable) return;
    const { data } = await deviceRequest(device, "find-link", { text: "More information" });
    expect(data).toHaveProperty("found", true);
    const el = data.element as Record<string, unknown>;
    expect(el).toHaveProperty("tag", "a");
  });

  it("find-input returns not found on page without inputs", async () => {
    if (!reachable) return;
    const { data } = await deviceRequest(device, "find-input", { label: "email" });
    expect(data).toHaveProperty("found", false);
  });

  it("get-shadow-roots lists shadow hosts", async () => {
    if (!reachable) return;
    const { ok, data } = await deviceRequest(device, "get-shadow-roots");
    expect(ok).toBe(true);
    expect(data).toHaveProperty("hosts");
    expect(data).toHaveProperty("count");
  });
});
