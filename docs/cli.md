# Mollotov — CLI Reference

## Installation

```bash
npm install -g @unlike-other-ai/mollotov
# or
pnpm add -g @unlike-other-ai/mollotov
```

## Usage

```
mollotov <command> [options]
```

---

## Global Options

| Flag | Description |
|---|---|
| `--device <id\|name\|ip>` | Target a specific device by ID (most reliable), name, or IP |
| `--format <type>` | Output format: `json` (default), `table`, `text` |
| `--timeout <ms>` | CLI-level command timeout in milliseconds (default: 10000). Overrides per-method API defaults (typically 5000ms). |
| `--port <port>` | Override default port 8420 |
| `--help` | Show help for any command |
| `--version` | Show CLI version |
| `--llm-help` | Show detailed LLM-oriented help with schemas and examples |

---

## Discovery Commands

### `mollotov discover`
Scan the local network for Mollotov browser instances.

```bash
mollotov discover
mollotov discover --timeout 5000    # custom scan duration
```

**Output:**
```json
{
  "devices": [
    {
      "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      "name": "My iPhone",
      "ip": "192.168.1.42",
      "port": 8420,
      "platform": "ios",
      "model": "iPhone 15 Pro",
      "resolution": "390x844",
      "version": "1.0.0"
    }
  ],
  "count": 1
}
```

### `mollotov devices`
List previously discovered devices (cached from last scan).

```bash
mollotov devices
mollotov devices --refresh         # force re-scan before listing
```

### `mollotov ping [device]`
Check if a device is reachable. Without `--device`, pings all known devices.

```bash
mollotov ping --device "My iPhone"
mollotov ping                       # ping all
```

---

## Navigation Commands

### `mollotov navigate <url>`

```bash
mollotov navigate "https://example.com" --device "My iPhone"
```

### `mollotov back` / `mollotov forward` / `mollotov reload`

```bash
mollotov back --device "My iPhone"
mollotov forward --device "My iPhone"
mollotov reload --device "My iPhone"
```

### `mollotov url`
Get current URL and title.

```bash
mollotov url --device "My iPhone"
```

---

## Screenshot Commands

### `mollotov screenshot`

```bash
mollotov screenshot --device "My iPhone"
mollotov screenshot --device "My iPhone" --output ./shot.png
mollotov screenshot --device "My iPhone" --full-page
```

Without `--output`, returns base64 JSON. With `--output`, saves to file.

---

## DOM Commands

### `mollotov dom`
Get the DOM tree.

```bash
mollotov dom --device "My iPhone"
mollotov dom --device "My iPhone" --selector "main" --depth 3
```

### `mollotov query <selector>`
Query for elements.

```bash
mollotov query "#submit-btn" --device "My iPhone"
mollotov query "a.nav-link" --device "My iPhone" --all
```

### `mollotov text <selector>`
Get text content of an element.

```bash
mollotov text "h1" --device "My iPhone"
```

### `mollotov attributes <selector>`
Get all attributes of an element.

```bash
mollotov attributes "#email-input" --device "My iPhone"
```

---

## Interaction Commands

### `mollotov click <selector>`

```bash
mollotov click "#submit-btn" --device "My iPhone"
```

### `mollotov tap <x> <y>`

```bash
mollotov tap 195 420 --device "My iPhone"
```

### `mollotov fill <selector> <value>`

```bash
mollotov fill "#email" "user@example.com" --device "My iPhone"
```

### `mollotov type <text>`

```bash
mollotov type "search query" --device "My iPhone"
mollotov type "search query" --device "My iPhone" --selector "#search-box"
mollotov type "search query" --device "My iPhone" --delay 50
```

### `mollotov select <selector> <value>`

```bash
mollotov select "#country" "us" --device "My iPhone"
```

### `mollotov check <selector>` / `mollotov uncheck <selector>`

```bash
mollotov check "#agree-terms" --device "My iPhone"
```

---

## Scroll Commands

### `mollotov scroll`

```bash
mollotov scroll --device "My iPhone" --y 500
mollotov scroll --device "My iPhone" --x 200 --y 0
```

### `mollotov scroll2 <selector>`
Resolution-aware scroll to element.

```bash
mollotov scroll2 "#footer" --device "My iPhone"
mollotov scroll2 "#footer" --device "My iPhone" --position center
```

### `mollotov scroll-top` / `mollotov scroll-bottom`

```bash
mollotov scroll-top --device "My iPhone"
mollotov scroll-bottom --device "My iPhone"
```

---

## Console & DevTools Commands

### `mollotov console`
Get console messages from the page.

```bash
mollotov console --device "My iPhone"
mollotov console --device "My iPhone" --level error     # errors only
mollotov console --device "My iPhone" --level warn      # warnings only
mollotov console --device "My iPhone" --limit 50
```

### `mollotov errors`
Get JavaScript errors (shorthand for `console --level error`).

```bash
mollotov errors --device "My iPhone"
```

### `mollotov network`
Get the network activity log — all resources loaded by the page.

```bash
mollotov network --device "My iPhone"
mollotov network --device "My iPhone" --type script     # only JS files
mollotov network --device "My iPhone" --type fetch      # only XHR/fetch
mollotov network --device "My iPhone" --status error    # only failed requests
```

### `mollotov timeline`
Get the resource loading timeline with timing data.

```bash
mollotov timeline --device "My iPhone"
```

### `mollotov clear-console`
Clear the console message buffer.

```bash
mollotov clear-console --device "My iPhone"
```

### `mollotov mutations`
Watch and get DOM mutations.

```bash
mollotov mutations watch --device "My iPhone"                    # start watching
mollotov mutations watch --device "My iPhone" --selector "main"  # scoped
mollotov mutations get --device "My iPhone"                      # get accumulated mutations
mollotov mutations stop --device "My iPhone"                     # stop watching
```

### `mollotov intercept`
Manage request interception rules.

```bash
mollotov intercept block "*.doubleclick.net/*" --device "My iPhone"
mollotov intercept mock "https://api.example.com/data" --body '{"items":[]}' --device "My iPhone"
mollotov intercept list --device "My iPhone"
mollotov intercept clear --device "My iPhone"
```

---

## LLM-Optimized Commands

### `mollotov a11y`
Get the accessibility tree — the most LLM-friendly representation of the page.

```bash
mollotov a11y --device "My iPhone"
mollotov a11y --device "My iPhone" --interactable-only
mollotov a11y --device "My iPhone" --selector "main"
```

### `mollotov annotate`
Take an annotated screenshot with numbered labels on interactive elements.

```bash
mollotov annotate --device "My iPhone"
mollotov annotate --device "My iPhone" --output ./annotated.png
mollotov annotate --device "My iPhone" --full-page
```

### `mollotov click-index <index>`
Click an element by its annotation index from the last `annotate` call.

```bash
mollotov click-index 5 --device "My iPhone"
```

### `mollotov fill-index <index> <value>`
Fill an element by its annotation index.

```bash
mollotov fill-index 2 "user@example.com" --device "My iPhone"
```

### `mollotov visible`
Get only the elements currently visible in the viewport.

```bash
mollotov visible --device "My iPhone"
mollotov visible --device "My iPhone" --interactable-only
```

### `mollotov page-text`
Extract readable text from the page (reader mode).

```bash
mollotov page-text --device "My iPhone"
mollotov page-text --device "My iPhone" --mode markdown
mollotov page-text --device "My iPhone" --mode full
mollotov page-text --device "My iPhone" --selector "article"
```

### `mollotov form-state`
Get the state of all forms on the page.

```bash
mollotov form-state --device "My iPhone"
mollotov form-state --device "My iPhone" --selector "#signup-form"
```

---

## Dialog & Alert Commands

### `mollotov dialog`
Check if a dialog is showing.

```bash
mollotov dialog --device "My iPhone"
```

### `mollotov dialog accept` / `mollotov dialog dismiss`
Handle the current dialog.

```bash
mollotov dialog accept --device "My iPhone"
mollotov dialog dismiss --device "My iPhone"
mollotov dialog accept --device "My iPhone" --prompt-text "my input"
```

### `mollotov dialog auto`
Configure automatic dialog handling.

```bash
mollotov dialog auto --action accept --device "My iPhone"
mollotov dialog auto --action dismiss --device "My iPhone"
mollotov dialog auto --action queue --device "My iPhone"     # capture for later
mollotov dialog auto --off --device "My iPhone"              # disable
```

---

## Tab Commands

### `mollotov tabs`
List all open tabs.

```bash
mollotov tabs --device "My iPhone"
```

### `mollotov tab new [url]`
Open a new tab.

```bash
mollotov tab new "https://example.com" --device "My iPhone"
mollotov tab new --device "My iPhone"                         # blank tab
```

### `mollotov tab switch <id>`
Switch to a tab.

```bash
mollotov tab switch 1 --device "My iPhone"
```

### `mollotov tab close <id>`
Close a tab.

```bash
mollotov tab close 1 --device "My iPhone"
```

---

## Iframe Commands

### `mollotov iframes`
List all iframes on the page.

```bash
mollotov iframes --device "My iPhone"
```

### `mollotov iframe enter <id|selector>`
Switch command context into an iframe.

```bash
mollotov iframe enter 0 --device "My iPhone"
mollotov iframe enter "iframe[name='payment']" --device "My iPhone"
```

### `mollotov iframe exit`
Switch back to the main page context.

```bash
mollotov iframe exit --device "My iPhone"
```

### `mollotov iframe context`
Check which context (main page or iframe) commands are currently targeting.

```bash
mollotov iframe context --device "My iPhone"
```

---

## Cookie & Storage Commands

### `mollotov cookies`
Get cookies for the current page.

```bash
mollotov cookies --device "My iPhone"
mollotov cookies --device "My iPhone" --name "session_id"
```

### `mollotov cookies set <name> <value>`
Set a cookie.

```bash
mollotov cookies set "session_id" "abc123" --device "My iPhone"
mollotov cookies set "theme" "dark" --device "My iPhone" --domain "example.com" --path "/" --secure
```

### `mollotov cookies delete`
Delete cookies.

```bash
mollotov cookies delete --name "session_id" --device "My iPhone"
mollotov cookies delete --domain "example.com" --device "My iPhone"
mollotov cookies delete --all --device "My iPhone"
```

### `mollotov storage`
Read localStorage or sessionStorage.

```bash
mollotov storage --device "My iPhone"                          # localStorage (default)
mollotov storage --device "My iPhone" --type session
mollotov storage --device "My iPhone" --key "auth_token"
```

### `mollotov storage set <key> <value>`
Write to storage.

```bash
mollotov storage set "theme" "dark" --device "My iPhone"
mollotov storage set "theme" "dark" --device "My iPhone" --type session
```

### `mollotov storage clear`
Clear storage.

```bash
mollotov storage clear --device "My iPhone"
mollotov storage clear --device "My iPhone" --type session
mollotov storage clear --device "My iPhone" --type both
```

---

## Clipboard Commands

### `mollotov clipboard`
Read clipboard contents.

```bash
mollotov clipboard --device "My iPhone"
```

### `mollotov clipboard set <text>`
Write to clipboard.

```bash
mollotov clipboard set "text to copy" --device "My iPhone"
```

---

## Geolocation Commands

### `mollotov geo set <lat> <lng>`
Override geolocation.

```bash
mollotov geo set 37.7749 -122.4194 --device "My iPhone"
mollotov geo set 37.7749 -122.4194 --device "My iPhone" --accuracy 10
```

### `mollotov geo clear`
Remove geolocation override.

```bash
mollotov geo clear --device "My iPhone"
```

---

## Shadow DOM Commands

### `mollotov shadow-roots`
List all shadow DOM hosts on the page.

```bash
mollotov shadow-roots --device "My iPhone"
```

### `mollotov shadow-query <host> <selector>`
Query elements inside a shadow root.

```bash
mollotov shadow-query "my-component" ".inner-button" --device "My iPhone"
mollotov shadow-query "my-component" ".inner-button" --device "My iPhone" --pierce
```

---

## Keyboard & Viewport Commands

### `mollotov keyboard show`
Show the soft keyboard by focusing an element.

```bash
mollotov keyboard show --device "My iPhone"
mollotov keyboard show --device "My iPhone" --selector "#email"
mollotov keyboard show --device "My iPhone" --type number
```

### `mollotov keyboard hide`
Dismiss the soft keyboard.

```bash
mollotov keyboard hide --device "My iPhone"
```

### `mollotov keyboard state`
Check keyboard visibility and viewport impact.

```bash
mollotov keyboard state --device "My iPhone"
```

### `mollotov resize <width> <height>`
Simulate a reduced viewport (e.g., keyboard present, toolbar visible).

```bash
mollotov resize 390 500 --device "My iPhone"
```

### `mollotov resize reset`
Restore full-screen viewport.

```bash
mollotov resize reset --device "My iPhone"
```

### `mollotov obscured <selector>`
Check if an element is hidden by the keyboard or outside the visible viewport.

```bash
mollotov obscured "#password-input" --device "My iPhone"
```

---

## Wait Commands

### `mollotov wait <selector>`

```bash
mollotov wait ".results-loaded" --device "My iPhone"
mollotov wait ".results-loaded" --device "My iPhone" --timeout 15000
mollotov wait ".spinner" --device "My iPhone" --state hidden
```

### `mollotov wait-nav`
Wait for a navigation event to complete.

```bash
mollotov wait-nav --device "My iPhone"
mollotov wait-nav --device "My iPhone" --timeout 15000
```

---

## Evaluate

### `mollotov eval <expression>`

```bash
mollotov eval "document.title" --device "My iPhone"
mollotov eval "window.innerHeight" --device "My iPhone"
```

---

## Device Info

### `mollotov info [device]`
Get full device information.

```bash
mollotov info --device "My iPhone"
mollotov info                         # info for all devices
```

### `mollotov viewport [device]`
Get viewport dimensions.

```bash
mollotov viewport --device "My iPhone"
```

---

## Group Commands

All group commands target every discovered device unless filtered.

### `mollotov group <command> [args]`

```bash
mollotov group navigate "https://example.com"
mollotov group screenshot --output ./screenshots/
mollotov group fill "#email" "test@example.com"
mollotov group click "#submit"
mollotov group scroll2 "#footer"
```

### `mollotov group find-button <text>`
Find a button on all devices. Returns which devices found it and which didn't.

```bash
mollotov group find-button "Submit"
```

**Output:**
```json
{
  "found": [
    {"device": "My iPhone", "element": {"tag": "button", "text": "Submit"}},
    {"device": "Pixel 8", "element": {"tag": "button", "text": "Submit"}}
  ],
  "notFound": [
    {"device": "iPad Air", "reason": "Element not found"}
  ]
}
```

### `mollotov group find-element <text>`

```bash
mollotov group find-element "Sign Up" --role link
```

### `mollotov group find-link <text>`

```bash
mollotov group find-link "Sign Up"
```

### `mollotov group find-input <label>`

```bash
mollotov group find-input "Email"
```

### Group Filtering

```bash
mollotov group navigate "https://example.com" --platform ios       # only iOS devices
mollotov group navigate "https://example.com" --platform android   # only Android
mollotov group navigate "https://example.com" --exclude "iPad Air" # exclude specific device
mollotov group navigate "https://example.com" --include "a1b2c3d4,My iPhone" # only these devices (by ID or name)
```

`--include` accepts a comma-separated list of device IDs or names. When both `--include` and `--platform` are specified, only devices matching both filters are targeted.

---

## MCP Server

### `mollotov mcp`
Start the CLI as an MCP server (stdio transport).

```bash
mollotov mcp
```

Configure in Claude Desktop / Claude Code:
```json
{
  "mcpServers": {
    "mollotov": {
      "command": "mollotov",
      "args": ["mcp"]
    }
  }
}
```

### `mollotov mcp --http`
Start the MCP server with HTTP transport.

```bash
mollotov mcp --http --port 8421
```

---

## LLM Help System

Every command includes structured help designed for LLMs.

### `mollotov --llm-help`
Outputs a complete machine-readable reference of all commands, their parameters, expected inputs/outputs, and usage guidance.

```bash
mollotov --llm-help                   # full reference
mollotov click --llm-help             # help for specific command
mollotov group --llm-help             # help for group commands
```

**LLM help includes:**
- Command purpose and when to use it
- Full parameter schema with types and defaults
- Example request/response pairs
- Common error scenarios and how to handle them
- Related commands and suggested workflows

### `mollotov explain <command>`
Natural language explanation of a command for LLM consumption.

```bash
mollotov explain scroll2
```

**Output:**
```
scroll2 scrolls the page until a target element is visible in the viewport.
Unlike regular scroll, it adapts the scroll distance to the device's screen
size — a phone needs more scroll steps than a tablet to reach the same element.

Use scroll2 when you need to interact with an element that's below the fold.
It will automatically verify the element is visible after scrolling.

Parameters:
  selector (required) — CSS selector of the target element
  position (optional) — where in viewport: "top", "center" (default), "bottom"
  maxScrolls (optional) — safety limit, default 10

Returns: element position, whether it's visible, number of scrolls performed
```

---

## Exit Codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Command error (invalid params, element not found) |
| 2 | Network error (device unreachable) |
| 3 | Timeout |
| 4 | No devices found |
