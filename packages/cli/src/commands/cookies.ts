import type { Command } from "commander";
import type { SetCookieFailure, SetCookiesResponse } from "@unlikeotherai/kelpie-shared";
import { commandTimeout, deviceCommand, getGlobals, requireDevice, withGlobalTabId } from "./helpers.js";
import {
  CookieInputError,
  cookieBatches,
  cookieStoreTarget,
  printCookieInputError,
  readCookieInput,
  sameCookieStore,
} from "./cookie-options.js";
import { sendCommand } from "../client/http-client.js";
import { print } from "../output/formatter.js";

interface ListOptions {
  name?: string;
  all?: boolean;
  domain?: string;
  partition?: string;
}

interface ImportOptions {
  tab?: string;
  partition?: string;
}

interface CopyOptions {
  fromTab?: string;
  fromPartition?: string;
  toTab?: string;
  toPartition?: string;
  domain?: string;
}

/** Run `action`, printing a refused command instead of throwing it. */
async function guarded(program: Command, action: () => Promise<void>): Promise<void> {
  try {
    await action();
  } catch (error) {
    if (!(error instanceof CookieInputError)) throw error;
    printCookieInputError(program, error);
  }
}

/** The global `--tab-id` already names a tab, so it cannot be combined with a partition. */
function rejectTabWithPartition(program: Command, partition: string | undefined): void {
  if (getGlobals(program).tabId !== undefined && partition !== undefined) {
    throw new CookieInputError("INVALID_PARAMS", "Use --tab-id or --partition, not both.");
  }
}

async function listCookies(program: Command, opts: ListOptions): Promise<void> {
  rejectTabWithPartition(program, opts.partition);
  const body: Record<string, unknown> = { ...cookieStoreTarget(undefined, opts.partition, { tab: "--tab-id", partition: "--partition" }) };
  if (opts.name) body.name = opts.name;
  if (opts.all) body.all = true;
  if (opts.domain) body.domain = opts.domain;
  await deviceCommand(program, "getCookies", body);
}

/**
 * Write the file's cookies in batches the endpoint accepts. Refused cookies
 * are reported by their position in the file; a failed batch stops the
 * import and reports how far it got.
 */
async function importCookies(program: Command, source: string, opts: ImportOptions): Promise<void> {
  rejectTabWithPartition(program, opts.partition);
  const target = cookieStoreTarget(opts.tab, opts.partition, { tab: "--tab", partition: "--partition" });
  const cookies = await readCookieInput(source);
  const device = await requireDevice(program);
  if (!device) return;
  const globals = getGlobals(program);
  const timeout = commandTimeout(program);
  let set = 0;
  const failed: SetCookieFailure[] = [];
  let offset = 0;
  for (const batch of cookieBatches(cookies)) {
    const result = await sendCommand(device, "setCookies", withGlobalTabId(globals, { ...target, cookies: batch }), timeout);
    const data = result.data as Partial<SetCookiesResponse> | undefined;
    if (!result.ok || data?.success !== true) {
      const reply = result.data;
      print(offset > 0 && typeof reply === "object" && reply !== null ? { ...reply, set, failed } : reply, globals.format);
      process.exitCode = 1;
      return;
    }
    set += data.set ?? 0;
    failed.push(...(data.failed ?? []).map((failure) => ({ ...failure, index: failure.index + offset })));
    offset += batch.length;
  }
  print({ success: true, set, failed }, globals.format);
}

async function copyCookies(program: Command, opts: CopyOptions): Promise<void> {
  if (getGlobals(program).tabId !== undefined) {
    throw new CookieInputError("INVALID_PARAMS", "cookies copy takes --from-tab and --to-tab, not --tab-id.");
  }
  const from = cookieStoreTarget(opts.fromTab, opts.fromPartition, { tab: "--from-tab", partition: "--from-partition" });
  const to = cookieStoreTarget(opts.toTab, opts.toPartition, { tab: "--to-tab", partition: "--to-partition" });
  if (sameCookieStore(from, to)) {
    throw new CookieInputError(
      "INVALID_PARAMS",
      "The source and target are the same store. With no flags both are the default store; pass --from-* or --to-*.",
    );
  }
  const body: Record<string, unknown> = { from, to };
  if (opts.domain) body.domain = opts.domain;
  await deviceCommand(program, "copyCookies", body);
}

export function registerCookies(program: Command): void {
  const cookies = program
    .command("cookies")
    .description("Manage cookies");

  cookies
    .command("list")
    .description("Get cookies for the current page, or every cookie in a store with --all")
    .option("--name <name>", "Filter by cookie name")
    .option("--all", "Every cookie in the store, not just the current page's")
    .option("--domain <domain>", "Only cookies for this domain and its subdomains")
    .option("--partition <id>", "Read this partition's store instead of the default store")
    .action((opts: ListOptions) => guarded(program, () => listCookies(program, opts)));

  cookies
    .command("set <name> <value>")
    .description("Set a cookie")
    .option("--domain <domain>", "Cookie domain")
    .option("--path <path>", "Cookie path")
    .option("--secure", "Secure flag")
    .option("--http-only", "HttpOnly flag")
    .option("--same-site <val>", "SameSite: Lax, Strict, None")
    .option("--expires <date>", "Expiry as an HTTP date string (e.g. 'Wed, 09 Jun 2027 10:18:14 GMT')")
    .action(async (name: string, value: string, opts: {
      domain?: string;
      path?: string;
      secure?: boolean;
      httpOnly?: boolean;
      sameSite?: string;
      expires?: string;
    }) => {
      const body: Record<string, unknown> = { name, value };
      if (opts.domain) body.domain = opts.domain;
      if (opts.path) body.path = opts.path;
      if (opts.secure) body.secure = true;
      if (opts.httpOnly) body.httpOnly = true;
      if (opts.sameSite) body.sameSite = opts.sameSite;
      if (opts.expires) body.expires = opts.expires;
      await deviceCommand(program, "setCookie", body);
    });

  cookies
    .command("import <file>")
    .description("Write cookies from a JSON file, or - for stdin, into a store (default store unless --tab or --partition)")
    .option("--tab <id>", "Write into this tab's store")
    .option("--partition <id>", "Write into this partition's store")
    .action((file: string, opts: ImportOptions) => guarded(program, () => importCookies(program, file, opts)));

  cookies
    .command("copy")
    .description("Copy cookies between stores on one device; values never leave it. No flag on a side means the default store")
    .option("--from-tab <id>", "Copy from this tab's store")
    .option("--from-partition <id>", "Copy from this partition's store")
    .option("--to-tab <id>", "Copy into this tab's store")
    .option("--to-partition <id>", "Copy into this partition's store")
    .option("--domain <domain>", "Only cookies for this domain and its subdomains")
    .action((opts: CopyOptions) => guarded(program, () => copyCookies(program, opts)));

  cookies
    .command("sync-status")
    .description("Show peer-to-peer cookie sync: whether it runs, peers, last sync and store counts")
    .action(() => deviceCommand(program, "getCookieSyncStatus"));

  cookies
    .command("delete")
    .description("Delete cookies")
    .option("--name <name>", "Delete by name")
    .option("--domain <domain>", "Scope by domain")
    .option("--all", "Delete all cookies")
    .action(async (opts: { name?: string; domain?: string; all?: boolean }) => {
      const body: Record<string, unknown> = {};
      if (opts.name) body.name = opts.name;
      if (opts.domain) body.domain = opts.domain;
      if (opts.all) body.deleteAll = true;
      await deviceCommand(program, "deleteCookies", body);
    });
}
