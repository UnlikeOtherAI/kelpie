# Task 01: Monorepo Scaffold + Shared Types

**Component:** Infrastructure
**Depends on:** Nothing
**Estimated size:** ~300 lines

## Goal

Set up the pnpm monorepo structure and create the shared TypeScript types package that defines every API request, response, error code, and MCP tool name. This is the foundation everything else builds on.

## Files to Create

```
kelpie/
  .gitignore
  .npmrc
  pnpm-workspace.yaml
  package.json                          # root workspace
  tsconfig.base.json                    # shared TS config
  packages/
    shared/
      package.json                      # @unlike-other-ai/kelpie-shared
      tsconfig.json
      src/
        index.ts                        # barrel export
        api-types.ts                    # all HTTP request/response types
        error-codes.ts                  # error code enum + error response type
        device-types.ts                 # device info, mDNS TXT records, capabilities
        mcp-tools.ts                    # MCP tool name constants
        constants.ts                    # port, mDNS service type, API version prefix
    cli/
      package.json                      # @unlike-other-ai/kelpie (stub)
      tsconfig.json
  apps/
    ios/.gitkeep
    android/.gitkeep
```

## Steps

### 1. Root workspace files

Create `pnpm-workspace.yaml`:
```yaml
packages:
  - "packages/*"
```

Create root `package.json`:
```json
{
  "name": "kelpie-monorepo",
  "private": true,
  "scripts": {
    "build": "pnpm -r build",
    "test": "pnpm -r test",
    "lint": "pnpm -r lint"
  }
}
```

Create `.npmrc`:
```
shamefully-hoist=false
strict-peer-dependencies=true
```

Create `.gitignore` covering: `node_modules/`, `dist/`, `*.tsbuildinfo`, `.DS_Store`, `.env`, `*.log`.

Create `tsconfig.base.json` with strict mode, ES2022 target, NodeNext module resolution.

### 2. Shared types package

Create `packages/shared/package.json`:
```json
{
  "name": "@unlike-other-ai/kelpie-shared",
  "version": "0.1.0",
  "type": "module",
  "main": "./dist/index.js",
  "types": "./dist/index.d.ts",
  "exports": {
    ".": { "import": "./dist/index.js", "types": "./dist/index.d.ts" }
  },
  "scripts": {
    "build": "tsc",
    "test": "vitest run"
  }
}
```

### 3. Type definitions

**`constants.ts`** — Default port (8420), mDNS service type (`_kelpie._tcp`), API version prefix (`/v1/`), MCP tool prefix (`kelpie_`).

**`error-codes.ts`** — Enum of all error codes from docs/api/README.md: `ELEMENT_NOT_FOUND`, `ELEMENT_NOT_VISIBLE`, `TIMEOUT`, `NAVIGATION_ERROR`, `INVALID_SELECTOR`, `INVALID_PARAMS`, `WEBVIEW_ERROR`, `IFRAME_ACCESS_DENIED`, `WATCH_NOT_FOUND`, `ANNOTATION_EXPIRED`, `PLATFORM_NOT_SUPPORTED`, `PERMISSION_REQUIRED`, `SHADOW_ROOT_CLOSED`. Plus the `ErrorResponse` type.

**`device-types.ts`** — Types for: `DeviceInfo` (full response from `/v1/get-device-info`), `MdnsTxtRecord` (id, name, model, platform, width, height, port, version), `DeviceCapabilities` (supported/partial/unsupported arrays), `Platform` union type (`"ios" | "android"`).

**`api-types.ts`** — Request/response types for every API endpoint grouped by category:
- Navigation: `NavigateRequest`, `NavigateResponse`, etc.
- Screenshots: `ScreenshotRequest`, `ScreenshotResponse`
- DOM: `GetDOMRequest`, `QuerySelectorRequest`, etc.
- Interaction: `ClickRequest`, `FillRequest`, `TypeRequest`, etc.
- Scrolling: `ScrollRequest`, `Scroll2Request`, etc.
- LLM: `GetAccessibilityTreeRequest`, `ScreenshotAnnotatedRequest`, `FindElementRequest`, etc.
- DevTools: `GetConsoleMessagesRequest`, `GetNetworkLogRequest`, `WatchMutationsRequest`, etc.
- Browser: `HandleDialogRequest`, `GetTabsResponse`, `GetCookiesRequest`, `SetStorageRequest`, etc.
- Keyboard/Viewport: `ShowKeyboardRequest`, `ResizeViewportRequest`, etc.

**`mcp-tools.ts`** — String literal union of all MCP tool names (from docs/api/README.md table). Both browser-level and CLI-level tools.

### 4. CLI package stub

Create `packages/cli/package.json` with name `@unlike-other-ai/kelpie`, version `0.1.0`, dependency on `@unlike-other-ai/kelpie-shared`.

### 5. Build and verify

```bash
cd packages/shared && pnpm install && pnpm build
```

### 6. Write tests

Test that all type exports are accessible, constants have correct values, error codes match the documented set.

### 7. Commit

```bash
git add -A && git commit -m "feat: monorepo scaffold and shared types package"
```

## Acceptance Criteria

- [ ] `pnpm install` succeeds at repo root
- [ ] `pnpm build` succeeds in `packages/shared/`
- [ ] All API types from docs/api/ are represented (cross-reference against MCP tool table)
- [ ] Error codes match docs/api/README.md exactly
- [ ] Constants match documented values (port 8420, `_kelpie._tcp`, `/v1/`)
- [ ] `packages/cli/` exists with correct package name and dependency on shared
- [ ] `apps/ios/` and `apps/android/` directories exist
- [ ] `.gitignore` excludes `node_modules/`, `dist/`, `*.tsbuildinfo`
- [ ] Types compile with strict TypeScript (no `any`)
- [ ] Tests pass: `pnpm test` in shared package

---

- [ ] **Have you run an adversarial review with Codex?**
