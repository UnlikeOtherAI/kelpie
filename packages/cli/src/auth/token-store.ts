import { promises as fs } from "node:fs";
import { existsSync, lstatSync } from "node:fs";
import { homedir, hostname, userInfo } from "node:os";
import { join } from "node:path";
import { randomUUID } from "node:crypto";

/**
 * Persistent token store backing `kelpie pair` and the implicit auth retry.
 *
 * Layout:
 *
 *   ~/.kelpie/
 *     tokens.json      mode 0600
 *
 * Tokens are keyed by `<deviceId>:<host>:<port>` (the *device fingerprint*).
 * Pinning to the host/port guards against mDNS TXT-record spoofing — if a
 * device id re-appears at a different socket address the CLI refuses to
 * send the stored token and forces a re-pair instead.
 *
 * Session-scope (`Yes, once`) approvals are NEVER written to disk; they
 * live in process memory via {@link SessionTokenCache} and are dropped at
 * CLI exit.
 */

export interface TokenStoreFile {
  /** Stable per-install client id. Persisted so re-pairs reuse it. */
  clientId: string;
  /** Schema version for forward-compatibility. */
  version: 1;
  /** `${deviceId}:${host}:${port}` -> bearer token (plaintext). */
  tokens: Record<string, string>;
}

const DIR_MODE = 0o700;
const FILE_MODE = 0o600;

export function fingerprintFor(deviceId: string, host: string, port: number): string {
  return `${deviceId}:${host}:${port}`;
}

export function defaultStoreDir(): string {
  return join(homedir(), ".kelpie");
}

function defaultStorePath(dir: string): string {
  return join(dir, "tokens.json");
}

function emptyStore(): TokenStoreFile {
  return { clientId: randomUUID(), version: 1, tokens: {} };
}

/** Returns the OS user + host for the self-reported client name. */
export function defaultClientName(): string {
  let user = "user";
  try {
    user = userInfo().username || user;
  } catch {
    /* fall back to literal "user" */
  }
  return `${user}@${hostname()}`;
}

/**
 * Ensure the storage directory exists with `0o700` and is not a symlink.
 * Refuses to operate on a symlinked path. If the directory is owned by the
 * current user but has wider perms, tightens them.
 */
async function ensureDir(dir: string): Promise<void> {
  if (existsSync(dir)) {
    const st = lstatSync(dir);
    if (st.isSymbolicLink()) {
      throw new Error(`Refusing to use symlinked token directory: ${dir}`);
    }
    if (!st.isDirectory()) {
      throw new Error(`Token path is not a directory: ${dir}`);
    }
    const mode = st.mode & 0o777;
    if (mode !== DIR_MODE) {
      if (st.uid === process.getuid?.()) {
        await fs.chmod(dir, DIR_MODE);
      } else {
        throw new Error(
          `Refusing to use token directory with unsafe perms ${mode.toString(8)}: ${dir}`,
        );
      }
    }
    return;
  }
  await fs.mkdir(dir, { recursive: true, mode: DIR_MODE });
  // mkdir mode is affected by umask, so re-apply explicitly.
  await fs.chmod(dir, DIR_MODE);
}

async function readStoreFile(path: string): Promise<TokenStoreFile> {
  if (!existsSync(path)) return emptyStore();
  const st = lstatSync(path);
  if (st.isSymbolicLink()) {
    throw new Error(`Refusing to read symlinked token file: ${path}`);
  }
  const mode = st.mode & 0o777;
  if (mode !== FILE_MODE) {
    if (st.uid === process.getuid?.()) {
      await fs.chmod(path, FILE_MODE);
    } else {
      throw new Error(
        `Refusing to read token file with unsafe perms ${mode.toString(8)}: ${path}`,
      );
    }
  }
  const raw = await fs.readFile(path, "utf8");
  try {
    const parsed: unknown = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object") return emptyStore();
    const obj = parsed as { clientId?: unknown; tokens?: unknown };
    const tokens: Record<string, string> = {};
    if (obj.tokens && typeof obj.tokens === "object") {
      for (const [key, value] of Object.entries(obj.tokens as Record<string, unknown>)) {
        if (typeof value === "string") tokens[key] = value;
      }
    }
    return {
      clientId: typeof obj.clientId === "string" ? obj.clientId : randomUUID(),
      version: 1,
      tokens,
    };
  } catch {
    // Corrupt file: treat as empty rather than crashing the CLI. Caller's
    // next save overwrites with a fresh document.
    return emptyStore();
  }
}

async function writeStoreFile(path: string, data: TokenStoreFile): Promise<void> {
  const tmp = `${path}.tmp.${process.pid}.${Date.now()}`;
  const handle = await fs.open(tmp, "w", FILE_MODE);
  try {
    await handle.writeFile(JSON.stringify(data, null, 2));
    await handle.sync();
  } finally {
    await handle.close();
  }
  await fs.chmod(tmp, FILE_MODE);
  await fs.rename(tmp, path);
}

/**
 * Disk-backed token store. Synchronous mutation is not required — pair flow
 * already awaits the device.
 */
export class TokenStore {
  private readonly dir: string;
  private readonly file: string;
  private cache: TokenStoreFile | null = null;
  /** True once the on-disk file has been written at least once this session. */
  private persistedClientId = false;

  constructor(dir = defaultStoreDir()) {
    this.dir = dir;
    this.file = defaultStorePath(dir);
  }

  async clientId(): Promise<string> {
    const data = await this.load();
    // Persist a freshly-generated clientId so subsequent CLI invocations
    // present the same identity to paired devices.
    if (!this.persistedClientId) {
      await this.flush(data);
      this.persistedClientId = true;
    }
    return data.clientId;
  }

  async get(deviceId: string, host: string, port: number): Promise<string | undefined> {
    const data = await this.load();
    return data.tokens[fingerprintFor(deviceId, host, port)];
  }

  async set(deviceId: string, host: string, port: number, token: string): Promise<void> {
    const data = await this.load();
    data.tokens[fingerprintFor(deviceId, host, port)] = token;
    await this.flush(data);
  }

  async remove(deviceId: string, host: string, port: number): Promise<void> {
    const data = await this.load();
    const key = fingerprintFor(deviceId, host, port);
    if (!(key in data.tokens)) return;
    const next: Record<string, string> = {};
    for (const [k, v] of Object.entries(data.tokens)) {
      if (k !== key) next[k] = v;
    }
    data.tokens = next;
    await this.flush(data);
  }

  async list(): Promise<Record<string, string>> {
    const data = await this.load();
    return { ...data.tokens };
  }

  /** Test seam: drop the cache so the next call re-reads from disk. */
  resetCache(): void {
    this.cache = null;
  }

  private async load(): Promise<TokenStoreFile> {
    if (this.cache) return this.cache;
    await ensureDir(this.dir);
    const fileExistedOnDisk = existsSync(this.file);
    this.cache = await readStoreFile(this.file);
    // If we read a real file, the clientId in it is already persisted; no
    // need for clientId() to re-flush.
    if (fileExistedOnDisk) this.persistedClientId = true;
    return this.cache;
  }

  private async flush(data: TokenStoreFile): Promise<void> {
    await ensureDir(this.dir);
    await writeStoreFile(this.file, data);
    this.cache = data;
  }
}

/**
 * In-memory cache for `Yes, once` approvals. Lives for the lifetime of a
 * single CLI process; the user must re-approve next invocation.
 */
export class SessionTokenCache {
  private readonly tokens = new Map<string, string>();

  get(deviceId: string, host: string, port: number): string | undefined {
    return this.tokens.get(fingerprintFor(deviceId, host, port));
  }

  set(deviceId: string, host: string, port: number, token: string): void {
    this.tokens.set(fingerprintFor(deviceId, host, port), token);
  }

  remove(deviceId: string, host: string, port: number): void {
    this.tokens.delete(fingerprintFor(deviceId, host, port));
  }
}

/** Process-wide singletons used by the CLI runtime. */
let persistentStore: TokenStore | null = null;
let sessionCache: SessionTokenCache | null = null;

export function getTokenStore(): TokenStore {
  persistentStore ??= new TokenStore();
  return persistentStore;
}

export function getSessionCache(): SessionTokenCache {
  sessionCache ??= new SessionTokenCache();
  return sessionCache;
}

/** Test seam: install a custom-directory store for the duration of a test. */
export function setTokenStoreForTesting(store: TokenStore | null): void {
  persistentStore = store;
}

/** Test seam: drop the in-memory session cache. */
export function resetSessionCacheForTesting(): void {
  sessionCache = null;
}
