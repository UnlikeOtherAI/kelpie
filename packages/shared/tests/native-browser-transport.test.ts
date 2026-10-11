import { describe, expect, it, vi } from "vitest";
import { createNativeBrowserTransport } from "../src/browser-control/native.js";

describe("canonical native wire transport", () => {
  it("validates before sending, preserves native refusals and never retries unknown mutations", async () => {
    const send = vi.fn().mockRejectedValue(new Error("SECRET script token"));
    const transport = createNativeBrowserTransport(send);
    expect(await transport.call({ version: 2, method: "tabs.list" } as never)).toMatchObject({ error: { code: "INVALID_ARGUMENTS", mayHaveCompleted: false } });
    expect(send).not.toHaveBeenCalled();
    const result = await transport.call({ version: 1, method: "tab.goto", tabId: "a", params: { url: "https://example.org" } });
    expect(result).toMatchObject({ error: { mayHaveCompleted: true } });
    expect(JSON.stringify(result)).not.toContain("SECRET");
    expect(send).toHaveBeenCalledTimes(1);
    send.mockResolvedValueOnce({ version: 1, ok: false, error: { code: "STALE_REFERENCE", message: "Observe again", mayHaveCompleted: false } });
    expect(await transport.call({ version: 1, method: "tab.click", tabId: "a", params: { ref: "e1" } })).toMatchObject({ error: { code: "STALE_REFERENCE", mayHaveCompleted: false } });
  });
  it("preserves uncertainty for lost tab-targeted reads that may select a renderer", async () => {
    const transport = createNativeBrowserTransport(async () => { throw new Error("Lost reply after selected-tab switch"); });
    expect(await transport.call({ version: 1, method: "tab.snapshot", tabId: "b" })).toMatchObject({ error: { mayHaveCompleted: true } });
  });
  it("serializes the complete native transaction", async () => {
    let release!: () => void;
    const pending = new Promise<void>((resolve) => { release = resolve; });
    const send = vi.fn().mockImplementationOnce(async () => { await pending; return { version: 1, ok: true, value: [] }; }).mockResolvedValue({ version: 1, ok: true, value: [] });
    const transport = createNativeBrowserTransport(send);
    const first = transport.call({ version: 1, method: "tabs.list" });
    const second = transport.call({ version: 1, method: "tabs.list" });
    await Promise.resolve();
    expect(send).toHaveBeenCalledTimes(1);
    release();
    await Promise.all([first, second]);
    expect(send).toHaveBeenCalledTimes(2);
  });
});
