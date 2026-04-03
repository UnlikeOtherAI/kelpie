# macOS AI Shell Alignment

## Problem

The macOS AI UI does not match the approved local inference design:

- The floating menu opens a modal status sheet instead of the specified AI side panel.
- The URL bar has no brain pill.
- Settings has no compact AI section.
- There is no chat surface or model management surface in the browser window.

The backend already supports `ai-status`, `ai-load`, `ai-unload`, `ai-infer`, and `ai-record`. The missing piece is the macOS shell and the minimal model/state layer needed to drive it.

## Scope

Implement the macOS local inference UI described in:

- `docs/plans/2026-04-02-local-inference.md`
- `docs/plans/2026-04-02-local-inference-ui.md`

This change is limited to the macOS app.

## Design

### 1. Replace the modal AI sheet with an attached side panel

- Remove the `AIStatusView` sheet path from the browser shell.
- Add a 250px AI side panel on the right side of the browser window.
- The panel has two tabs: `Chat` and `Models`.
- The panel is hidden by default.
- When visible, it lives inside the browser shell and shrinks the browser content width.

### 2. Add the URL bar brain pill

- Insert a brain pill into the macOS URL bar beside the address field.
- State mapping:
  - No model loaded: dimmed brain icon, tapping opens `Models`.
  - Model loaded and panel closed: labeled pill, tapping opens `Chat`.
  - Model loaded and panel open: highlighted pill, tapping closes panel.
- The floating menu brain action uses the same open behavior.

### 3. Add a compact AI section to Settings

- Add an `AI` section to macOS settings.
- Show:
  - active model picker
  - local device summary
  - Ollama endpoint field + test status
  - privacy copy
- Keep settings compact. No chat UI in settings.

### 4. Introduce a lightweight macOS AI registry/state layer

- Expand `AIState` from availability-only state into the single observable source for:
  - availability
  - Apple Silicon vs Ollama-only mode
  - active backend/model/capabilities
  - Ollama endpoint and reachability
  - downloaded native models from `~/.mollotov/models/*/metadata.json`
  - detected Ollama models from `/api/tags`
- Keep inference execution in `InferenceEngine` and handler routing in `AIHandler`.
- Do not add a downloader in this change. The models UI will support load/unload and reflect downloaded/native inventory plus Ollama inventory.

### 5. Per-window chat state

- Keep chat history per browser window, not global.
- Reset conversation on page URL change, per spec.
- Use the existing AI endpoints for submit/record flow instead of adding a second inference path in the UI layer.

## Simplifications

To keep complexity under control while fixing the core mismatch, the first implementation will:

- implement the pinned in-window panel
- implement the brain pill states
- implement chat + models tabs
- implement settings AI section
- implement model load/unload and Ollama testing
- implement model fitness evaluation for native cards using device RAM/storage

The detachable unpinned window and magnetic re-docking are intentionally excluded from this pass. They are part of the longer-term spec, but they are not the broken invariant the user reported. The current defect is that the macOS AI shell is missing and replaced by a modal placeholder. This pass will still preserve a clean panel presentation seam so detached-window behavior can be added later without rewriting the chat or model views.

## Files Expected To Change

- `apps/macos/Mollotov/Views/BrowserView.swift`
- `apps/macos/Mollotov/Views/URLBarView.swift`
- `apps/macos/Mollotov/Views/SettingsView.swift`
- `apps/macos/Mollotov/Views/FloatingMenuView.swift`
- `apps/macos/Mollotov/AI/AIState.swift`
- `apps/macos/Mollotov/MollotovApp.swift`

New views are likely:

- `apps/macos/Mollotov/Views/AIChatPanel.swift`
- `apps/macos/Mollotov/Views/AIChatView.swift`
- `apps/macos/Mollotov/Views/AIModelListView.swift`
- `apps/macos/Mollotov/Views/AIStatusPill.swift`

## Acceptance Criteria

- The macOS browser no longer opens `AIStatusView` as a sheet.
- The URL bar shows a brain pill with the documented open/close behavior.
- The floating menu brain action opens the same panel state as the brain pill.
- The panel contains `Chat` and `Models` tabs and stays attached to the browser shell.
- Settings includes the compact AI section.
- Chat clears when the page URL changes.
- Native model cards evaluate device fitness from RAM and free disk and render recommended / possible / not-recommended / no-storage states.
- Ollama models are shown separately with server-managed treatment and no local fitness warning.
- The app builds successfully on macOS.

## Cross-Provider Review

Reviewer: Gemini CLI

Findings taken:

- `AIState` cannot stay availability-only. It needs to become the shared observable source for backend/model status, device capabilities, native inventory, and Ollama inventory so state does not leak into views.
- Per-window chat state must stay out of the singleton. The browser window owns conversation history and active tab; the singleton owns shared model/backend/device inventory.
- Native model cards need device-fit evaluation, not a static list. This pass will include RAM/storage-based card state for the approved native models.
- Acceptance criteria must verify behavior, not just panel visibility. The criteria above were expanded accordingly.

Finding rejected:

- Full detached-window chat support is not required for this alignment fix. The current defect is a modal placeholder instead of an in-window AI shell. Shipping the attached panel with a clean presentation seam reduces complexity now without forcing a future rewrite.
