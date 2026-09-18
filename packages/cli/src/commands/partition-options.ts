import type { Command } from "commander";
import {
  MAX_TAB_NAME_LENGTH,
  partitionErrorMessage,
  validatePartition,
} from "@unlikeotherai/kelpie-shared";
import { getGlobals } from "./helpers.js";
import { print } from "../output/formatter.js";

/** Flags `tab new` accepts for per-tab naming and storage isolation. */
export interface PartitionTabOptions {
  name?: string;
  partition?: string;
  ephemeral?: boolean;
  nonPersistent?: boolean;
}

/**
 * Client-side validation for the partition flags.
 *
 * The device validates too — a direct HTTP caller bypasses the CLI entirely —
 * but catching it here turns a round-trip into an immediate, specific message.
 */
export function partitionFlagError(opts: PartitionTabOptions): string | null {
  const ephemeral = opts.ephemeral === true || opts.nonPersistent === true;

  if (opts.name !== undefined && opts.name.length > MAX_TAB_NAME_LENGTH) {
    return `--name must be at most ${String(MAX_TAB_NAME_LENGTH)} characters`;
  }
  if (ephemeral && opts.partition === undefined) {
    return "--ephemeral requires --partition: only a named partition can be made non-persistent";
  }
  if (opts.partition !== undefined) {
    const result = validatePartition(opts.partition);
    if (!result.ok) return `invalid --partition: ${partitionErrorMessage(result.reason)}`;
  }
  return null;
}

/**
 * Body fields for `new-tab`. `persistent` is only sent when explicitly turned
 * off, keeping the request byte-identical to today's for existing callers.
 */
export function partitionTabBody(opts: PartitionTabOptions): Record<string, unknown> {
  const body: Record<string, unknown> = {};
  if (opts.name !== undefined) body.name = opts.name;
  if (opts.partition !== undefined) body.partition = opts.partition;
  if (opts.ephemeral === true || opts.nonPersistent === true) body.persistent = false;
  return body;
}

/** Print a structured validation failure in the caller's chosen format. */
export function printValidationError(program: Command, message: string): void {
  print(
    { success: false, error: { code: "INVALID_PARTITION", message } },
    getGlobals(program).format,
  );
  process.exitCode = 1;
}
