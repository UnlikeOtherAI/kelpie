import os from "node:os";
import path from "node:path";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import type { Platform } from "@unlikeotherai/kelpie-shared";

export interface BrowserAlias {
  platform: Platform;
  appPath?: string;
}

export interface RunningBrowser {
  port: number;
  lastLaunchedAt: string;
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
  return path.join(os.homedir(), ".kelpie");
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
  delete store.aliases[name];
  delete store.running[name];
  await saveBrowserStore(store);
}

export async function setRunningBrowser(name: string, running: RunningBrowser): Promise<void> {
  const store = await loadBrowserStore();
  store.running[name] = running;
  await saveBrowserStore(store);
}

export async function clearRunningBrowser(name: string): Promise<void> {
  const store = await loadBrowserStore();
  delete store.running[name];
  await saveBrowserStore(store);
}

export async function getBrowserAlias(name: string): Promise<BrowserAlias | undefined> {
  const store = await loadBrowserStore();
  return store.aliases[name];
}
