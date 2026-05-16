# Per-Tab Partition + Name — Shared (CLI / MCP / Types / Docs)

Parent: [../2026-05-16-per-tab-partition-and-name.md](../2026-05-16-per-tab-partition-and-name.md)

Lands first. Types-only; platform agents depend on it for shared API definitions.

## Files

### `packages/shared/src/partition.ts` (new — single source of truth for validation)

```ts
const PARTITION_REGEX = /^[A-Za-z0-9._\-]{1,128}$/;
const RESERVED = new Set(["default", "."]);  // case-insensitive; also rejects ".."
const RESERVED_PREFIX = "ephemeral-";

export function validatePartition(s: string): { ok: true } | { ok: false; reason: string } {
  if (!PARTITION_REGEX.test(s)) return { ok: false, reason: "charset-or-length" };
  if (!/[A-Za-z0-9]/.test(s)) return { ok: false, reason: "no-alnum" };
  if (s === ".." || RESERVED.has(s.toLowerCase())) return { ok: false, reason: "reserved" };
  if (s.startsWith(RESERVED_PREFIX)) return { ok: false, reason: "reserved-prefix" };
  return { ok: true };
}
```

Exported and re-used by CLI option parsing and MCP Zod refinements. Each platform mirrors this logic in its own language with identical rules.

### `packages/shared/src/api-types.ts`

Extend `NewTabRequest`:
```ts
export interface NewTabRequest {
  url?: string;
  name?: string;
  partition?: string;
  persistent?: boolean;   // defaults to true; only meaningful when partition is set
}
```

Extend `TabInfo`:
```ts
export interface TabInfo {
  id: string;
  url: string;
  title: string;
  active: boolean;
  isLoading?: boolean;
  name?: string;
  partition?: string;
  persistent?: boolean;
}
```

Add partition types:
```ts
export interface Partition {
  id: string;
  tabCount: number;
  persistent: boolean;
  sizeBytes?: number;
}

export interface GetPartitionsResponse extends SuccessResponse {
  partitions: Partition[];
}

export interface DeletePartitionRequest {
  id: string;
}

export interface DeletePartitionResponse extends SuccessResponse {
  deleted: string;       // always the requested id
  tabsClosed: number;
  existed: boolean;      // false when the id was unknown
}

export type PartitionUnsupportedReason =
  | "chromium-engine"
  | "webview-multi-profile-missing"
  | "platform-single-tab";

export interface PartitionUnsupportedError {
  success: false;
  error: "PARTITION_UNSUPPORTED";
  reason: PartitionUnsupportedReason;
  activeEngine?: "chromium" | "webkit";
  hint?: string;
}
```

### `packages/cli/src/commands/tabs.ts`

`tab new` gains flags:
- `--name <label>` → `body.name`
- `--partition <id>` → `body.partition` (validated via `validatePartition` before send)
- `--non-persistent` → `body.persistent = false`

Reject `--non-persistent` without `--partition`, and reject any `partition` that fails `validatePartition`, with clear CLI errors before the request fires. **Server-side handlers must validate too** — a direct HTTP caller bypassing the CLI would otherwise hit undefined behaviour.

### `packages/cli/src/commands/partitions.ts` (new)

```
kelpie partitions [--device <name>]
kelpie partition delete <id> [--device <name>]
```

Same `deviceCommand` plumbing as `tab new`.

### `packages/cli/src/index.ts`

Register the new `partitions` and `partition` command groups.

### `packages/cli/src/help/command-metadata.ts`

- Extend `"new-tab"` entry with `name`, `partition`, `persistent` flag docs (use the existing flag-field shape).
- Add `"get-partitions"` and `"delete-partition"` entries.
- Update `"new-tab"`'s `response` field to include the new `TabInfo` shape.
- Add new `partitionInfoFields` helper used by both new commands' response schemas.

### `packages/cli/src/mcp/tools.ts`

- Extend `kelpie_new_tab` Zod schema with `name`, `partition`, `persistent`.
- Add `kelpie_get_partitions` tool (method `getPartitions`, no body params).
- Add `kelpie_delete_partition` tool (method `deletePartition`, body `{ id: string }`).

### `packages/cli/src/types.ts`

If there's a `Methods` union or `MethodName` literal, add `"getPartitions"` and `"deletePartition"`.

### Tests

- `packages/cli/tests/commands/commands.test.ts` — flag parsing for `tab new --name --partition --non-persistent`; method-name mapping for `partitions` and `partition delete`.
- `packages/cli/tests/commands/partitions.test.ts` (new) — argument validation, helpful error when `--non-persistent` used without `--partition`.
- `packages/cli/tests/e2e/browser-management.e2e.test.ts` — partition acceptance test (mocked device): two-tab isolation check via the eval method.
- `packages/cli/tests/help/llm-help.test.ts` — extend with the new metadata entries.

### Docs

- `docs/api/browser.md` — `newTab` request example with `name`/`partition`; new `getPartitions` and `deletePartition` sections; new errors section listing `INVALID_PARTITION`, `PARTITION_UNSUPPORTED` (with full `reason` matrix and per-platform recovery hints), `PARTITION_DELETING`, `PARTITION_IN_USE`.
- `docs/cli.md` — `kelpie tab new` flag list; new `partitions` and `partition delete` command sections.
- `docs/functionality.md` — under tabs section, describe per-tab naming and storage partitioning, and list per-platform support matrix (iOS/Android/macOS WK supported; Linux/Windows/macOS CEF not).

## Constraints

- Strictly additive — every change is optional with safe defaults; existing CLI calls and HTTP bodies must keep working unchanged.
- No new shared dependencies.
- Keep all changes ≤ 500 lines per file.

## Verification

- `pnpm lint && pnpm build && pnpm test` from repo root.
- `kelpie tab new --help` shows the new flags.
- `kelpie --llm-help new-tab` shows the new flags and the updated response schema.
