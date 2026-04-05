# Task 02: CLI Foundation — Discovery + HTTP Client + Entry Point

**Component:** CLI
**Depends on:** Task 01
**Estimated size:** ~500 lines

## Goal

Build the CLI skeleton: Commander.js entry point with global options, mDNS device discovery, device registry, HTTP client for talking to browsers, and the three discovery commands (`discover`, `devices`, `ping`).

## Files to Create/Modify

```
packages/cli/
  src/
    index.ts                    # Commander program setup, global options
    discovery/
      scanner.ts                # mDNS browser using bonjour-service
      registry.ts               # In-memory device registry with health tracking
    client/
      http-client.ts            # HTTP client wrapping native fetch
    commands/
      discover.ts               # kelpie discover
      devices.ts                # kelpie devices
      ping.ts                   # kelpie ping
    output/
      formatter.ts              # JSON/table/text output formatting
    types.ts                    # CLI-internal types (DiscoveredDevice, etc.)
  bin/
    kelpie.ts                 # CLI entry point (shebang + import)
  tests/
    discovery/
      scanner.test.ts
      registry.test.ts
    client/
      http-client.test.ts
    commands/
      discover.test.ts
```

## Steps

### 1. Install dependencies

```bash
cd packages/cli
pnpm add commander bonjour-service chalk cli-table3
pnpm add -D vitest @types/node typescript tsup
```

### 2. CLI entry point (`src/index.ts`)

Commander program with:
- `--device <id|name|ip>` global option
- `--format <json|table|text>` global option (default: `json`)
- `--timeout <ms>` global option (default: `10000`)
- `--port <port>` global option (default: `8420`)
- `--version` from package.json
- `--llm-help` flag (stub for Task 09)

### 3. mDNS Scanner (`discovery/scanner.ts`)

- Uses `bonjour-service` to browse for `_kelpie._tcp`
- Scans for a configurable duration (default 3 seconds)
- Parses TXT records into `MdnsTxtRecord` type from shared
- Returns array of discovered devices
- Handles errors gracefully (no network, no mDNS responder)

### 4. Device Registry (`discovery/registry.ts`)

- Singleton in-memory store of known devices
- `addDevice()`, `removeDevice()`, `getDevice(idOrNameOrIp)`, `getAllDevices()`
- Fuzzy name matching for `--device` targeting
- Device ID exact match > name match > IP match priority
- `refreshAll()` — pings all known devices, removes unreachable

### 5. HTTP Client (`client/http-client.ts`)

- `sendCommand(device, method, body?)` → JSON response
- Builds URL: `http://{ip}:{port}/v1/{method}`
- Method name conversion: camelCase → kebab-case (e.g., `getDOM` → `get-dom`)
- Timeout handling via AbortController
- Error wrapping: network errors → structured error response
- Returns typed responses using shared types

### 6. Output formatter (`output/formatter.ts`)

- `formatOutput(data, format)` — JSON pretty-print, table, or plain text
- Table mode uses cli-table3 for device lists
- All commands pipe through this before printing

### 7. Discovery commands

**`discover`** — Runs mDNS scan, populates registry, formats output.
**`devices`** — Lists registry contents. `--refresh` flag triggers re-scan first.
**`ping`** — Sends `GET /v1/get-device-info` to one or all devices, reports reachable/unreachable.

### 8. Tests

- Scanner: mock bonjour-service, verify TXT record parsing
- Registry: add/remove/get devices, fuzzy matching, priority resolution
- HTTP client: mock fetch, verify URL construction, timeout, error handling
- Discover command: integration test with mocked scanner

### 9. Commit

```bash
git add -A && git commit -m "feat: CLI foundation — discovery, HTTP client, entry point"
```

## Acceptance Criteria

- [ ] `kelpie --version` prints the version from package.json
- [ ] `kelpie --help` shows all global options and available commands
- [ ] `kelpie discover` scans mDNS and returns JSON with device list (test with mock)
- [ ] `kelpie devices` returns cached device list
- [ ] `kelpie ping --device <name>` sends HTTP request and reports status
- [ ] `--device` resolves by ID (exact), name (fuzzy), or IP
- [ ] `--format table` renders a readable table
- [ ] `--timeout` is respected by HTTP client
- [ ] HTTP client correctly builds `/v1/{method}` URLs
- [ ] All tests pass: `pnpm test` in cli package
- [ ] No runtime dependencies beyond: commander, bonjour-service, chalk, cli-table3

---

- [ ] **Have you run an adversarial review with Codex?**
