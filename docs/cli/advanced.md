# Advanced CLI Commands

Back to the [CLI reference](../cli.md).

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

### `kelpie ai catalog`
List the approved on-device model catalog from a device, including download URLs and per-model metadata (size, min/recommended RAM, capabilities, quantization). Requires a HuggingFace token configured on the device. Supported on iOS, Android, and macOS.

```bash
kelpie ai catalog --device mac
```

### `kelpie ai fitness <model>`
Score a catalog model against a device's resources. Returns a fitness level (`recommended`, `possible`, `not_recommended`, `no_storage`) with an explanatory message. Supported on iOS, Android, and macOS.

| Flag | Description |
|---|---|
| `--ram <gb>` | Total device RAM in GB to score against |
| `--disk <gb>` | Free disk space in GB to score against |

```bash
kelpie ai fitness gemma-4-e2b-q4 --device mac --ram 32 --disk 50
```

---

## LLM Help System

Every command includes structured help designed for LLMs.

### `kelpie --llm-help`
Outputs a complete machine-readable reference of all commands, their parameters, expected inputs/outputs, usage guidance, and issue-reporting instructions for unexpected failures or missing capabilities.

```bash
kelpie --llm-help                   # full reference
kelpie click --llm-help             # help for specific command
kelpie group --llm-help             # help for group commands
```

**LLM help includes:**
- Command purpose and when to use it
- Full parameter schema with types and defaults
- Example request/response pairs
- Common error scenarios, failure-reporting guidance, and the repo issue URL
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
