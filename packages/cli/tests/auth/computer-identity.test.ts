import { createPublicKey, verify } from "node:crypto";
import { promises as fs } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";
import { computerIdentity } from "../../src/auth/computer-identity.js";
import { pair } from "../../src/auth/pairing.js";

const directories: string[] = [];
afterEach(async () => {
  vi.unstubAllGlobals();
  await Promise.all(directories.splice(0).map((dir) => fs.rm(dir, { recursive: true, force: true })));
});

async function directory() {
  const dir = await fs.mkdtemp(join(tmpdir(), "kelpie-computer-test-"));
  directories.push(dir);
  return dir;
}

describe("computer identity", () => {
  it("shares one complete key across concurrent writers and subsequent loads", async () => {
    const dir = await directory();
    const identities = await Promise.all(Array.from({ length: 16 }, () => computerIdentity(dir)));
    const restarted = await computerIdentity(dir);
    expect(new Set(identities.map((identity) => identity.publicKey))).toEqual(new Set([restarted.publicKey]));
    const publicKey = createPublicKey({ format: "jwk", key: {
      kty: "OKP", crv: "Ed25519", x: Buffer.from(restarted.publicKey, "hex").toString("base64url"),
    } });
    const signature = Buffer.from(restarted.signChallenge("fresh-server-challenge"), "hex");
    expect(verify(null, Buffer.from(`kelpie-computer-pair-v1\nfresh-server-challenge\n${restarted.publicKey}`), publicKey, signature)).toBe(true);
    expect(verify(null, Buffer.from(`kelpie-computer-pair-v1\ndifferent-challenge\n${restarted.publicKey}`), publicKey, signature)).toBe(false);
    if (process.platform !== "win32") expect((await fs.stat(join(dir, "computer-key.pem"))).mode & 0o777).toBe(0o600);
  });

  it("does not silently replace a corrupt existing key and lose all approvals", async () => {
    const dir = await directory();
    await fs.writeFile(join(dir, "computer-key.pem"), "corrupt");
    await expect(computerIdentity(dir)).rejects.toThrow();
    expect(await fs.readFile(join(dir, "computer-key.pem"), "utf8")).toBe("corrupt");
  });

  it("reuses its signature identity when the browser IP, port, and client ID change", async () => {
    const dir = await directory();
    const identity = await computerIdentity(dir);
    const requests: { computerPublicKey: string; computerSignature?: string; requestId?: string }[] = [];
    const prompt = vi.fn();
    vi.stubGlobal("fetch", vi.fn(async (url: string, init: RequestInit) => {
      if (url.includes("/pair/status")) return Response.json({ status: "approved", scope: "persistent", token: "fixture-token" });
      const body = JSON.parse(init.body as string);
      requests.push(body);
      if (!body.requestId) return Response.json({ status: "computer_challenge", requestId: "challenge", expiresAt: Date.now() + 10000 }, { status: 202 });
      expect(body.computerSignature).toBe(identity.signChallenge("challenge"));
      return Response.json({ status: "pending", requestId: "challenge", approvalRequired: false }, { status: 202 });
    }));
    for (const [host, port, clientId] of [["192.0.2.1", 8420, "a"], ["203.0.113.5", 9210, "b"]] as const) {
      expect((await pair({ host, port, clientId, clientName: "Computer", computerIdentity: () => computerIdentity(dir), onApprovalRequired: prompt })).status).toBe("approved");
    }
    expect(new Set(requests.map((request) => request.computerPublicKey))).toEqual(new Set([identity.publicKey]));
    expect(prompt).not.toHaveBeenCalled();
  });
});
