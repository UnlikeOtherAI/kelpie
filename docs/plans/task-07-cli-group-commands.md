# Task 07: CLI Group Commands

**Component:** CLI
**Depends on:** Tasks 03, 04, 05, 06
**Estimated size:** ~500 lines

## Goal

Build the group command orchestration engine that broadcasts commands to multiple devices in parallel, collects results, and returns aggregated responses. Includes filtering and smart query group variants.

## Files to Create

```
packages/cli/src/
  group/
    orchestrator.ts           # Core engine: fan-out, collect, aggregate
    filter.ts                 # --platform, --include, --exclude filtering
    smart-response.ts         # found/notFound aggregation for smart queries
  commands/
    group.ts                  # mollotov group <command> [args]
```

```
packages/cli/tests/
  group/
    orchestrator.test.ts
    filter.test.ts
  commands/
    group.test.ts
```

## Architecture

### Orchestrator (`group/orchestrator.ts`)

```typescript
async function executeGroup(
  devices: Device[],
  method: string,
  body: Record<string, unknown>,
  options: { concurrency?: number }
): Promise<GroupResult>
```

- Takes filtered device list + API method + body
- Sends HTTP requests to all devices in parallel (Promise.allSettled)
- Collects per-device results (success or error)
- Returns `GroupResult` with `results[]`, `succeeded`, `failed` counts
- Exit code: 0 if all succeeded, 1 if any failed

### Filter (`group/filter.ts`)

Applies CLI flags to device list:
- `--platform ios|android` — filter by platform
- `--include "id1,name2"` — only these devices (by ID or name)
- `--exclude "name"` — exclude specific device
- When both `--include` and `--platform` specified, intersection

### Smart Response (`group/smart-response.ts`)

For query commands (findButton, findElement, etc.):
- Separates results into `found[]` and `notFound[]`
- `found` entries include device metadata + element data
- `notFound` entries include device metadata + reason

### Group Command (`commands/group.ts`)

`mollotov group <command> [args]` — routes to the appropriate individual command handler but through the orchestrator.

Supported group commands (from docs/api/README.md):

| Group Command | Individual API Method |
|---|---|
| `group navigate <url>` | `navigate` |
| `group screenshot` | `screenshot` (saves one file per device) |
| `group fill <selector> <value>` | `fill` |
| `group click <selector>` | `click` |
| `group scroll2 <selector>` | `scroll2` |
| `group find-button <text>` | `find-button` (smart response) |
| `group find-element <text>` | `find-element` (smart response) |
| `group find-link <text>` | `find-link` (smart response) |
| `group find-input <label>` | `find-input` (smart response) |
| `group a11y` | `get-accessibility-tree` |
| `group dom` | `get-dom` |
| `group eval <expr>` | `evaluate` |
| `group console` | `get-console-messages` |
| `group errors` | `get-js-errors` |
| `group form-state` | `get-form-state` |
| `group visible` | `get-visible-elements` |
| `group keyboard show/hide` | `show-keyboard` / `hide-keyboard` |

Group screenshots: `--output <dir>/` saves one file per device with device name in filename.

## Tests

- Orchestrator: mock multiple devices, verify parallel execution, result aggregation
- Filter: test platform/include/exclude combinations
- Smart response: verify found/notFound partitioning
- Group screenshot: verify one file per device saved

## Acceptance Criteria

- [ ] `group navigate "https://example.com"` sends to all discovered devices
- [ ] `group screenshot --output ./screenshots/` saves one file per device
- [ ] `group find-button "Submit"` returns `found[]` and `notFound[]` arrays
- [ ] `--platform ios` filters to iOS devices only
- [ ] `--include "device1,device2"` targets only named devices
- [ ] `--exclude "iPad"` removes device from target list
- [ ] `--include` + `--platform` uses intersection
- [ ] Partial failure: some devices succeed, some fail → exit code 1, all results reported
- [ ] Response includes `deviceCount`, `succeeded`, `failed` counts
- [ ] Per-device results include device metadata (name, platform, resolution)
- [ ] All tests pass

---

- [ ] **Have you run an adversarial review with Codex?**
