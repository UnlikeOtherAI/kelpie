import { readFile } from "node:fs/promises";
import type { Command } from "commander";
import {
  MAX_SET_COOKIES,
  cookieInfoSchema,
  partitionErrorMessage,
  validatePartition,
  type CookieInfo,
  type CookieStoreTarget,
} from "@unlikeotherai/kelpie-shared";
import { getGlobals } from "./helpers.js";
import { print } from "../output/formatter.js";

/** A cookie command the CLI refuses before it contacts a device. */
export class CookieInputError extends Error {
  constructor(
    readonly code: "INVALID_PARAMS" | "INVALID_PARTITION" | "INVALID_ARGUMENT",
    message: string,
  ) {
    super(message);
  }
}

/**
 * One cookie store from a tab flag and a partition flag. `{}` is the default
 * store. The device validates too; checking here gives an immediate, specific
 * message instead of a round trip.
 */
export function cookieStoreTarget(
  tabId: string | undefined,
  partition: string | undefined,
  flags: { tab: string; partition: string },
): CookieStoreTarget {
  if (tabId !== undefined && partition !== undefined) {
    throw new CookieInputError("INVALID_PARAMS", `Use ${flags.tab} or ${flags.partition}, not both.`);
  }
  if (partition !== undefined) {
    const result = validatePartition(partition);
    if (!result.ok) {
      throw new CookieInputError("INVALID_PARTITION", `invalid ${flags.partition}: ${partitionErrorMessage(result.reason)}`);
    }
    return { partition };
  }
  return tabId === undefined ? {} : { tabId };
}

/** True when two targets name the same store by the same flags. */
export function sameCookieStore(left: CookieStoreTarget, right: CookieStoreTarget): boolean {
  return left.tabId === right.tabId && left.partition === right.partition;
}

async function readText(source: string, stdin: NodeJS.ReadableStream): Promise<string> {
  if (source !== "-") {
    try {
      return await readFile(source, "utf8");
    } catch (error) {
      const reason = error instanceof Error ? error.message : String(error);
      throw new CookieInputError("INVALID_PARAMS", `Cannot read ${source}: ${reason}`);
    }
  }
  const chunks: Buffer[] = [];
  for await (const chunk of stdin) {
    chunks.push(typeof chunk === "string" ? Buffer.from(chunk) : chunk);
  }
  return Buffer.concat(chunks).toString("utf8");
}

/** The cookie list inside a JSON array, or inside the object `cookies list` prints. */
function cookieList(parsed: unknown): unknown[] | undefined {
  if (Array.isArray(parsed)) return parsed as unknown[];
  if (typeof parsed === "object" && parsed !== null) {
    const cookies = (parsed as { cookies?: unknown }).cookies;
    if (Array.isArray(cookies)) return cookies as unknown[];
  }
  return undefined;
}

/**
 * Cookies from a file, or from stdin when `source` is `-`. Accepts a JSON
 * array of cookies or the object `kelpie cookies list` prints, so a listing
 * can be imported unchanged. Unknown fields are dropped.
 */
export async function readCookieInput(
  source: string,
  stdin: NodeJS.ReadableStream = process.stdin,
): Promise<CookieInfo[]> {
  const label = source === "-" ? "stdin" : source;
  let parsed: unknown;
  try {
    parsed = JSON.parse(await readText(source, stdin));
  } catch (error) {
    if (error instanceof CookieInputError) throw error;
    throw new CookieInputError("INVALID_PARAMS", `${label} is not valid JSON.`);
  }
  const list = cookieList(parsed);
  if (!list) {
    throw new CookieInputError(
      "INVALID_PARAMS",
      `${label} must hold a JSON array of cookies, or the object \`kelpie cookies list\` prints.`,
    );
  }
  const result = cookieInfoSchema.array().safeParse(list);
  if (!result.success) {
    const issue = result.error.issues[0];
    const [index, ...field] = issue?.path ?? [];
    const where = index === undefined ? "" : `cookie ${String(index)}${field.length ? ` field ${field.map(String).join(".")}` : ""}: `;
    throw new CookieInputError("INVALID_PARAMS", `${label}: ${where}${issue?.message ?? "invalid cookie"}`);
  }
  return result.data;
}

/** `set-cookies` takes at most `MAX_SET_COOKIES`; always at least one batch. */
export function cookieBatches(cookies: readonly CookieInfo[]): CookieInfo[][] {
  const batches: CookieInfo[][] = [];
  for (let offset = 0; offset < cookies.length; offset += MAX_SET_COOKIES) {
    batches.push(cookies.slice(offset, offset + MAX_SET_COOKIES));
  }
  return batches.length > 0 ? batches : [[]];
}

/** Print a refused cookie command in the caller's chosen format. */
export function printCookieInputError(program: Command, error: CookieInputError): void {
  print({ success: false, error: { code: error.code, message: error.message } }, getGlobals(program).format);
  process.exitCode = 1;
}
