import { describe, expect, it, vi } from "vitest";
import { createCleanupOwner } from "../src/browser-control/cleanup.js";

describe("retained cleanup ownership", () => {
  it("automatically retries a failed release without dropping its resource", async () => {
    vi.useFakeTimers();
    try {
      const owner = createCleanupOwner();
      const close = vi.fn<() => Promise<void>>().mockRejectedValueOnce(new Error("temporary")).mockResolvedValue(undefined);
      await expect(owner.close("resource", close)).rejects.toMatchObject({ code: "CLEANUP_PENDING" });
      expect(owner.pending()).toBe(1);
      await vi.advanceTimersByTimeAsync(1001);
      expect(close).toHaveBeenCalledTimes(2);
      expect(owner.pending()).toBe(0);
    } finally { vi.useRealTimers(); }
  });

  it("deduplicates concurrent cleanup and supports explicit drain without hiding failures", async () => {
    vi.useFakeTimers();
    try {
      const owner = createCleanupOwner();
      const close = vi.fn<() => Promise<void>>().mockRejectedValueOnce(new Error("temporary")).mockResolvedValue(undefined);
      const first = owner.close("resource", close);
      const duplicate = owner.close("resource", close);
      await expect(first).rejects.toMatchObject({ code: "CLEANUP_PENDING" });
      await expect(duplicate).rejects.toMatchObject({ code: "CLEANUP_PENDING" });
      expect(close).toHaveBeenCalledOnce();
      await owner.drain();
      expect(close).toHaveBeenCalledTimes(2);
      expect(owner.pending()).toBe(0);
      await vi.advanceTimersByTimeAsync(1001);
      expect(close).toHaveBeenCalledTimes(2);
    } finally { vi.useRealTimers(); }
  });
});
