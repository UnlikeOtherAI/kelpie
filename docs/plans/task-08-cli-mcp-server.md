# Task 08: CLI MCP Server

**Component:** CLI
**Depends on:** Task 07
**Estimated size:** ~500 lines

## Goal

Expose all CLI commands as MCP tools so LLMs can drive Kelpie directly. Both stdio and HTTP transports.

## Files to Create

```
packages/cli/src/
  mcp/
    server.ts                 # MCP server setup, tool registration
    tools.ts                  # Tool definitions (name, description, schema, handler)
    transport.ts              # stdio + HTTP transport selection
```

```
packages/cli/tests/mcp/
  server.test.ts
  tools.test.ts
```

## Architecture

### Server (`mcp/server.ts`)

Uses `@modelcontextprotocol/sdk` to create an MCP server. Registers all tools from `tools.ts`.

```bash
pnpm add @modelcontextprotocol/sdk
```

Two launch modes:
- `kelpie mcp` — stdio transport (standard MCP CLI pattern)
- `kelpie mcp --http --port 8421` — HTTP/SSE transport

### Tool Definitions (`mcp/tools.ts`)

Each MCP tool maps to a CLI command. Uses `kelpie_` prefix for all tool names.

**Browser-level tools (80+):** Map directly to HTTP API methods. Each tool takes a `device` parameter (required for individual commands) plus the method-specific params.

From docs/api/README.md MCP tool table:
- `kelpie_navigate`, `kelpie_back`, `kelpie_forward`, `kelpie_reload`
- `kelpie_screenshot`, `kelpie_get_dom`, `kelpie_query_selector`
- `kelpie_click`, `kelpie_fill`, `kelpie_type`, `kelpie_scroll2`
- ... (all 80+ tools from the table)

**CLI-level tools (20+):** Group commands + discovery.
- `kelpie_discover`, `kelpie_list_devices`
- `kelpie_group_navigate`, `kelpie_group_screenshot`, `kelpie_group_find_button`
- ... (all group tools from the table)

### Tool Registration Pattern

Each tool definition:
```typescript
{
  name: "kelpie_navigate",
  description: "Navigate a device browser to a URL",
  inputSchema: {
    type: "object",
    properties: {
      device: { type: "string", description: "Device ID, name, or IP" },
      url: { type: "string", description: "URL to navigate to" }
    },
    required: ["device", "url"]
  },
  handler: async (params) => {
    const dev = registry.getDevice(params.device);
    return httpClient.sendCommand(dev, "navigate", { url: params.url });
  }
}
```

Group tools omit the `device` parameter and take filter params (`platform`, `include`, `exclude`) instead.

### Transport (`mcp/transport.ts`)

- stdio: reads JSON-RPC from stdin, writes to stdout
- HTTP: starts an HTTP server with SSE endpoint at `/mcp`

## Tests

- Server: verify tool count matches expected (80+ browser + 20+ CLI)
- Tools: test a few representative tools call correct handlers
- Verify tool names match documented MCP tool names exactly

## Acceptance Criteria

- [ ] `kelpie mcp` starts stdio MCP server
- [ ] `kelpie mcp --http --port 8421` starts HTTP MCP server
- [ ] All browser-level MCP tools are registered (cross-reference docs/api/README.md table)
- [ ] All CLI-level group MCP tools are registered
- [ ] Tool names use `kelpie_` prefix with underscores (not hyphens)
- [ ] Each tool has a clear description and correct input schema
- [ ] Individual tools require `device` parameter
- [ ] Group tools accept `platform`, `include`, `exclude` filter params
- [ ] Tool handlers correctly route to HTTP client or orchestrator
- [ ] MCP server config works in Claude Desktop / Claude Code (test JSON config)
- [ ] All tests pass

---

- [ ] **Have you run an adversarial review with Codex?**
