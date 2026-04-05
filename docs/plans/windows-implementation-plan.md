# Windows Browser — Implementation Plan

**Goal:** Build a Windows desktop browser app using the shared desktop Chromium core. GUI-only (no headless requirement for first pass).

**Approach:** Consume the shared engine-chromium-desktop, wrap in a Win32/WinAPI shell with URL bar, toolbar, and browser panels.

## Current Implementation Notes

The repo does not yet contain `native/engine-chromium-desktop/`, so the first Windows cut in `apps/windows/` is intentionally thin:

- Build and shell code exist now under `apps/windows/`.
- The app links the existing native protocol/state/automation/MCP libraries directly.
- CEF integration is optional behind `HAS_CEF` and `CEF_ROOT`; without a real SDK the app still builds with a visible placeholder browser host.
- HTTP keeps `/v1/` stable for the implemented Windows shell endpoints and returns `PLATFORM_NOT_SUPPORTED` for shared browser methods that still need the shared desktop engine.
- Settings persist to `settings.json` in the profile directory. Changing the profile directory updates future launches immediately, but full cache migration still depends on the later shared desktop runtime.

---

## Architecture

```
apps/windows/
  CMakeLists.txt              # Windows app build
  src/
    main.cpp                  # WinMain entry point
    windows_app.h / .cpp      # App lifecycle, initializes core + shell
    win32_shell.h / .cpp      # Win32 window host
    win32_browser_view.h / .cpp # HWND hosting CEF view
    url_bar.h / .cpp          # Win32 URL bar + navigation buttons
    settings_view.h / .cpp    # Settings dialog
    bookmarks_view.h / .cpp   # Bookmarks panel
    history_view.h / .cpp     # History panel
    network_inspector.h / .cpp # Network inspector with filter dropdowns
    toast_view.h / .cpp       # Toast notification
    device_info_windows.h / .cpp # Windows-specific device info
    mdns_windows.h / .cpp     # Windows mDNS (dns-sd API or Bonjour SDK)
  resources/
    kelpie.rc               # Windows resource file
    kelpie.ico              # App icon
    manifest.xml              # App manifest (DPI awareness, etc.)
```

### Dependencies on shared native core

Same as Linux — consumes:
- `native/core-protocol/`
- `native/core-state/`
- `native/core-automation/`
- `native/core-mcp/`
- `native/engine-chromium-desktop/`

---

## Phase 1: Consume Shared Desktop Core

The shared `engine-chromium-desktop` must be built first (see Linux plan). Windows links against the same core libraries.

### Windows-specific build considerations

- CMake generator: Visual Studio or Ninja
- CEF binary distribution: Windows 64-bit (`cef_binary_*_windows64`)
- Link against: `libcef.lib`, `libcef_dll_wrapper.lib`
- Copy CEF resources to output directory: `libcef.dll`, `icudtl.dat`, `chrome_elf.dll`, locales/, etc.
- Subsystem: Windows (not Console) for GUI app
- For cross-compilation from macOS: use `x86_64-w64-mingw32` toolchain or MSVC via Wine

---

## Phase 2: Win32 Shell

### Window structure

```
┌─────────────────────────────────────────────┐
│ ← → ↻ │ URL Bar                        │ ☰ │  <- Toolbar
├─────────────────────────────────────────────┤
│                                             │
│                                             │
│             CEF Browser View                │
│                                             │
│                                             │
├─────────────────────────────────────────────┤
│ Status: Ready                               │  <- Status bar
└─────────────────────────────────────────────┘
```

### Win32 implementation

**Main window:**
- Register `WNDCLASSEX` with custom `WndProc`
- Create main window with `WS_OVERLAPPEDWINDOW`
- Handle `WM_SIZE` to resize browser view
- Handle `WM_CLOSE` to shut down CEF
- DPI-aware via manifest

**URL bar:**
- Child `EDIT` control with `ES_AUTOHSCROLL`
- Navigation buttons: `BUTTON` controls with icons
- Handle `WM_COMMAND` for button clicks
- Handle `EN_CHANGE` or Enter key for navigation

**Browser view:**
- CEF browser hosted in a child HWND
- `CefBrowserHost::CreateBrowser()` with parent HWND
- Forward `WM_SIZE` to CEF for resize

**Sidebar panels (bookmarks/history/network inspector):**
- Child windows shown/hidden on toggle
- ListView controls for lists
- Network inspector: three ComboBox filter dropdowns
  - Method: All/GET/POST/PUT/DELETE
  - Type: All/HTML/JSON/JS/CSS/Image/Font/XML/Other
  - Source: All/Browser/JS

**Settings dialog:**
- Modal dialog with port, profile directory, startup URL
- Persisted to `%APPDATA%\Kelpie\settings.json`

---

## Phase 3: Device Info & mDNS

### Device info (Windows-specific)

- ID: persistent UUID from `%APPDATA%\Kelpie\device-id`
- Name: `GetComputerNameEx(ComputerNameDnsHostname)`
- Model: WMI `Win32_ComputerSystem.Model` or registry
- Platform: `windows`
- Engine: `chromium`
- IP: `GetAdaptersAddresses()`
- Memory: `GlobalMemoryStatusEx()`
- OS version: `RtlGetVersion()` or `GetVersionEx()`

### mDNS

Option A: Bonjour SDK for Windows (Apple's `dns_sd.h` API)
- Requires Bonjour service installed (comes with iTunes, or standalone installer)
- `DNSServiceRegister()` to advertise `_kelpie._tcp`

Option B: Windows built-in mDNS (`DnsServiceRegister` from `windns.h`, Windows 10+)
- Native, no extra dependencies
- Available on Windows 10 1809+

Recommendation: Start with Option B (native), fall back to Option A.

---

## Phase 4: Packaging

### Local dev build
- CMake build produces: `kelpie.exe` + CEF DLLs + resources
- Run from build directory

### Distributable
- Zip archive with all files
- Optional: NSIS or WiX installer later
- User data: `%APPDATA%\Kelpie\`

### Profile directory layout
```
%APPDATA%\Kelpie\
  device-id                # Persistent device UUID
  settings.json            # App settings
  cache/                   # CEF cache
  bookmarks.json           # Bookmarks
  history.json             # History
```

---

## Verification

- [ ] App launches with visible window, URL bar, browser view
- [ ] Navigation works via URL bar
- [ ] Navigation works via HTTP API (`POST /v1/navigate`)
- [ ] `GET /health` responds
- [ ] `POST /v1/get-device-info` returns correct Windows info
- [ ] `POST /v1/screenshot` returns PNG
- [ ] `POST /v1/evaluate` runs JS
- [ ] Bookmarks/history panels show data
- [ ] Network inspector shows traffic with filter dropdowns
- [ ] mDNS advertisement visible (`dns-sd -B _kelpie._tcp local.`)
- [ ] CLI discovers and controls the Windows browser
- [ ] Browser-side MCP exposes supported tools only

---

## Build requirements

- CMake 3.16+
- C++17 compiler (MSVC 2019+ or MinGW-w64)
- CEF binary distribution (Windows 64-bit)
- cpp-httplib (header-only)
- nlohmann/json (already in native/ CMake)
- Windows SDK 10.0.17763+ (for native mDNS)

### Cross-compilation from macOS (for development)

- Install MinGW-w64: `brew install mingw-w64`
- CMake toolchain file for cross-compilation
- CEF Windows distribution extracted locally
- Cannot run the built .exe on macOS without Wine
- Wine can be used for basic smoke testing

### Testing options

1. **Docker with Wine** — Run Windows .exe in Wine inside Docker
2. **Wine on macOS** — Install via `brew install --cask wine-stable`
3. **Windows VM** — VirtualBox/UTM with Windows
4. **Physical Windows machine** — Best for final verification

---

## CLI flags

```
kelpie.exe [options]
  --port PORT         HTTP server port (default: 8420)
  --profile-dir DIR   Data directory (default: %APPDATA%\Kelpie)
  --url URL           Initial URL to load
  --width WIDTH       Window width (default: 1920)
  --height HEIGHT     Window height (default: 1080)
```

---

## Unsupported features (return PLATFORM_NOT_SUPPORTED)

- `safari-auth` — Apple only
- `set-renderer` — Chromium-only, no switching
- `show-keyboard` / `hide-keyboard` — mobile only
- `set-orientation` — mobile only
- External display features — mobile only

## Cross-Provider Review

Fallback review was required before implementation. This environment does not expose a true non-Codex provider directly, so the review was recorded against the implementation plan and the accepted findings were:

1. Do not bury HTTP routing or Windows shell state in a fake shared runtime. Keep the first Windows delivery as explicit app-side bootstrap code until `engine-chromium-desktop/` exists.
2. Do not pretend screenshot/eval/DOM features work before the shared desktop Chromium engine exists. Keep those endpoints deterministic with `PLATFORM_NOT_SUPPORTED`.
3. Do not make mDNS a hard startup dependency. Attempt native Windows registration first, fall back to Bonjour when available, and otherwise continue with HTTP plus a warning path.
4. Do not make CEF mandatory at configure time. The Win32 shell must compile without a real SDK so the repo can land structure before the shared engine is wired in.
