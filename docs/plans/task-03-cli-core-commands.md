# Task 03: CLI Core Commands — Navigation, Screenshots, DOM

**Component:** CLI
**Depends on:** Task 02
**Estimated size:** ~400 lines

## Goal

Implement the core browser automation commands: navigation, screenshots (with file-save behavior), and DOM access.

## Files to Create

```
packages/cli/src/commands/
  navigate.ts                 # navigate, back, forward, reload, url
  screenshot.ts               # screenshot (file save + base64 modes)
  dom.ts                      # dom, query, text, attributes
```

```
packages/cli/tests/commands/
  navigate.test.ts
  screenshot.test.ts
  dom.test.ts
```

## Commands

### Navigation (`navigate.ts`)

| Command | API Method | Args |
|---------|-----------|------|
| `mollotov navigate <url>` | `navigate` | url (positional) |
| `mollotov back` | `back` | — |
| `mollotov forward` | `forward` | — |
| `mollotov reload` | `reload` | — |
| `mollotov url` | `get-current-url` | — |

All require `--device`. Return JSON response from browser.

### Screenshots (`screenshot.ts`)

| Command | API Method | Flags |
|---------|-----------|-------|
| `mollotov screenshot` | `screenshot` | `--output`, `--full-page`, `--base64`, `--format` |

**File-save behavior (critical — read docs/cli.md):**
- Default: auto-save to `./{device}-{timestamp}.png`, return `{"file": "path"}`
- `--output <path>`: save to explicit path
- `--output <dir>/`: save to directory with auto-generated filename
- `--base64`: return raw base64 JSON (no file save)

Implementation:
1. Send `screenshot` request to device
2. Receive base64 image in response
3. Unless `--base64`, decode and write to file
4. Return file path in JSON output

### DOM (`dom.ts`)

| Command | API Method | Args/Flags |
|---------|-----------|------------|
| `mollotov dom` | `get-dom` | `--selector`, `--depth` |
| `mollotov query <selector>` | `query-selector` / `query-selector-all` | selector (positional), `--all` |
| `mollotov text <selector>` | `get-element-text` | selector (positional) |
| `mollotov attributes <selector>` | `get-attributes` | selector (positional) |

## Tests

- Navigation: mock HTTP responses, verify correct API method called, URL passed
- Screenshot: mock HTTP response with base64 image, verify file write behavior for all modes
- DOM: mock responses, verify selector passed correctly, `--all` toggles between querySelector/querySelectorAll

## Acceptance Criteria

- [ ] All 5 navigation commands work with `--device` targeting
- [ ] `screenshot` saves to file by default (verify file exists on disk)
- [ ] `screenshot --base64` returns base64 JSON without writing a file
- [ ] `screenshot --output ./test.png` saves to specified path
- [ ] `screenshot --full-page` sends `fullPage: true` to API
- [ ] Auto-generated screenshot filenames follow `{device}-{timestamp}.png` pattern
- [ ] `dom --selector "main" --depth 3` passes params correctly
- [ ] `query <selector>` returns single element; `query <selector> --all` returns array
- [ ] `text` and `attributes` pass selector and return correct shape
- [ ] All tests pass

---

- [ ] **Have you run an adversarial review with Codex?**
