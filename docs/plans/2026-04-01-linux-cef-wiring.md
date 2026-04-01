# Linux CEF Wiring Plan

**Goal:** Make the Linux app show and control a real Chromium page through CEF instead of the current stub renderer.

**Current defect:** The Linux GUI now launches, but it never renders a browser because `apps/linux/src/linux_app.cpp` always constructs `StubRenderer`, while the shared desktop Chromium engine lives separately under `native/engine-chromium-desktop/` and is not used by the Linux shell. Even when GTK is available, the app only shows placeholder text.

## Root Cause

There are two disconnected browser paths:

1. `apps/linux/` owns app lifecycle, HTTP server, stores, mDNS, and UI, but binds handlers to `StubRenderer`.
2. `native/engine-chromium-desktop/` owns the real `DesktopEngine`, `CefRenderer`, router, HTTP server, MCP server, and store wiring, but Linux never instantiates it.

Build-time CEF support is also incomplete on Linux:

- `apps/linux/CMakeLists.txt` can optionally detect a `CEF_ROOT`, but the current build path does not provision one.
- `native/engine-chromium-desktop/CMakeLists.txt` intentionally falls back to `desktop_engine_stub.cpp` unless `MOLLOTOV_ENABLE_CHROMIUM_DESKTOP=ON` and `CEF_ROOT` is supplied.
- `scripts/download-cef.sh` only handles macOS ARM64 today.

The broken invariant is that Linux claims to be a Chromium desktop shell, but the runtime path in `apps/linux/` is not actually connected to the shared Chromium engine.

## Simplification First

The right fix is to remove Linux-specific duplicate browser orchestration, not to make the stub renderer more sophisticated.

Linux should:

- reuse `DesktopApp` for engine, HTTP, MCP, handler registration, and store/event plumbing
- keep only Linux-specific concerns in `apps/linux/`: GTK window host integration, Avahi-backed mDNS adapter, Linux device info adapter, and small UI widgets
- retain the stub/non-CEF path only as an explicit fallback for environments without CEF, not as the default GUI path

## Proposed Changes

### 1. Add Linux CEF runtime provisioning

- Extend `scripts/download-cef.sh` to support Linux x86_64 in addition to macOS ARM64, or add a Linux-specific companion script if that keeps the script simpler.
- Download the Linux minimal CEF binary distribution into a stable repo-local cache path such as `third_party/cef/linux-x86_64/` or another non-generated permanent location already acceptable to the repo.
- Ensure the Linux build can be pointed at that extracted SDK via `CEF_ROOT`.

### 2. Make the Linux build prefer real CEF when available

- Keep GTK and Avahi optional.
- Keep Linux building without CEF for fresh machines and CI.
- When `CEF_ROOT` is present:
  - build `native/engine-chromium-desktop` with `MOLLOTOV_ENABLE_CHROMIUM_DESKTOP=ON`
  - link the Linux app against the real desktop engine
  - stage the required runtime files next to the Linux binary so launching does not depend on ad hoc environment setup

### 3. Replace Linux’s direct `StubRenderer` ownership with a renderer seam

- Change `LinuxApp::Impl` to hold a `RendererInterface`-compatible object through an abstraction that can point to:
  - `DesktopEngine::renderer()` when CEF is active
  - `StubRenderer` only when CEF is unavailable
- Do not keep the Linux app’s current bespoke HTTP/store wiring if `DesktopApp` can own it already.

### 4. Reuse `DesktopApp` in Linux instead of duplicating orchestration

- Introduce small Linux adapters for:
  - `DeviceInfoProvider`
  - `DesktopMdns`
- Let `DesktopApp` own:
  - engine lifecycle
  - HTTP routing
  - MCP registry/server
  - console/network/history/bookmark store updates
- Let `LinuxApp` own:
  - CLI flag parsing inputs
  - GTK shell startup
  - periodic `Tick()` / message-pump integration
  - Linux-specific dialogs/widgets

This is the core simplification. It removes duplicate router and store plumbing from `apps/linux/` and makes Linux consume the already-built shared desktop core.

### 5. Host the real browser in the GTK shell

- In GUI mode, create the browser via `DesktopEngine::Config.mode = kWindowed`.
- Provide a GTK/X11-backed `configure_window_info` callback so CEF attaches to the host widget/window instead of using the current placeholder label.
- Keep the existing GLib timer model and call the shared engine tick/message loop from GTK main-thread timers.

### 6. Keep headless behavior aligned

- In headless mode, use `DesktopEngine::Config.mode = kOffscreen`.
- Verify screenshots and JS evaluation come from the real engine when CEF is available.
- If CEF is unavailable, return clear unsupported errors instead of silently behaving like a fake browser for endpoints that require a real page.

## Files Likely Touched

- `apps/linux/CMakeLists.txt`
- `apps/linux/src/linux_app.h`
- `apps/linux/src/linux_app.cpp`
- `apps/linux/src/linux_app_internal.h`
- `apps/linux/src/gui_shell.cpp`
- `apps/linux/src/gtk_browser_view.h`
- `apps/linux/src/gtk_browser_view.cpp`
- `apps/linux/src/main.cpp`
- `scripts/download-cef.sh`
- `Makefile`
- relevant Linux docs once the behavior changes

## Verification

1. Provision Linux CEF runtime locally.
2. Clean rebuild: `make linux`
3. Launch GUI build on the desktop session.
4. Confirm the default URL renders as an actual page rather than placeholder text.
5. Verify:
   - `GET /health`
   - `POST /v1/navigate`
   - `POST /v1/evaluate`
   - `POST /v1/screenshot`
6. Run `pnpm build && pnpm test` for the CLI after the Linux runtime changes are integrated.

## Cross-Provider Review

Attempted with the local `claude` CLI before implementation, but the machine was not authenticated (`Not logged in · Please run /login`), so no external review response was available for this change.
