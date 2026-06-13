import { describe, it, expect, beforeEach, afterEach } from "vitest";
import {
  mkdtempSync,
  rmSync,
  statSync,
  writeFileSync,
  symlinkSync,
  mkdirSync,
  unlinkSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  SessionTokenCache,
  TokenStore,
  defaultClientName,
  fingerprintFor,
} from "../../src/auth/token-store.js";

describe("fingerprintFor", () => {
  it("composes deviceId:host:port", () => {
    expect(fingerprintFor("abc", "192.168.1.10", 8420)).toBe("abc:192.168.1.10:8420");
  });
});

describe("defaultClientName", () => {
  it("returns a non-empty user@host string", () => {
    const name = defaultClientName();
    expect(name).toMatch(/^.+@.+$/);
  });
});

describe("SessionTokenCache", () => {
  it("stores and retrieves tokens by fingerprint", () => {
    const cache = new SessionTokenCache();
    cache.set("d1", "192.168.1.5", 8420, "tok-1");
    expect(cache.get("d1", "192.168.1.5", 8420)).toBe("tok-1");
  });

  it("misses on wrong host", () => {
    const cache = new SessionTokenCache();
    cache.set("d1", "192.168.1.5", 8420, "tok-1");
    expect(cache.get("d1", "192.168.1.6", 8420)).toBeUndefined();
  });

  it("removes individual entries", () => {
    const cache = new SessionTokenCache();
    cache.set("d1", "h", 1, "t1");
    cache.set("d2", "h", 1, "t2");
    cache.remove("d1", "h", 1);
    expect(cache.get("d1", "h", 1)).toBeUndefined();
    expect(cache.get("d2", "h", 1)).toBe("t2");
  });
});

describe("TokenStore", () => {
  let dir: string;
  let store: TokenStore;

  beforeEach(() => {
    dir = mkdtempSync(join(tmpdir(), "kelpie-token-store-"));
    store = new TokenStore(dir);
  });

  afterEach(() => {
    rmSync(dir, { recursive: true, force: true });
  });

  it("creates the directory with 0700 perms on first write", async () => {
    rmSync(dir, { recursive: true, force: true });
    await store.set("d1", "h", 1, "tok");
    const mode = statSync(dir).mode & 0o777;
    expect(mode).toBe(0o700);
  });

  it("writes tokens.json with 0600 perms", async () => {
    await store.set("d1", "192.168.1.10", 8420, "tok");
    const mode = statSync(join(dir, "tokens.json")).mode & 0o777;
    expect(mode).toBe(0o600);
  });

  it("persists tokens across instances", async () => {
    await store.set("d1", "h", 1, "tok-1");
    const fresh = new TokenStore(dir);
    expect(await fresh.get("d1", "h", 1)).toBe("tok-1");
  });

  it("generates a stable clientId per directory", async () => {
    const id1 = await store.clientId();
    const id2 = await store.clientId();
    expect(id1).toBe(id2);
    const fresh = new TokenStore(dir);
    expect(await fresh.clientId()).toBe(id1);
  });

  it("removes entries", async () => {
    await store.set("d1", "h", 1, "tok-1");
    await store.set("d2", "h", 1, "tok-2");
    await store.remove("d1", "h", 1);
    expect(await store.get("d1", "h", 1)).toBeUndefined();
    expect(await store.get("d2", "h", 1)).toBe("tok-2");
  });

  it("treats a corrupt store file as empty", async () => {
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, "tokens.json"), "{ not valid json", { mode: 0o600 });
    const fresh = new TokenStore(dir);
    expect(await fresh.get("d1", "h", 1)).toBeUndefined();
  });

  it("refuses to operate on a symlinked directory", async () => {
    const real = mkdtempSync(join(tmpdir(), "kelpie-token-real-"));
    const link = `${dir}-link`;
    symlinkSync(real, link);
    try {
      const linked = new TokenStore(link);
      await expect(linked.set("d1", "h", 1, "tok")).rejects.toThrow(/symlinked/);
    } finally {
      try {
        unlinkSync(link);
      } catch {
        /* ignore */
      }
      rmSync(real, { recursive: true, force: true });
    }
  });
});
