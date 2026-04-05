# Linux Browser — Implementation Plan

**Goal:** Build a Linux browser app with headless and GUI modes, sharing the desktop Chromium core with Windows.

**Approach:** Headless first (validates the shared core without UI noise), then add GTK-based GUI shell.

---

## Architecture

```
apps/linux/
  CMakeLists.txt              # Linux app build
  src/
    main.cpp                  # Entry point — parses flags, picks headless vs GUI
    linux_app.h / .cpp        # App lifecycle, initializes core + shell
    headless_shell.h / .cpp   # Headless mode — no window, runs event loop
    gui_shell.h / .cpp        # GUI mode — GTK window host
    gtk_browser_view.h / .cpp # GTK widget embedding CEF view
    url_bar.h / .cpp          # GTK URL bar + navigation buttons
    settings_view.h / .cpp    # GTK settings panel
    bookmarks_view.h / .cpp   # GTK bookmarks sidebar
    history_view.h / .cpp     # GTK history sidebar
    network_inspector.h / .cpp # GTK network inspector with filter dropdowns
    toast_view.h / .cpp       # Toast notification overlay
    device_info_linux.h / .cpp # Linux-specific device info (hostname, IP, memory)
    mdns_avahi.h / .cpp       # Avahi-based mDNS advertiser
  Dockerfile                  # For headless testing
  docker-compose.yml
```

### Dependencies on shared native core

```
native/
  core-protocol/    — endpoint names, error codes, platform enums (EXISTS)
  core-state/       — bookmark/history/console/network stores (EXISTS)
  core-automation/  — handler context, renderer interface, response helpers (EXISTS)
  core-mcp/         — browser-side MCP registry (EXISTS)
  engine-chromium-desktop/  — CEF runtime, HTTP server, mDNS interface (TO BUILD)
```

---

## Phase 1: Shared Desktop Engine (engine-chromium-desktop)

This is shared with Windows. Build it first.

### Module: `native/engine-chromium-desktop/`

```
native/engine-chromium-desktop/
  CMakeLists.txt
  include/kelpie/
    desktop_engine.h          # CEF lifecycle, windowed + offscreen modes
    desktop_http_server.h     # HTTP server (cpp-httplib)
    desktop_router.h          # Routes /v1/{method} to handlers
    desktop_mcp_server.h      # Browser-side MCP server
    desktop_mdns.h            # mDNS interface (platform-specific impl)
    desktop_app.h             # Orchestrates engine + server + mDNS
    desktop_bridge.h          # Console/network bridge script injection
    cef_renderer.h            # CEF RendererInterface implementation
  src/
    desktop_engine.cpp
    desktop_http_server.cpp
    desktop_router.cpp
    desktop_mcp_server.cpp
    desktop_app.cpp
    desktop_bridge.cpp
    cef_renderer.cpp
    handlers/                 # C++ handler implementations
      navigation_handler.cpp
      interaction_handler.cpp
      dom_handler.cpp
      evaluate_handler.cpp
      screenshot_handler.cpp
      scroll_handler.cpp
      console_handler.cpp
      network_handler.cpp
      device_handler.cpp
      bookmark_handler.cpp
      history_handler.cpp
      browser_mgmt_handler.cpp
      renderer_handler.cpp
      viewport_handler.cpp
```

### Key implementation details

**CEF integration:**
- Download CEF binary distribution for Linux (cef_binary_*_linux64_minimal)
- Use `CefApp`, `CefClient`, `CefBrowserProcessHandler`
- Windowed mode: embed in platform window (GTK on Linux, HWND on Windows)
- Offscreen mode: `CefRenderHandler` with `GetViewRect` / `OnPaint` for screenshots
- Message loop: `CefDoMessageLoopWork()` on timer (60fps) or `CefRunMessageLoop()`

**HTTP server:**
- Use [cpp-httplib](https://github.com/yhirose/cpp-httplib) — single-header, no dependencies
- Listen on port 8420 (configurable via `--port`)
- Route `POST /v1/{method}` with JSON body to handler functions
- Route `GET /health` for health check
- CORS headers: `Access-Control-Allow-Origin: *`

**mDNS:**
- Linux: Avahi via `avahi-client` library (D-Bus)
- Windows: `dns-sd` API (Bonjour for Windows) or mdnsresponder
- Advertise `_kelpie._tcp` with TXT record: id, name, model, platform, engine, width, height, port, version

**Handler wiring:**
- Each handler receives `HandlerContext` (from core-automation) and JSON params
- Returns JSON response
- Handlers call `RendererInterface` methods (EvaluateJs, TakeSnapshot, LoadUrl, etc.)
- Use core-state stores for bookmarks, history, console, network traffic

---

## Phase 2: Linux Headless App

### Entry point (`apps/linux/src/main.cpp`)

```cpp
int main(int argc, char* argv[]) {
    // Parse flags: --headless, --port N, --profile-dir PATH
    // Initialize CEF with appropriate settings
    // If headless: CefSettings.windowless_rendering_enabled = true
    // Start DesktopApp (engine + HTTP server + mDNS)
    // Run event loop
}
```

### Headless shell

- No GTK dependency in headless mode
- CEF off-screen rendering: `OnPaint` captures pixel buffer for screenshots
- Full HTTP/MCP surface active
- Profile directory: `~/.config/kelpie/` (or `--profile-dir`)
- Cookies, bookmarks, history persisted to profile directory

### Device info

- ID: persistent UUID from `~/.config/kelpie/device-id`
- Name: Linux hostname
- Model: from `/sys/devices/virtual/dmi/id/product_name` or `uname`
- Platform: `linux`
- Engine: `chromium`
- IP: from network interfaces
- Memory: from `/proc/meminfo`

### Dockerfile for testing

```dockerfile
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y \
    libx11-6 libxcomposite1 libxdamage1 libxext6 libxfixes3 \
    libxrandr2 libatk1.0-0 libatk-bridge2.0-0 libcups2 \
    libdrm2 libgbm1 libgtk-3-0 libpango-1.0-0 libasound2 \
    libnspr4 libnss3 xvfb avahi-daemon dbus \
    && rm -rf /var/lib/apt/lists/*
COPY build/ /opt/kelpie/
WORKDIR /opt/kelpie
ENV DISPLAY=:99
CMD ["sh", "-c", "Xvfb :99 -screen 0 1920x1080x24 & ./kelpie-linux --headless --port 8420"]
```

### Verification checklist

- [ ] Launches without visible window
- [ ] Responds to `GET /health`
- [ ] `POST /v1/get-device-info` returns correct Linux device info
- [ ] `POST /v1/navigate` loads a page
- [ ] `POST /v1/screenshot` returns PNG data
- [ ] `POST /v1/evaluate` runs JS and returns result
- [ ] `POST /v1/get-bookmarks` / `add-bookmark` work
- [ ] `POST /v1/get-history` shows navigation history
- [ ] `POST /v1/get-network-log` captures traffic
- [ ] `POST /v1/get-console-messages` captures console output
- [ ] mDNS advertisement visible from host (`avahi-browse _kelpie._tcp`)
- [ ] CLI discovers and controls the headless browser

---

## Phase 3: Linux GUI App

### GTK shell

- GTK3 (widely available) or GTK4
- Main window with vertical layout:
  - URL bar (GtkEntry + nav buttons)
  - CEF browser view (embedded via X11 window reparenting)
  - Status bar
- Floating menu / sidebar for settings, bookmarks, history, network inspector

### Views

**URL bar:** GtkEntry with back/forward/reload buttons. Emits navigate on Enter.

**Network inspector:** GtkTreeView with three filter dropdowns:
- Method: All/GET/POST/PUT/DELETE
- Type: All/HTML/JSON/JS/CSS/Image/Font/XML/Other
- Source: All/Browser/JS

**Bookmarks/History:** GtkListBox with URL, title, timestamp.

**Settings:** GtkDialog with port, profile directory, startup URL.

### GUI verification

- [ ] Window opens with URL bar and browser view
- [ ] Navigation works via URL bar and API
- [ ] Bookmarks/history views show data
- [ ] Network inspector shows captured traffic with filters
- [ ] Settings panel saves preferences
- [ ] Same HTTP/MCP surface works in GUI mode

---

## Phase 4: Packaging

- CMake install target produces: `kelpie-linux` binary + CEF resources + locales
- AppImage or tarball for initial distribution
- `make linux` target in root Makefile
- `make linux-headless-docker` for Docker image

---

## Build requirements

- CMake 3.16+
- C++17 compiler (GCC 9+ or Clang 10+)
- CEF binary distribution (Linux 64-bit)
- cpp-httplib (header-only, fetched by CMake)
- nlohmann/json (already in native/ CMake)
- GTK3 dev libraries (GUI mode only)
- Avahi client libraries (mDNS)
- For Docker testing: Docker on host machine

---

## CLI flags

```
kelpie-linux [options]
  --headless          Run without visible window
  --port PORT         HTTP server port (default: 8420)
  --profile-dir DIR   Data directory (default: ~/.config/kelpie)
  --url URL           Initial URL to load
  --width WIDTH       Viewport width (default: 1920)
  --height HEIGHT     Viewport height (default: 1080)
```

---

## Cross-Provider Review

Reviewed with `claude -p` on 2026-04-01.

Accepted findings:
- `CefExecuteProcess()` must run before any other startup work when CEF is compiled in.
- GTK and CEF must share the main thread through `CefDoMessageLoopWork()` on a GLib timer rather than `CefRunMessageLoop()`.
- Avahi must stay build-optional so minimal Linux and CI environments still compile.
- Headless mode must skip GTK entirely.
- Missing CEF support must return a structured 503 error for screenshot-style endpoints instead of empty data or crashes.

Rejected findings:
- Splitting the app into separate GUI and headless binaries was rejected. The current requirement is a single `kelpie-linux` binary with runtime flags and optional dependency gates.
- Dropping the network inspector UI was rejected. The requested file structure includes it, so the initial implementation keeps a minimal GTK inspector while the HTTP surface remains the real source of truth.
