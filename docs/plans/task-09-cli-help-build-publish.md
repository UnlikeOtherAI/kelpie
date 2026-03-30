# Task 09: CLI Help System + Build + Publish Config

**Component:** CLI
**Depends on:** Task 08
**Estimated size:** ~400 lines

## Goal

Implement the LLM help system, configure tsup build, finalize the entry point, and make the package ready for npm publish.

## Files to Create/Modify

```
packages/cli/src/
  help/
    llm-help.ts               # --llm-help implementation
    explain.ts                 # mollotov explain <command>
    command-metadata.ts        # structured metadata for every command
  commands/
    explain.ts                 # explain command registration
  index.ts                     # wire up --llm-help flag
```

```
packages/cli/
  tsup.config.ts              # build config
  bin/mollotov.ts              # entry point (finalize)
  package.json                 # publish config (bin, files, exports)
```

```
packages/cli/tests/help/
  llm-help.test.ts
  explain.test.ts
```

## LLM Help System

### `--llm-help` Flag (`help/llm-help.ts`)

When passed globally or on any command, outputs machine-readable structured help:

```bash
mollotov --llm-help              # full reference for all commands
mollotov click --llm-help        # help for specific command
mollotov group --llm-help        # help for group commands
```

Output format:
```json
{
  "command": "click",
  "purpose": "Click an element on the page",
  "when": "Use when you need to interact with a clickable element identified by CSS selector",
  "params": [
    {"name": "selector", "type": "string", "required": true, "description": "CSS selector of element to click"},
    {"name": "timeout", "type": "number", "required": false, "default": 5000, "description": "Wait timeout in ms"}
  ],
  "example": {"request": "mollotov click \"#submit\" --device \"iPhone\"", "response": {"success": true, "element": {"tag": "button", "text": "Submit"}}},
  "errors": ["ELEMENT_NOT_FOUND", "ELEMENT_NOT_VISIBLE", "TIMEOUT"],
  "related": ["tap", "fill", "find-button"]
}
```

### `explain` Command (`help/explain.ts`)

```bash
mollotov explain scroll2
```

Returns natural language explanation (pre-written per command in `command-metadata.ts`).

### Command Metadata (`help/command-metadata.ts`)

Static data structure with per-command metadata: purpose, when to use, parameter schema, example request/response, common errors, related commands, natural language explanation.

## Build Config

### tsup (`tsup.config.ts`)

```typescript
import { defineConfig } from "tsup";
export default defineConfig({
  entry: ["src/index.ts"],
  format: ["esm"],
  target: "node20",
  dts: true,
  clean: true,
  sourcemap: true,
  shims: false,
});
```

### Package.json (final)

```json
{
  "name": "@unlike-other-ai/mollotov",
  "version": "0.1.0",
  "type": "module",
  "bin": { "mollotov": "./dist/index.js" },
  "files": ["dist"],
  "exports": { ".": { "import": "./dist/index.js" } },
  "engines": { "node": ">=20" },
  "publishConfig": { "access": "public" }
}
```

### Entry Point (`bin/mollotov.ts`)

Shebang line + import:
```typescript
#!/usr/bin/env node
import "../dist/index.js";
```

## Tests

- `--llm-help`: verify JSON output shape for a few commands
- `explain`: verify text output for a few commands
- Build: `pnpm build` produces valid dist/ with bin entry

## Acceptance Criteria

- [ ] `mollotov --llm-help` outputs valid JSON with all commands
- [ ] `mollotov click --llm-help` outputs structured help for click command
- [ ] `mollotov explain scroll2` outputs natural language explanation
- [ ] `pnpm build` succeeds, produces `dist/` with single bundle
- [ ] `node dist/index.js --version` works
- [ ] `node dist/index.js --help` shows all commands
- [ ] package.json `bin` field points to correct entry
- [ ] package.json `files` only includes `dist/`
- [ ] `pnpm pack` produces a clean tarball (no source, no tests)
- [ ] All commands have LLM help metadata (no missing entries)
- [ ] All tests pass
- [ ] Full CLI test: `pnpm build && pnpm test` passes

---

- [ ] **Have you run an adversarial review with Codex?**
