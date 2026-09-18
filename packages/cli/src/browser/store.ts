import os from "node:os";
import path from "node:path";
import { mkdir, readFile, stat, writeFile } from "node:fs/promises";
import type { Platform } from "@unlikeotherai/kelpie-shared";

export interface BrowserAlias {
  platform: Platform;
  appPath?: string;
  profileDir?: string;
}

export interface RunningBrowser {
  port: number;
  lastLaunchedAt: string;
  pid?: number;
  launchId?: string;
  readinessFile?: string;
  deviceId?: string;
}

export interface BrowserStore {
  aliases: Record<string, BrowserAlias>;
  running: Record<string, RunningBrowser>;
}

const EMPTY_STORE: BrowserStore = {
  aliases: {},
  running: {},
};

function storeDir(): string {
  return process.env.KELPIE_HOME ?? path.join(os.homedir(), ".kelpie");
}

function storePath(): string {
  return path.join(storeDir(), "browsers.json");
}

export async function loadBrowserStore(): Promise<BrowserStore> {
  try {
    const contents = await readFile(storePath(), "utf8");
    const parsed = JSON.parse(contents) as Partial<BrowserStore>;
    return {
      aliases: parsed.aliases ?? {},
      running: parsed.running ?? {},
    };
  } catch {
    return { ...EMPTY_STORE };
  }
}

async function saveBrowserStore(store: BrowserStore): Promise<void> {
  await mkdir(storeDir(), { recursive: true });
  await writeFile(storePath(), JSON.stringify(store, null, 2));
}

export async function upsertBrowserAlias(name: string, alias: BrowserAlias): Promise<void> {
  const store = await loadBrowserStore();
  store.aliases[name] = alias;
  await saveBrowserStore(store);
}

export async function removeBrowserAlias(name: string): Promise<void> {
  const store = await loadBrowserStore();
  const { [name]: _alias, ...remainingAliases } = store.aliases;
  const { [name]: _running, ...remainingRunning } = store.running;
  store.aliases = remainingAliases;
  store.running = remainingRunning;
  await saveBrowserStore(store);
}

export async function setRunningBrowser(name: string, running: RunningBrowser): Promise<void> {
  const store = await loadBrowserStore();
  store.running[name] = running;
  await saveBrowserStore(store);
}

export async function clearRunningBrowser(name: string): Promise<void> {
  const store = await loadBrowserStore();
  const { [name]: _removed, ...remaining } = store.running;
  store.running = remaining;
  await saveBrowserStore(store);
}

export async function getBrowserAlias(name: string): Promise<BrowserAlias | undefined> {
  const store = await loadBrowserStore();
  return store.aliases[name];
}

export interface LocalReadiness {
  version: number;
  launchId: string;
  deviceId: string;
  port: number;
  token: string;
  controlMode: "loopback";
  mcp: { http: boolean; stdio: boolean; endpoint: "/mcp" };
}

export function readinessPath(alias: BrowserAlias): string | undefined {
  return alias.profileDir ? path.join(alias.profileDir, "readiness.json") : undefined;
}

/** Read the app-written local capability without persisting or printing it. */
export async function readLocalReadiness(file: string): Promise<LocalReadiness | undefined> {
  try {
    if ((await stat(file)).size > 16 * 1024) return undefined;
    const value = JSON.parse(await readFile(file, "utf8")) as Partial<LocalReadiness>;
    const boundedId = (input: unknown): input is string => typeof input === "string" && input.length > 0 && input.length <= 128;
    if (value.version !== 1 || !boundedId(value.launchId) || !boundedId(value.deviceId) ||
        !Number.isInteger(value.port) || (value.port ?? 0) < 1 || (value.port ?? 0) > 65_535 ||
        typeof value.token !== "string" || !/^[A-Za-z0-9_-]{32,512}$/.test(value.token) ||
        value.controlMode !== "loopback" || value.mcp?.endpoint !== "/mcp" ||
        typeof value.mcp.http !== "boolean" || !value.mcp.http ||
        typeof value.mcp.stdio !== "boolean") return undefined;
    return value as LocalReadiness;
  } catch {
    return undefined;
  }
}
