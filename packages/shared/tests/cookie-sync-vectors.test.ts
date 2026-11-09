import { createCipheriv, createDecipheriv, createECDH, createHash, hkdfSync } from "node:crypto";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

// The cookie sync handshake vectors are the cross-platform crypto contract.
// This test re-derives every value with Node's crypto so a hand-edited or
// mis-generated vector file cannot become the reference that Swift, Kotlin,
// Windows CNG and OpenSSL are checked against.

interface Side {
  privateKey: string;
  key: string;
  replica: string;
  nonce: string;
}

interface SealedMessage {
  direction: "req" | "res";
  seq: number;
  plaintext: string;
  nonce: string;
  aad: string;
  box: string;
}

interface Vectors {
  initiator: Side;
  responder: Side;
  challenge: string;
  sharedSecret: string;
  i2r: string;
  r2i: string;
  sessionId: string;
  messages: SealedMessage[];
}

const vectorsPath = fileURLToPath(
  new URL("../../../core/native/core-sync/tests/vectors/handshake-v1.json", import.meta.url),
);
const vectors = JSON.parse(readFileSync(vectorsPath, "utf8")) as Vectors;
const bytes = (value: string): Buffer => Buffer.from(value, "base64url");

function transcript(initiator: Side, responder: Side): Buffer {
  const parts = [initiator.replica, initiator.key, initiator.nonce, responder.replica, responder.key, responder.nonce];
  const hash = createHash("sha256").update("kelpie-sync-v1");
  for (const part of parts) hash.update(Buffer.from([0])).update(part, "utf8");
  return hash.digest();
}

function agree(own: Side, peer: Side): Buffer {
  const ecdh = createECDH("prime256v1");
  ecdh.setPrivateKey(bytes(own.privateKey));
  expect(ecdh.getPublicKey(null, "uncompressed").toString("base64url")).toBe(own.key);
  return ecdh.computeSecret(bytes(peer.key));
}

describe("cookie sync handshake vectors", () => {
  const t = transcript(vectors.initiator, vectors.responder);

  it("derives the UOA challenge from the transcript", () => {
    expect(t.toString("base64url")).toBe(vectors.challenge);
    expect(vectors.challenge).toMatch(/^[A-Za-z0-9_-]{43}$/);
  });

  it("agrees on one shared secret from either side", () => {
    expect(agree(vectors.initiator, vectors.responder).toString("base64url")).toBe(vectors.sharedSecret);
    expect(agree(vectors.responder, vectors.initiator).toString("base64url")).toBe(vectors.sharedSecret);
  });

  it("derives direction keys with HKDF-SHA256 salted by the transcript", () => {
    const secret = bytes(vectors.sharedSecret);
    const derive = (info: string) => Buffer.from(hkdfSync("sha256", secret, t, info, 32)).toString("base64url");
    expect(derive("kelpie-sync-v1 i2r")).toBe(vectors.i2r);
    expect(derive("kelpie-sync-v1 r2i")).toBe(vectors.r2i);
    expect(vectors.i2r).not.toBe(vectors.r2i);
  });

  it("seals and opens every message with AES-256-GCM", () => {
    for (const message of vectors.messages) {
      const key = bytes(message.direction === "req" ? vectors.i2r : vectors.r2i);
      const nonce = Buffer.alloc(12);
      nonce.writeBigUInt64BE(BigInt(message.seq), 4);
      const aad = Buffer.from(`kelpie-sync-v1\0${vectors.sessionId}\0${message.direction}\0${message.seq}`, "utf8");
      expect(nonce.toString("base64url")).toBe(message.nonce);
      expect(aad.toString("base64url")).toBe(message.aad);

      const cipher = createCipheriv("aes-256-gcm", key, nonce).setAAD(aad);
      const sealed = Buffer.concat([cipher.update(message.plaintext, "utf8"), cipher.final(), cipher.getAuthTag()]);
      expect(sealed.toString("base64url")).toBe(message.box);

      const box = bytes(message.box);
      const decipher = createDecipheriv("aes-256-gcm", key, nonce).setAAD(aad);
      decipher.setAuthTag(box.subarray(box.length - 16));
      const opened = Buffer.concat([decipher.update(box.subarray(0, box.length - 16)), decipher.final()]);
      expect(opened.toString("utf8")).toBe(message.plaintext);
    }
  });

  it("rejects a box sealed for the other direction", () => {
    const request = vectors.messages.find((message) => message.direction === "req");
    expect(request).toBeDefined();
    if (!request) return;
    const box = bytes(request.box);
    const decipher = createDecipheriv("aes-256-gcm", bytes(vectors.r2i), bytes(request.nonce)).setAAD(bytes(request.aad));
    decipher.setAuthTag(box.subarray(box.length - 16));
    decipher.update(box.subarray(0, box.length - 16));
    expect(() => decipher.final()).toThrow();
  });
});
