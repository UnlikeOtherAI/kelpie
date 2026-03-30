# Task 05: CLI DevTools + Browser Management Commands

**Component:** CLI
**Depends on:** Task 02
**Estimated size:** ~500 lines

## Goal

Implement all DevTools commands (console, network, mutations, shadow DOM, request interception) and browser management commands (dialogs, tabs, iframes, cookies, storage, clipboard, geolocation, keyboard, viewport resize).

## Files to Create

```
packages/cli/src/commands/
  console.ts                  # console, errors, clear-console
  network.ts                  # network, timeline
  mutations.ts                # mutations watch/get/stop
  intercept.ts                # intercept block/mock/list/clear
  shadow-dom.ts               # shadow-roots, shadow-query
  dialog.ts                   # dialog, dialog accept/dismiss, dialog auto
  tabs.ts                     # tabs, tab new/switch/close
  iframes.ts                  # iframes, iframe enter/exit/context
  cookies.ts                  # cookies, cookies set, cookies delete
  storage.ts                  # storage, storage set, storage clear
  clipboard.ts                # clipboard, clipboard set
  geo.ts                      # geo set, geo clear
  keyboard.ts                 # keyboard show/hide/state, resize, resize reset, obscured
```

```
packages/cli/tests/commands/
  devtools.test.ts            # console, network, mutations, intercept, shadow-dom
  browser-mgmt.test.ts        # dialog, tabs, iframes, cookies, storage, clipboard, geo, keyboard
```

## Commands

### Console & DevTools

| Command | API Method |
|---------|-----------|
| `mollotov console` | `get-console-messages` |
| `mollotov console --level error` | `get-console-messages` (filtered) |
| `mollotov errors` | `get-js-errors` |
| `mollotov clear-console` | `clear-console` |
| `mollotov network` | `get-network-log` |
| `mollotov network --type fetch --status error` | `get-network-log` (filtered) |
| `mollotov timeline` | `get-resource-timeline` |

### Mutations (subcommands)

| Command | API Method |
|---------|-----------|
| `mollotov mutations watch` | `watch-mutations` |
| `mollotov mutations watch --selector "main"` | `watch-mutations` (scoped) |
| `mollotov mutations get` | `get-mutations` |
| `mollotov mutations stop` | `stop-watching` |

### Request Interception (subcommands)

| Command | API Method |
|---------|-----------|
| `mollotov intercept block <pattern>` | `set-request-interception` |
| `mollotov intercept mock <url> --body <json>` | `set-request-interception` |
| `mollotov intercept list` | `get-intercepted-requests` |
| `mollotov intercept clear` | `clear-request-interception` |

### Shadow DOM

| Command | API Method |
|---------|-----------|
| `mollotov shadow-roots` | `get-shadow-roots` |
| `mollotov shadow-query <host> <selector>` | `query-shadow-dom` |

### Dialog (subcommands)

| Command | API Method |
|---------|-----------|
| `mollotov dialog` | `get-dialog` |
| `mollotov dialog accept` | `handle-dialog` |
| `mollotov dialog dismiss` | `handle-dialog` |
| `mollotov dialog auto --action accept` | `set-dialog-auto-handler` |

### Tabs (subcommands)

| Command | API Method |
|---------|-----------|
| `mollotov tabs` | `get-tabs` |
| `mollotov tab new [url]` | `new-tab` |
| `mollotov tab switch <id>` | `switch-tab` |
| `mollotov tab close <id>` | `close-tab` |

### Iframes (subcommands)

| Command | API Method |
|---------|-----------|
| `mollotov iframes` | `get-iframes` |
| `mollotov iframe enter <id\|selector>` | `switch-to-iframe` |
| `mollotov iframe exit` | `switch-to-main` |
| `mollotov iframe context` | `get-iframe-context` |

### Cookies & Storage

| Command | API Method |
|---------|-----------|
| `mollotov cookies` | `get-cookies` |
| `mollotov cookies set <name> <value>` | `set-cookie` |
| `mollotov cookies delete` | `delete-cookies` |
| `mollotov storage` | `get-storage` |
| `mollotov storage set <key> <value>` | `set-storage` |
| `mollotov storage clear` | `clear-storage` |

### Clipboard, Geo, Keyboard, Viewport

| Command | API Method |
|---------|-----------|
| `mollotov clipboard` | `get-clipboard` |
| `mollotov clipboard set <text>` | `set-clipboard` |
| `mollotov geo set <lat> <lng>` | `set-geolocation` |
| `mollotov geo clear` | `clear-geolocation` |
| `mollotov keyboard show` | `show-keyboard` |
| `mollotov keyboard hide` | `hide-keyboard` |
| `mollotov keyboard state` | `get-keyboard-state` |
| `mollotov resize <width> <height>` | `resize-viewport` |
| `mollotov resize reset` | `reset-viewport` |
| `mollotov obscured <selector>` | `is-element-obscured` |

## Tests

Test each command group sends the correct API method and parameters. Use mocked HTTP responses.

## Acceptance Criteria

- [ ] `console --level warn --limit 50` passes filters to API
- [ ] `errors` calls `get-js-errors` endpoint
- [ ] `network --type fetch --status error` passes both filters
- [ ] `mutations watch/get/stop` lifecycle works correctly
- [ ] `intercept block/mock/list/clear` subcommands all work
- [ ] `dialog accept --prompt-text "input"` passes prompt text
- [ ] `dialog auto --action queue` sets queue mode
- [ ] `tab new/switch/close` pass correct IDs
- [ ] `iframe enter` accepts both numeric ID and CSS selector
- [ ] `cookies set` with `--domain --path --secure` flags work
- [ ] `storage --type session` passes type parameter
- [ ] `geo set` parses lat/lng as numbers
- [ ] `keyboard show --selector "#email" --type number` passes all params
- [ ] `resize` and `resize reset` send correct viewport dimensions
- [ ] All tests pass

---

- [ ] **Have you run an adversarial review with Codex?**
