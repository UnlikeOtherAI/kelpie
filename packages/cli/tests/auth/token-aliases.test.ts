import { describe, it, expect } from "vitest";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { SessionTokenCache, TokenStore } from "../../src/auth/token-store.js";

const host = "192.168.1.229";
const port = 8420;
const direct = `direct:${host}:${port}`;

for (const kind of ["persistent", "session"] as const) {
  describe(`${kind} token aliases`, () => {
    async function withStore(run: (store: TokenStore | SessionTokenCache) => Promise<void>) {
      const dir = await mkdtemp(join(tmpdir(), "kelpie-alias-test-"));
      try { await run(kind === "persistent" ? new TokenStore(dir) : new SessionTokenCache()); }
      finally { await rm(dir, { recursive: true, force: true }); }
    }

    it("reuses a direct approval under a discovered ID at the identical socket", async () => {
      await withStore(async (store) => {
        await store.set(direct, host, port, "approved");
        expect(await store.get("native", host, port)).toBe("approved");
        expect(await store.get("native", "127.0.0.1", port)).toBeUndefined();
        expect(await store.get("native", host, port + 1)).toBeUndefined();
      });
    });

    it("reuses a discovered approval for direct queries but keeps distinct native IDs isolated", async () => {
      await withStore(async (store) => {
        await store.set("native", host, port, "approved");
        expect(await store.get(direct, host, port)).toBe("approved");
        expect(await store.get("other-native", host, port)).toBeUndefined();
      });
    });

    it("refuses ambiguous token values and accepts duplicate aliases of one token", async () => {
      await withStore(async (store) => {
        await store.set("native", host, port, "one");
        await store.set("other-native", host, port, "two");
        expect(await store.get(direct, host, port)).toBeUndefined();
        await store.set("other-native", host, port, "one");
        expect(await store.get(direct, host, port)).toBe("one");
      });
    });

    it("removes only aliases of the rejected token at its pinned socket", async () => {
      await withStore(async (store) => {
        await store.set(direct, host, port, "old");
        await store.set("native", host, port, "old");
        await store.set("other-native", host, port, "new");
        await store.set("native", host, port + 1, "old");
        await store.remove("native", host, port, "old");
        expect(await store.get("native", host, port)).toBeUndefined();
        expect(await store.get(direct, host, port)).toBe("new");
        expect(await store.get("native", host, port + 1)).toBe("old");
      });
    });
  });
}
