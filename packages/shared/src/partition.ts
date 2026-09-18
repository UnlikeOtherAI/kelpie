/**
 * Partition string validation — the single source of truth for every consumer.
 *
 * A partition is a free-form storage-container identifier supplied on
 * `new-tab`. Tabs sharing a partition string share cookies/localStorage/IDB;
 * tabs with different strings are fully isolated. The rules below are mirrored
 * verbatim in each platform's native handler (macOS `PartitionRegistry.swift`,
 * iOS, Android) so the CLI, the MCP layer, and every device agree on which
 * strings are acceptable.
 *
 * Keep this file and its native mirrors in lockstep — a validator that drifts
 * lets a caller create a partition on one platform that another rejects.
 */

/** Maximum length of a partition identifier, in ASCII characters. */
export const MAX_PARTITION_LENGTH = 128;

/** Maximum length of the free-form per-tab display `name`. */
export const MAX_TAB_NAME_LENGTH = 200;

/**
 * Reserved internal prefix. Android's non-persistent emulation creates
 * profiles named `ephemeral-<partition>-<uuid>`; a user-supplied string
 * starting with the same prefix could collide with one of those.
 */
export const RESERVED_PARTITION_PREFIX = "ephemeral-";

/**
 * Case-insensitively reserved whole strings. `default` is Android's
 * `Profile.DEFAULT_PROFILE_NAME`; `.` and `..` are path traversal hazards for
 * any platform that derives a directory name from the partition.
 */
const RESERVED_PARTITIONS = new Set([".", "..", "default"]);

// Dash last inside the class so it needs no escape.
const PARTITION_PATTERN = new RegExp(`^[A-Za-z0-9._-]{1,${String(MAX_PARTITION_LENGTH)}}$`);

const ALPHANUMERIC_PATTERN = /[A-Za-z0-9]/;

/** Machine-actionable discriminator for why a partition string was rejected. */
export type PartitionInvalidReason =
  | "charset-or-length"
  | "no-alnum"
  | "reserved"
  | "reserved-prefix";

export type PartitionValidation =
  | { ok: true }
  | { ok: false; reason: PartitionInvalidReason };

/**
 * Validate a partition identifier.
 *
 * Accepts 1–128 ASCII characters drawn from `[A-Za-z0-9._-]`, containing at
 * least one alphanumeric, that is neither a reserved word (`.`, `..`,
 * `default` — case-insensitive) nor prefixed with `ephemeral-`.
 */
export function validatePartition(value: string): PartitionValidation {
  if (!PARTITION_PATTERN.test(value)) return { ok: false, reason: "charset-or-length" };
  if (!ALPHANUMERIC_PATTERN.test(value)) return { ok: false, reason: "no-alnum" };
  if (RESERVED_PARTITIONS.has(value.toLowerCase())) return { ok: false, reason: "reserved" };
  if (value.startsWith(RESERVED_PARTITION_PREFIX)) return { ok: false, reason: "reserved-prefix" };
  return { ok: true };
}

/** Convenience predicate for callers that do not need the failure reason. */
export function isValidPartition(value: string): boolean {
  return validatePartition(value).ok;
}

/** Human-readable explanation for a rejection, reused by CLI and MCP errors. */
export function partitionErrorMessage(reason: PartitionInvalidReason): string {
  switch (reason) {
    case "charset-or-length":
      return `partition must be 1-${String(MAX_PARTITION_LENGTH)} characters from [A-Za-z0-9._-]`;
    case "no-alnum":
      return "partition must contain at least one letter or digit";
    case "reserved":
      return 'partition must not be ".", ".." or "default" (case-insensitive)';
    case "reserved-prefix":
      return `partition must not start with "${RESERVED_PARTITION_PREFIX}" (reserved internal prefix)`;
  }
}
