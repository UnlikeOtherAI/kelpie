# Kelpie — CLI Reference

## Installation

```bash
npm install -g @unlikeotherai/kelpie
# or
pnpm add -g @unlikeotherai/kelpie
```

## Usage

```
kelpie <command> [options]
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

### `kelpie discover`
Scan the local network for Kelpie browser instances.

```bash
kelpie discover
kelpie discover --timeout 5000    # custom scan duration
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

### `kelpie devices`
List previously discovered devices (cached from last scan).

```bash
kelpie devices
kelpie devices --refresh         # force re-scan before listing
```

### `kelpie ping [device]`
Check if a device is reachable. Without `--device`, pings all known devices.

```bash
kelpie ping --device "My iPhone"
kelpie ping                       # ping all
```

### `kelpie browser`
Manage local macOS Kelpie app aliases stored in `~/.kelpie/browsers.json`.

```bash
kelpie browser --help
```

### `kelpie browser register <name>`
Register or update a named local macOS browser alias.

```bash
kelpie browser register claude-a
kelpie browser register codex-b --app /Applications/Kelpie.app
```

### `kelpie browser launch <name>`
Launch a new local macOS Kelpie app instance for a registered alias. If `--port` is omitted, the CLI auto-selects the first safe free port and skips reserved ports such as `8421` used by AppReveal and CLI MCP.

```bash
kelpie browser launch claude-a
kelpie browser launch codex-b --port 8450 --wait
```

### `kelpie browser list`
List registered local browser aliases and their saved runtime state.

```bash
kelpie browser list
```

### `kelpie browser inspect <name>`
Show the saved app path, runtime port, and reachability for one alias.

```bash
kelpie browser inspect claude-a
```

### `kelpie browser remove <name>`
Remove a saved local alias and its runtime state. This does not terminate a running app process.

```bash
kelpie browser remove claude-a
```

---

## Navigation Commands

### `kelpie navigate <url>`

```bash
kelpie navigate "https://example.com" --device "My iPhone"
```

### `kelpie back` / `kelpie forward` / `kelpie reload`

```bash
kelpie back --device "My iPhone"
kelpie forward --device "My iPhone"
kelpie reload --device "My iPhone"
```

### `kelpie url`
Get current URL and title.

```bash
kelpie url --device "My iPhone"
```

### `kelpie home set <url>`
Set the device's home page. Persisted across app restarts.

```bash
kelpie home set "https://example.com" --device "My iPhone"
```

### `kelpie home get`
Get the current home page URL.

```bash
kelpie home get --device "My iPhone"
```

---

## Screenshot Commands

### `kelpie screenshot`

```bash
kelpie screenshot --device "My iPhone"
kelpie screenshot --device "My iPhone" --output ./shot.png
kelpie screenshot --device "My iPhone" --full-page
kelpie screenshot --device "My iPhone" --base64     # return raw base64 instead of saving
```

**Default behavior: saves to file, returns the path.** Without `--output`, the CLI auto-generates a filename in the current directory using the pattern `{device}-{timestamp}.png` (e.g., `my-iphone-2026-03-30T10-15-32.png`). The JSON response contains the file path — never base64 — so LLMs don't waste tokens on image data.

| Flag | Behavior |
|---|---|
| *(no flag)* | Auto-save to `./{device}-{timestamp}.png`, return `{"file": "..."}` |
| `--output <path>` | Save to explicit path, return `{"file": "..."}` |
| `--output <dir>/` | Save to directory with auto-generated filename |
| `--base64` | Return raw base64 JSON (for programmatic use, not LLM conversations) |

Group screenshots (`kelpie group screenshot`) always save to files — one per device. Use `--output <dir>/` to collect them in a folder.

---

## DOM Commands

### `kelpie dom`
Get the DOM tree.

```bash
kelpie dom --device "My iPhone"
kelpie dom --device "My iPhone" --selector "main" --depth 3
```

### `kelpie query <selector>`
Query for elements.

```bash
kelpie query "#submit-btn" --device "My iPhone"
kelpie query "a.nav-link" --device "My iPhone" --all
```

### `kelpie text <selector>`
Get text content of an element.

```bash
kelpie text "h1" --device "My iPhone"
```

### `kelpie attributes <selector>`
Get all attributes of an element.

```bash
kelpie attributes "#email-input" --device "My iPhone"
```

---

## Interaction Commands

### `kelpie click <selector>`

```bash
kelpie click "#submit-btn" --device "My iPhone"
```

### `kelpie tap <x> <y>`

```bash
kelpie tap 195 420 --device "My iPhone"
```

### `kelpie fill <selector> <value>`

```bash
kelpie fill "#email" "user@example.com" --device "My iPhone"
```

### `kelpie type <text>`

```bash
kelpie type "search query" --device "My iPhone"
kelpie type "search query" --device "My iPhone" --selector "#search-box"
kelpie type "search query" --device "My iPhone" --delay 50
```

### `kelpie select <selector> <value>`

```bash
kelpie select "#country" "us" --device "My iPhone"
```

### `kelpie check <selector>` / `kelpie uncheck <selector>`

```bash
kelpie check "#agree-terms" --device "My iPhone"
```

---

## Scroll Commands

### `kelpie scroll`

```bash
kelpie scroll --device "My iPhone" --y 500
kelpie scroll --device "My iPhone" --x 200 --y 0
```

### `kelpie scroll2 <selector>`
Resolution-aware scroll to element.

```bash
kelpie scroll2 "#footer" --device "My iPhone"
kelpie scroll2 "#footer" --device "My iPhone" --position center
```

### `kelpie scroll-top` / `kelpie scroll-bottom`

```bash
kelpie scroll-top --device "My iPhone"
kelpie scroll-bottom --device "My iPhone"
```

---

## Console & DevTools Commands

### `kelpie console`
Get console messages from the page.

```bash
kelpie console --device "My iPhone"
kelpie console --device "My iPhone" --level error     # errors only
kelpie console --device "My iPhone" --level warn      # warnings only
kelpie console --device "My iPhone" --limit 50
```

### `kelpie errors`
Get JavaScript errors (shorthand for `console --level error`).

```bash
kelpie errors --device "My iPhone"
```

### `kelpie network`
Get the network activity log — all resources loaded by the page.

```bash
kelpie network --device "My iPhone"
kelpie network --device "My iPhone" --type script     # only JS files
kelpie network --device "My iPhone" --type fetch      # only XHR/fetch
kelpie network --device "My iPhone" --status error    # only failed requests
```

### `kelpie timeline`
Get the resource loading timeline with timing data.

```bash
kelpie timeline --device "My iPhone"
```

### `kelpie clear-console`
Clear the console message buffer.

```bash
kelpie clear-console --device "My iPhone"
```

### `kelpie mutations`
Watch and get DOM mutations.

```bash
kelpie mutations watch --device "My iPhone"                    # start watching
kelpie mutations watch --device "My iPhone" --selector "main"  # scoped
kelpie mutations get --device "My iPhone"                      # get accumulated mutations
kelpie mutations stop --device "My iPhone"                     # stop watching
```

### `kelpie intercept`
Manage request interception rules.

```bash
kelpie intercept block "*.doubleclick.net/*" --device "My iPhone"
kelpie intercept mock "https://api.example.com/data" --body '{"items":[]}' --device "My iPhone"
kelpie intercept list --device "My iPhone"
kelpie intercept clear --device "My iPhone"
```

---

## LLM-Optimized Commands

### `kelpie a11y`
Get the accessibility tree — the most LLM-friendly representation of the page.

```bash
kelpie a11y --device "My iPhone"
kelpie a11y --device "My iPhone" --interactable-only
kelpie a11y --device "My iPhone" --selector "main"
```

### `kelpie annotate`
Take an annotated screenshot with numbered labels on interactive elements. Same file-saving behavior as `screenshot` — defaults to auto-save, returns the file path.

```bash
kelpie annotate --device "My iPhone"
kelpie annotate --device "My iPhone" --output ./annotated.png
kelpie annotate --device "My iPhone" --full-page
kelpie annotate --device "My iPhone" --base64     # raw base64 instead of file
```

### `kelpie click-index <index>`
Click an element by its annotation index from the last `annotate` call.

```bash
kelpie click-index 5 --device "My iPhone"
```

### `kelpie fill-index <index> <value>`
Fill an element by its annotation index.

```bash
kelpie fill-index 2 "user@example.com" --device "My iPhone"
```

### `kelpie visible`
Get only the elements currently visible in the viewport.

```bash
kelpie visible --device "My iPhone"
kelpie visible --device "My iPhone" --interactable-only
```

### `kelpie page-text`
Extract readable text from the page (reader mode).

```bash
kelpie page-text --device "My iPhone"
kelpie page-text --device "My iPhone" --mode markdown
kelpie page-text --device "My iPhone" --mode full
kelpie page-text --device "My iPhone" --selector "article"
```

### `kelpie form-state`
Get the state of all forms on the page.

```bash
kelpie form-state --device "My iPhone"
kelpie form-state --device "My iPhone" --selector "#signup-form"
```

---

## Dialog & Alert Commands

### `kelpie dialog`
Check if a dialog is showing.

```bash
kelpie dialog --device "My iPhone"
```

### `kelpie dialog accept` / `kelpie dialog dismiss`
Handle the current dialog.

```bash
kelpie dialog accept --device "My iPhone"
kelpie dialog dismiss --device "My iPhone"
kelpie dialog accept --device "My iPhone" --prompt-text "my input"
```

### `kelpie dialog auto`
Configure automatic dialog handling.

```bash
kelpie dialog auto --action accept --device "My iPhone"
kelpie dialog auto --action dismiss --device "My iPhone"
kelpie dialog auto --action queue --device "My iPhone"     # capture for later
kelpie dialog auto --off --device "My iPhone"              # disable
```

---

## Tab Commands

### `kelpie tabs`
List all open tabs.

```bash
kelpie tabs --device "My iPhone"
```

### `kelpie tab new [url]`
Open a new tab.

```bash
kelpie tab new "https://example.com" --device "My iPhone"
kelpie tab new --device "My iPhone"                         # blank tab
```

### `kelpie tab switch <id>`
Switch to a tab.

```bash
kelpie tab switch 1 --device "My iPhone"
```

### `kelpie tab close <id>`
Close a tab.

```bash
kelpie tab close 1 --device "My iPhone"
```

---

## Iframe Commands

### `kelpie iframes`
List all iframes on the page.

```bash
kelpie iframes --device "My iPhone"
```

### `kelpie iframe enter <id|selector>`
Switch command context into an iframe.

```bash
kelpie iframe enter 0 --device "My iPhone"
kelpie iframe enter "iframe[name='payment']" --device "My iPhone"
```

### `kelpie iframe exit`
Switch back to the main page context.

```bash
kelpie iframe exit --device "My iPhone"
```

### `kelpie iframe context`
Check which context (main page or iframe) commands are currently targeting.

```bash
kelpie iframe context --device "My iPhone"
```

---

## Cookie & Storage Commands

### `kelpie cookies`
Get cookies for the current page.

```bash
kelpie cookies --device "My iPhone"
kelpie cookies --device "My iPhone" --name "session_id"
```

### `kelpie cookies set <name> <value>`
Set a cookie.

```bash
kelpie cookies set "session_id" "abc123" --device "My iPhone"
kelpie cookies set "theme" "dark" --device "My iPhone" --domain "example.com" --path "/" --secure
```

### `kelpie cookies delete`
Delete cookies.

```bash
kelpie cookies delete --name "session_id" --device "My iPhone"
kelpie cookies delete --domain "example.com" --device "My iPhone"
kelpie cookies delete --all --device "My iPhone"
```

### `kelpie storage`
Read localStorage or sessionStorage.

```bash
kelpie storage --device "My iPhone"                          # localStorage (default)
kelpie storage --device "My iPhone" --type session
kelpie storage --device "My iPhone" --key "auth_token"
```

### `kelpie storage set <key> <value>`
Write to storage.

```bash
kelpie storage set "theme" "dark" --device "My iPhone"
kelpie storage set "theme" "dark" --device "My iPhone" --type session
```

### `kelpie storage clear`
Clear storage.

```bash
kelpie storage clear --device "My iPhone"
kelpie storage clear --device "My iPhone" --type session
kelpie storage clear --device "My iPhone" --type both
```

---

## Clipboard Commands

### `kelpie clipboard`
Read clipboard contents.

```bash
kelpie clipboard --device "My iPhone"
```

### `kelpie clipboard set <text>`
Write to clipboard.

```bash
kelpie clipboard set "text to copy" --device "My iPhone"
```

---

## Geolocation Commands

### `kelpie geo set <lat> <lng>`
Override geolocation.

```bash
kelpie geo set 37.7749 -122.4194 --device "My iPhone"
kelpie geo set 37.7749 -122.4194 --device "My iPhone" --accuracy 10
```

### `kelpie geo clear`
Remove geolocation override.

```bash
kelpie geo clear --device "My iPhone"
```

---

## Shadow DOM Commands

### `kelpie shadow-roots`
List all shadow DOM hosts on the page.

```bash
kelpie shadow-roots --device "My iPhone"
```

### `kelpie shadow-query <host> <selector>`
Query elements inside a shadow root.

```bash
kelpie shadow-query "my-component" ".inner-button" --device "My iPhone"
kelpie shadow-query "my-component" ".inner-button" --device "My iPhone" --pierce
```

---

## Keyboard & Viewport Commands

### `kelpie keyboard show`
Show the soft keyboard by focusing an element.

```bash
kelpie keyboard show --device "My iPhone"
kelpie keyboard show --device "My iPhone" --selector "#email"
kelpie keyboard show --device "My iPhone" --type number
```

### `kelpie keyboard hide`
Dismiss the soft keyboard.

```bash
kelpie keyboard hide --device "My iPhone"
```

### `kelpie keyboard state`
Check keyboard visibility and viewport impact.

```bash
kelpie keyboard state --device "My iPhone"
```

### `kelpie resize <width> <height>`
Simulate a reduced viewport (e.g., keyboard present, toolbar visible).

```bash
kelpie resize 390 500 --device "My iPhone"
```

### `kelpie resize reset`
Restore full-screen viewport.

```bash
kelpie resize reset --device "My iPhone"
```

### `kelpie obscured <selector>`
Check if an element is hidden by the keyboard or outside the visible viewport.

```bash
kelpie obscured "#password-input" --device "My iPhone"
```

---

## Wait Commands

### `kelpie wait <selector>`

```bash
kelpie wait ".results-loaded" --device "My iPhone"
kelpie wait ".results-loaded" --device "My iPhone" --timeout 15000
kelpie wait ".spinner" --device "My iPhone" --state hidden
```

### `kelpie wait-nav`
Wait for a navigation event to complete.

```bash
kelpie wait-nav --device "My iPhone"
kelpie wait-nav --device "My iPhone" --timeout 15000
```

---

## Evaluate

### `kelpie eval <expression>`

```bash
kelpie eval "document.title" --device "My iPhone"
kelpie eval "window.innerHeight" --device "My iPhone"
```

---

## Device Info

### `kelpie info [device]`
Get full device information.

```bash
kelpie info --device "My iPhone"
kelpie info                         # info for all devices
```

### `kelpie viewport [device]`
Get viewport dimensions.

```bash
kelpie viewport --device "My iPhone"
```

---

## Group Commands

All group commands target every discovered device unless filtered.

### `kelpie group <command> [args]`

```bash
kelpie group navigate "https://example.com"
kelpie group screenshot --output ./screenshots/
kelpie group fill "#email" "test@example.com"
kelpie group click "#submit"
kelpie group scroll2 "#footer"
```

### `kelpie group find-button <text>`
Find a button on all devices. Returns which devices found it and which didn't.

```bash
kelpie group find-button "Submit"
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

### `kelpie group find-element <text>`

```bash
kelpie group find-element "Sign Up" --role link
```

### `kelpie group find-link <text>`

```bash
kelpie group find-link "Sign Up"
```

### `kelpie group find-input <label>`

```bash
kelpie group find-input "Email"
```

### Group Filtering

```bash
kelpie group navigate "https://example.com" --platform ios       # only iOS devices
kelpie group navigate "https://example.com" --platform android   # only Android
kelpie group navigate "https://example.com" --exclude "iPad Air" # exclude specific device
kelpie group navigate "https://example.com" --include "a1b2c3d4,My iPhone" # only these devices (by ID or name)
```

`--include` accepts a comma-separated list of device IDs or names. When both `--include` and `--platform` are specified, only devices matching both filters are targeted.

---

## MCP Server

### `kelpie mcp`
Start the CLI as an MCP server (stdio transport).

```bash
kelpie mcp
```

Configure in Claude Desktop / Claude Code:
```json
{
  "mcpServers": {
    "kelpie": {
      "command": "kelpie",
      "args": ["mcp"]
    }
  }
}
```

### `kelpie mcp --http`
Start the MCP server with HTTP transport.

```bash
kelpie mcp --http --port 8421
```

---

## AI Commands

### `kelpie ai list`
List approved models, their download status, and Ollama models if available.

```bash
kelpie ai list
```

### `kelpie ai pull <model>`
Download a model from HuggingFace.

```bash
kelpie ai pull gemma-4-e2b-q4
```

### `kelpie ai rm <model>`
Delete a downloaded model.

```bash
kelpie ai rm gemma-4-e2b-q4
```

### `kelpie ai status`
Check inference status on a device.

```bash
kelpie ai status --device mac
```

### `kelpie ai load <model>`
Load a model on a device. Supports native model IDs and `ollama:` prefixed IDs.

```bash
kelpie ai load gemma-4-e2b-q4 --device mac
kelpie ai load ollama:llava:7b --device iphone
```

### `kelpie ai unload`
Unload the current model from a device.

```bash
kelpie ai unload --device mac
```

### `kelpie ai ask <prompt>`
Run inference on the device's loaded model.

| Flag | Description |
|---|---|
| `-c, --context <mode>` | Context mode: `page_text`, `screenshot`, `dom`, `accessibility` |
| `--max-tokens <n>` | Maximum tokens to generate (default: 512) |
| `--temperature <t>` | Sampling temperature (default: 0.7) |

```bash
kelpie ai ask "summarise this page" --device mac -c page_text
kelpie ai ask "describe what you see" --device mac -c screenshot
```

---

## LLM Help System

Every command includes structured help designed for LLMs.

### `kelpie --llm-help`
Outputs a complete machine-readable reference of all commands, their parameters, expected inputs/outputs, and usage guidance.

```bash
kelpie --llm-help                   # full reference
kelpie click --llm-help             # help for specific command
kelpie group --llm-help             # help for group commands
```

**LLM help includes:**
- Command purpose and when to use it
- Full parameter schema with types and defaults
- Example request/response pairs
- Common error scenarios and how to handle them
- Related commands and suggested workflows

### `kelpie explain <command>`
Natural language explanation of a command for LLM consumption.

```bash
kelpie explain scroll2
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
