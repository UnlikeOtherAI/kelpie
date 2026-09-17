# Plan — `kelpie describe`: a stable machine-readable detection contract

Date: 2026-09-17
Branch: `feat/nessie-executor-discovery`
Status: design, pending cross-provider review

## Why

Nessie's executor (a per-machine daemon) will front Kelpie's MCP server and
report to Nessie whether Kelpie is installed and which Kelpie instances are on
the network. Today the only way to learn either is to parse human-facing CLI
output, coupling Nessie to incidental formatting. This plan adds one small,
stable, machine-readable surface so that coupling never exists.

Everything is additive. No existing human-facing output changes shape.

## Part 1 — `kelpie describe --json`

New command `describe` in `packages/cli/src/commands/describe.ts`.

### Flags

- `--json` — emit the stable JSON document (the contract). Without it, print a
  short human summary; the human form is *not* part of the contract.
- `--scan-timeout <ms>` — discovery budget, default `3000` (matches
  `kelpie discover`). A daemon polling on a schedule needs a bound; a person
  debugging wants longer.
- `--tools` — include the full wire tool catalog (name, description,
  inputSchema) under `tools.catalog`. Off by default: 145 schemas do not
  belong in a detection document; count + digest answer drift.

### Document grammar (schemaVersion 1)

```json
{
  "schemaVersion": 1,
  "generatedAt": "<ISO 8601>",
  "cli": {
    "version": "0.1.11",
    "path": "/absolute/realpath/of/the/answering/binary"
  },
  "mcp": {
    "available": true,
    "stdio": { "command": "kelpie", "args": ["mcp"] },
    "http": {
      "command": "kelpie",
      "args": ["mcp", "--http", "--port", "8421", "--bind", "127.0.0.1"],
      "defaultPort": 8421,
      "defaultBind": "127.0.0.1"
    }
  },
  "tools": {
    "count": 145,
    "digest": "sha256:<64 hex>",
    "digestAlgorithm": "<precise recipe, see below>",
    "catalog": [ { "name": "...", "description": "...", "inputSchema": { } } ]
  },
  "discovery": {
    "scanTimeoutMs": 3000,
    "mdns": "ok" | "unavailable",
    "deviceCount": 1,
    "devices": [
      {
        "id": "…", "name": "…", "model": "…",
        "platform": "ios|android|macos|linux|windows",
        "runtimeMode": "gui|headless",
        "engine": "webkit",
        "version": "0.1.13",
        "address": "192.168.1.42",
        "port": 8420,
        "display": { "width": 1440, "height": 900 },
        "paired": true,
        "lastSeenAt": "<ISO 8601>"
      }
    ]
  }
}
```

Device entries are shaped exactly like the Nessie `KelpieDeviceSchema`
(`packages/schemas/src/executor-mcp.ts` @ d4716d255): `address` not `ip`,
`display` an object, `lastSeenAt` an ISO timestamp, optional fields omitted
when unknown.

### Key decisions

1. **Catalog comes from a real server, not re-derived.** `describe` builds the
   actual `McpServer` (`createMcpServer()`), connects an SDK `Client` over
   `InMemoryTransport`, and reads `tools/list`. The digest is over what a
   client would literally receive — no reimplementation of the SDK's
   zod→JSON-Schema transform, so the digest cannot drift from the wire form.
   A successful handshake is also the proof behind `mcp.available: true`; a
   failure sets `available: false`, `tools` omitted, document still exits 0.

2. **Digest recipe (documented in docs/cli.md):** take the wire tools, keep
   `{name, description, inputSchema}` per tool, sort by `name`, serialize as
   canonical JSON (object keys sorted recursively, no whitespace), SHA-256 the
   UTF-8 bytes, prefix `sha256:`. Matches the Nessie contract's digest regex.
   The executor can recompute it from its own `mcp.tools` listing and compare.

3. **Discovery reuses existing code.** `scanForDevices(timeout)` + always
   `probeLocalDevices()` (mDNS is racy for same-host instances; the local
   instance is the one Nessie cares about most), merged and deduped by
   `address:port`. A loopback `local:`-id entry may therefore coexist with an
   mDNS entry for the same instance seen via its LAN address — both are valid
   observations; documented, not hidden. If the mDNS browse itself throws
   (no responder), `discovery.mdns: "unavailable"`, local probe still runs,
   exit stays 0.

4. **`paired` is the operational fact.** For each discovered device,
   `paired = (session cache or token store).get(device.id, device.ip,
   device.port) !== undefined` — exactly the lookup `sendCommand` performs, so
   `paired: true` means "this CLI would send a token for this instance right
   now". Only the boolean ever leaves the process. A test seeds the token
   store with a canary token and asserts the string never appears in output.

5. **Exit codes.** 0 whenever the document is produced — including zero
   devices, mDNS down, MCP handshake failed (those are *answers*). Non-zero
   only when the CLI could not answer at all (unexpected internal error → 1).

6. **`engine` reaches the device type.** `MdnsTxtRecord.engine` exists but
   `scanner.ts` drops it. Add optional `engine?: string` to
   `DiscoveredDevice`, populated in `scanner.ts` (from TXT) and
   `local-probe.ts` (from `/v1/get-device-info` `browser.engine`). Additive:
   table/text output use fixed columns and are unchanged; JSON output of
   `kelpie discover` gains one optional key only when the instance reports an
   engine. Called out here because the brief forbids changing existing output
   shapes silently.

### Non-goals

- No change to pairing, token storage, or the token-lookup fingerprint scheme.
- No change to `discover`, `registry`, or MCP server behavior.
- No signed-schema change on the Nessie side; if the grammar above cannot
  express something, that goes in the report, not in Nessie's schema files.

## Part 2 — documented install layout

New doc `docs/install-layout.md` stating, as a stable contract, what Kelpie
installs where and how a script detects each piece:

- macOS app: `/Applications/Kelpie.app`, bundle id `com.kelpie.browser.macos`
  (helper `com.kelpie.browser.helper`), version readable from
  `Contents/Info.plist` → `CFBundleShortVersionString` (no code change needed —
  already present).
- CLI: npm package `@unlikeotherai/kelpie`, binary `kelpie` on PATH
  (`command -v kelpie`, `kelpie --version`).
- iOS app: bundle id `com.unlikeotherai.kelpie`; Android: applicationId
  `com.kelpie.browser`. Windows/Linux: whatever the repo actually does today —
  documented as-found, marked accidental where it is accidental.

The describe grammar also lives in `docs/cli.md`; `docs/functionality.md`
gains the user-facing description.

## Part 3 — build, install, verify (this machine)

Per the release policy's build-and-install half (no release, no version bump,
no npm publish): `make macos-build`, kill any running Kelpie, `ditto` the
product into `/Applications/Kelpie.app`, relaunch from `/Applications`,
`make cli` (pnpm link --global from this worktree), then verify:
app running ↔ `kelpie describe --json` lists it, and `kelpie mcp` completes a
handshake whose `tools/list` digest equals the describe digest. Build is
unsigned (no Developer ID on this machine) — expected; Gatekeeper per-app
allowance steps are documented for a person, not worked around.

## Tests (vitest, `packages/cli/tests/commands/describe.test.ts`)

`buildDescribeDocument` takes injected deps (scan, probe, pairing lookup,
catalog listing) so each case is hermetic:

- one mDNS device found → full field mapping, exit 0
- no devices → `devices: []`, `deviceCount: 0`, valid document, exit 0
- mDNS throws → `mdns: "unavailable"`, probe still runs, exit 0
- local-only instance found by probe, not mDNS
- paired instance (token present) / unpaired instance
- no-credentials-ever: canary token never appears in serialized output
- digest: stable across runs, changes when a tool changes
- handshake failure → `mcp.available: false`, document still valid, exit 0

## Cross-Provider Review

(pending — adversarial review to be appended before implementation)

## Cross-Provider Review

Reviewed by Claude (claude-sonnet-4-5, adversarial prompt) on 2026-09-17.
39 findings: 4 flagged blocker, 8 major, 16 minor, 11 nit. Adjudication:

**Accepted (change the design):**
- #4 digest underspecified → the recipe is now an exact reference algorithm
  (recursive key sort, JS `JSON.stringify` number/string semantics, UTF-8
  bytes, no Unicode normalization), published in docs/cli.md so the executor
  (also TypeScript) reproduces it bit-for-bit. `digestAlgorithm` becomes the
  structured id `sha256-canonical-json-v1` (#20).
- #9 add `mcp.reason`/`mcp.detail` on handshake failure, sanitized (no host
  paths — `$HOME` redacted).
- #7 partial objects: `display` is emitted whole or not at all (in practice
  always present; both dimensions default 0).
- #8/#14/#18 timestamps: `generatedAt`/`lastSeenAt` are the scan host's clock,
  ISO 8601 UTC ms precision; the document is a point-in-time observation.
- #6 pairing lookup is session-cache-then-store, same as `sendCommand`;
  documented.
- #11/#39 `address` is always an IP literal, IPv4 preferred (existing
  `pickAddress` behavior), documented.
- #13/#24 evolution rule: readers ignore unknown fields and unknown enum
  values; the CLI removes nothing within a schemaVersion.
- #19 ordering: mDNS entries first (scan order), then local-probe entries by
  port; documented.
- #21/#23/#29/#33/#35/#36 documented: versions may differ; prefer stdio;
  `--tools` is for an integrator's initial catalog cache; duplicate ids are
  preserved; HTTP port conflicts → use stdio; poll no faster than ~5s.

**Rejected (push back):**
- #1 `cli.path` "leaks username" — the brief *requires* the absolute path of
  the answering binary, and the document is produced for the local executor
  daemon, which already enforces "host paths never leave the machine"
  (Nessie invariant #1). Kept; the forwarding caveat goes in the report.
- #2 `ip` vs `address` — misread: the token lookup runs on the internal
  `DiscoveredDevice` (`ip`) before the output mapping to `address`. No defect;
  docs make the mapping explicit.
- #3 export `DescribeDocumentSchema` from Nessie's `packages/schemas` — that
  repo is not mine to edit (the brief forbids it). Instead the grammar is a
  zod schema inside the CLI package, used by tests to validate real output;
  noted for the orchestrator.
- #16 raise default timeout — kept 3000 ms for consistency with
  `kelpie discover`; the flag exists for callers that want longer.
- #17 non-zero exit on mDNS failure — the brief mandates exit 0 whenever a
  document is produced; `discovery.mdns` carries the distinction.
- #25 `mdns` too coarse — misread: `ok`+empty devices vs `unavailable`
  already distinguishes the cases.
- #27 pin zod — the digest tracks the wire catalog; a serializer change *is*
  a catalog change. `digestAlgorithm` bumps if the recipe changes.
- #31 hash-of-token check — tokens never enter the digest input; the canary
  test is sufficient.
- #32 binary checksum — out of scope for a detection contract.

**Partially accepted:**
- #5 loopback/mDNS double-report: reliable dedupe is impossible (the local
  probe's synthetic `local:` id never equals the mDNS device id). Both
  observations are reported; docs state a loopback entry may duplicate a LAN
  entry for one instance and consumers key on `address:port`.
- #34 added a multiple-devices test; skipped concurrency testing (each
  invocation is its own process).

**Found during review (reported, not changed):** `mcp/server.ts` hardcodes
server version `"0.1.0"` while the CLI is at 0.1.11 — the `serverVersion`
Nessie reads from a handshake is stale. Out of minimal scope here; flagged
for the orchestrator.
