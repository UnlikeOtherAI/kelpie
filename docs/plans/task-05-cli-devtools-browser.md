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
| `kelpie console` | `get-console-messages` |
| `kelpie console --level error` | `get-console-messages` (filtered) |
| `kelpie errors` | `get-js-errors` |
| `kelpie clear-console` | `clear-console` |
| `kelpie network` | `get-network-log` |
| `kelpie network --type fetch --status error` | `get-network-log` (filtered) |
| `kelpie timeline` | `get-resource-timeline` |

### Mutations (subcommands)

| Command | API Method |
|---------|-----------|
| `kelpie mutations watch` | `watch-mutations` |
| `kelpie mutations watch --selector "main"` | `watch-mutations` (scoped) |
| `kelpie mutations get` | `get-mutations` |
| `kelpie mutations stop` | `stop-watching` |

### Request Interception (subcommands)

| Command | API Method |
|---------|-----------|
| `kelpie intercept block <pattern>` | `set-request-interception` |
| `kelpie intercept mock <url> --body <json>` | `set-request-interception` |
| `kelpie intercept list` | `get-intercepted-requests` |
| `kelpie intercept clear` | `clear-request-interception` |

### Shadow DOM

| Command | API Method |
|---------|-----------|
| `kelpie shadow-roots` | `get-shadow-roots` |
| `kelpie shadow-query <host> <selector>` | `query-shadow-dom` |

### Dialog (subcommands)

| Command | API Method |
|---------|-----------|
| `kelpie dialog` | `get-dialog` |
| `kelpie dialog accept` | `handle-dialog` |
| `kelpie dialog dismiss` | `handle-dialog` |
| `kelpie dialog auto --action accept` | `set-dialog-auto-handler` |

### Tabs (subcommands)

| Command | API Method |
|---------|-----------|
| `kelpie tabs` | `get-tabs` |
| `kelpie tab new [url]` | `new-tab` |
| `kelpie tab switch <id>` | `switch-tab` |
| `kelpie tab close <id>` | `close-tab` |

### Iframes (subcommands)

| Command | API Method |
|---------|-----------|
| `kelpie iframes` | `get-iframes` |
| `kelpie iframe enter <id\|selector>` | `switch-to-iframe` |
| `kelpie iframe exit` | `switch-to-main` |
| `kelpie iframe context` | `get-iframe-context` |

### Cookies & Storage

| Command | API Method |
|---------|-----------|
| `kelpie cookies` | `get-cookies` |
| `kelpie cookies set <name> <value>` | `set-cookie` |
| `kelpie cookies delete` | `delete-cookies` |
| `kelpie storage` | `get-storage` |
| `kelpie storage set <key> <value>` | `set-storage` |
| `kelpie storage clear` | `clear-storage` |

### Clipboard, Geo, Keyboard, Viewport

| Command | API Method |
|---------|-----------|
| `kelpie clipboard` | `get-clipboard` |
| `kelpie clipboard set <text>` | `set-clipboard` |
| `kelpie geo set <lat> <lng>` | `set-geolocation` |
| `kelpie geo clear` | `clear-geolocation` |
| `kelpie keyboard show` | `show-keyboard` |
| `kelpie keyboard hide` | `hide-keyboard` |
| `kelpie keyboard state` | `get-keyboard-state` |
| `kelpie resize <width> <height>` | `resize-viewport` |
| `kelpie resize reset` | `reset-viewport` |
| `kelpie obscured <selector>` | `is-element-obscured` |

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
