import { generateKeyPairSync, createPrivateKey, createPublicKey, sign, randomUUID } from "node:crypto";
import { promises as fs } from "node:fs";
import { join } from "node:path";
import { defaultStoreDir } from "./token-store.js";

export interface ComputerIdentity {
  publicKey: string;
  signChallenge(challenge: string): string;
}

/** One protected signing key for all CLI/MCP processes of this computer user. */
export async function computerIdentity(dir = defaultStoreDir()): Promise<ComputerIdentity> {
  await fs.mkdir(dir, { recursive: true, mode: 0o700 });
  const directory = await fs.lstat(dir);
  if (!directory.isDirectory() || directory.isSymbolicLink()) throw new Error("Computer signing directory must be a regular directory");
  if (process.platform !== "win32") await fs.chmod(dir, 0o700);
  const path = join(dir, "computer-key.pem");
  try { await fs.lstat(path); } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
    const { privateKey } = generateKeyPairSync("ed25519");
    const temporary = `${path}.${process.pid}.${randomUUID()}.tmp`;
    await fs.writeFile(temporary, privateKey.export({ type: "pkcs8", format: "pem" }), { mode: 0o600, flag: "wx" });
    try {
      // Link publishes a complete key without overwriting a concurrent process's key.
      await fs.link(temporary, path);
    } catch (linkError) {
      if ((linkError as NodeJS.ErrnoException).code !== "EEXIST") throw linkError;
    } finally { await fs.unlink(temporary); }
  }
  const info = await fs.lstat(path);
  if (!info.isFile() || info.isSymbolicLink()) throw new Error("Computer signing key must be a regular file");
  if (process.platform !== "win32") await fs.chmod(path, 0o600);
  const key = createPrivateKey(await fs.readFile(path));
  if (key.asymmetricKeyType !== "ed25519") throw new Error("Computer signing key must be Ed25519");
  const jwk = createPublicKey(key).export({ format: "jwk" });
  if (typeof jwk.x !== "string") throw new Error("Computer signing key has no public identity");
  const publicKey = Buffer.from(jwk.x, "base64url").toString("hex");
  return {
    publicKey,
    signChallenge: (challenge) => sign(null,
      Buffer.from(`kelpie-computer-pair-v1\n${challenge}\n${publicKey}`), key).toString("hex"),
  };
}
