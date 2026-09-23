# Screenshots and waits an agent can rely on

Status: design, reviewed before implementation (see [Cross-Provider Review](#cross-provider-review)). Branch `fix/agent-screenshots-and-waits`.

## Why

An agent driving the Windows browser over `kelpie --browser <alias> mcp` hit
eight problems on 2026-09-22. The measurements behind them (result shapes,
sizes, timings) come from an MCP probe that spoke JSON-RPC to the CLI over
stdio against a running `kelpie.exe`:

- A screenshot of any real page is 0.5–0.9 MB by the time it reaches the
  client, because the base64 image is sent three times.
- Every call stops at 10 s, whatever `timeout` the agent passed.
- Page text has no ceiling. Wikipedia's readable text came to about 80 KB.
- Windows screenshots can only be full-size PNG.
- A minimised window returns a stale image, or a 158×14 one, and still
  reports `success: true`.
- A profile directory of 194 characters does not start.
- `kelpie_discover` never finds the Windows browser.
- `wait_for_navigation` does not wait after a click.

## Contents

| Item | Problem | Where the change lands | Who implements it |
|---|---|---|---|
| C1 | Screenshot base64 sent three times | `packages/cli/src/mcp/server.ts` (split out), `native/engine-chromium-desktop/src/desktop_mcp_server.cpp` | CLI, then native |
| C2 | Every call cut at 10 s | `packages/cli/src/mcp/server.ts`, `tools.ts` | CLI |
| C3 | Page text has no ceiling | CLI MCP layer, and the native `/mcp` | CLI, then native |
| C4 | Windows screenshots are full-size PNG only | Native engine (CDP) and handler; CLI schema, pass-through and an option check | Native and CLI |
| C5 | Minimised window returns a wrong image | Native engine | Native |
| C6 | Long profile paths do not start | `apps/windows/src/profile_session.cpp` | Native |
| C7 | `kelpie_discover` misses Windows | CLI discovery (see the deviation below) | CLI |
| C8 | `wait_for_navigation` ignores page-started loads | Native engine and `evaluate_handler.cpp` | Native |

The protocol changes are listed together in [Protocol changes](#protocol-changes).

---

## C1 — One copy of each screenshot

**Root cause.** `portableScreenshotResult` (`server.ts:178-189`) spreads the
whole device response, `image` included, into the metadata. That metadata then
becomes both the text item and `structuredContent`, and the image item carries
the base64 a third time. The native desktop `/mcp` server repeats the same
pattern (`desktop_mcp_server.cpp:357-369`): its text item is `body.dump()` and
`structuredContent` is `body`.

**Change.**
- Screenshot formatting moves out of `server.ts` into
  `packages/cli/src/mcp/screenshot-result.ts`. It is one responsibility, and
  the move keeps `server.ts` well under 500 lines.
- For a portable result, `metadata` is the device response without `image`,
  plus `mimeType` and `imageBytes` (the decoded length, computed from the
  base64 length without decoding). The text item is `JSON.stringify(metadata)`,
  `structuredContent` is `metadata`, and the image item is the only copy of the
  base64.
- The native-resolution branch (save to a file, return a `resource_link`)
  already follows this rule and does not change.
- The native `/mcp` server applies the same rule to the text item and to
  `structuredContent` for `screenshot` and `screenshot-annotated`.

**Tests.**
- `tests/mcp/server.test.ts`:
  - The base64 string appears exactly once in `JSON.stringify(result)`.
  - Neither the text item nor `structuredContent` has an `image` key.
  - `imageBytes` is correct.
- The existing test "returns portable MCP image content for Windows
  screenshots" pins the triple copy today. It is rewritten.
- `tests/mcp/windows-local-stdio.test.ts` asserts the same rule through the
  real MCP SDK over stdio.
- Native: `test_desktop_mcp_server.cpp` asserts one copy.

## C2 — A tool's own timeout

**Root cause.** `registerBrowserTool` calls `sendCommand(device, method, body)`
(`server.ts:114`), and that call uses its 10 s default (`http-client.ts:157`).
The `timeout` argument is forwarded to the device, but the CLI aborts its own
HTTP request at 10 s. The probe measured this: a `wait_for_element` with a
20 s timeout came back after 10,017 ms as the CLI's own `TIMEOUT`.

The desktop app clamps every `timeout` to 1–30000 ms (`ControlTimeout`,
`handler_support.h:229-232`), and its native `/mcp` schema declares
`maximum: 30000`. iOS, Android and macOS do not clamp. Today they are cut at
10 s over MCP anyway.

**Change.**
- The tools that take a `timeout` are `kelpie_click`, `kelpie_fill`,
  `kelpie_wait_for_element` and `kelpie_wait_for_navigation` (the `timeout`
  fragment, `tools.ts:36`). The rule is keyed on the schema: any browser tool
  whose schema declares `timeout` gets
  `requestTimeoutMs = min(args.timeout ?? 10_000, 30_000) + 5_000`. Every
  other tool keeps 10 000 ms.
- The 5 s margin covers device-side overshoot and the network. On iOS and
  macOS, a poll loop with a 100 ms sleep plus an evaluate per iteration can
  run about 10% past the requested time.
- The `timeout` schema becomes `z.number().int().min(1).max(30000)`, and its
  description states the maximum. A caller that asks for 60 s gets a
  validation error, rather than believing it waited 60 s.
- One number, `MAX_TOOL_TIMEOUT_MS = 30_000`, bounds every platform. It
  matches the desktop app's clamp and its published `/mcp` schema.
- The timeout helper and its constants live in `tools.ts`, beside the
  `timeout` fragment.
- Two schema changes reject values the old schema accepted:
  - `timeout` above 30 000 ms. Such values never worked over MCP, because the
    CLI cut every call at 10 s.
  - `quality` of 0 or a fraction.

  `docs/cli.md` records both as a tightening.
- Known limit: the margin is measured from when the CLI sends the request.
  A call that the device holds behind other work can still hit the CLI's
  deadline first. An agent drives one tab at a time over stdio, so this is
  recorded, not engineered around.

**Tests.** `tests/mcp/request-timeout.test.ts` mocks `sendCommand` with
`vi.mock` and connects a client to the real `createMcpServer` over
`InMemoryTransport`:

| Call | Timeout passed to `sendCommand` |
|---|---|
| `kelpie_wait_for_element` with `timeout: 20000` | 25 000 ms |
| `kelpie_wait_for_element` with no `timeout` | 15 000 ms |
| `kelpie_navigate` | 10 000 ms |

`timeout: 30001` is rejected by the schema, and `sendCommand` is not called.

## C3 — Page text has a ceiling

**Root cause.** `kelpie_get_page_text` returns whatever the page holds. No
layer bounds it.

**Change.**
- The CLI tool gains `maxChars` (`z.number().int().min(1)`, default 20 000).
- The CLI does not forward it to the device. Truncation happens in the MCP
  layer, so iOS, Android, macOS and Windows all get the ceiling from one
  implementation.
- The text is in `content` on iOS, Android and macOS, and in `text` on desktop
  Chromium.
- When the text is longer than `maxChars`:
  - The text field is cut to `maxChars` UTF-16 code units, without splitting
    a surrogate pair. The native `/mcp` holds UTF-8, so it counts the same
    UTF-16 units while walking the UTF-8: one unit per code point below
    U+10000 and two for a 4-byte sequence. It never cuts inside a sequence or
    a pair, so both surfaces report the same `totalChars` and cut at the same
    place.
  - The result gains `truncated: true`, `totalChars: <original length>` and a
    `note`, for example: `"Page text truncated to 20000 of 80359 characters.
    Pass a larger maxChars, or a selector for the part you need."`
- Otherwise the result gains `truncated: false`. Other device fields (`length`,
  `excerpt`, `wordCount`) are left as the device sent them.
- The code lives in `packages/cli/src/mcp/page-text-limit.ts`.
- The native `/mcp` also exposes `kelpie_get_page_text` and rejects unknown
  arguments (`additionalProperties: false`). It gains the same `maxChars`
  option and the same truncation fields, so both MCP surfaces agree.
- `/v1/get-page-text` over HTTP stays unbounded.

**Tests.**
- `tests/mcp/page-text-limit.test.ts` covers:
  - an 80 000-character `content`, which comes back cut to 20 000 with the
    note;
  - the desktop `text` field;
  - text under the limit, which gets `truncated: false`;
  - a custom `maxChars`;
  - a surrogate pair on the boundary;
  - that `maxChars` is never forwarded to the device.
- Native: `test_desktop_mcp_server.cpp`, including the same astral-character
  boundary case, so the two implementations are held to one answer.

## C4 — Windows screenshots: JPEG, quality, maxWidth

**Root cause.** Three separate limits:
- The handler rejects any `fullPage` key, even `false`, and any format other
  than PNG (`screenshot_handler.cpp:18-22`). `kelpie screenshot` always sends
  `fullPage: false`, so it cannot work against Windows.
- `DesktopDevToolsSession::ScreenshotParams` refuses anything but PNG
  (`desktop_devtools.cpp:286-295`).
- `DesktopEngine::Screenshot` passes it an empty object
  (`desktop_engine_control.cpp:519`).

**Deviation from the follow-up text: CDP instead of WIC.** CDP's
`Page.captureScreenshot` already takes `format: "jpeg"`, `quality` and
`clip.scale`, so Chromium does the encoding and the downscaling itself:
- There is no second encoder and no decode-and-re-encode pass.
- There is no Windows-only code, so the Linux app (the same engine) gets the
  feature too.
- It adds no dependency, which was the constraint the WIC suggestion was
  written to satisfy.

WIC is the fallback only if the live check below shows that `clip.scale`
misbehaves under CEF windowed rendering. If that happens, this section is
updated first.

**Change.** Native:

1. `ScreenshotParams` accepts:
   - `format` `png` | `jpeg`;
   - `quality`, an integer 1–100. It is applied to JPEG and ignored for PNG,
     as on iOS, Android and macOS;
   - `maxWidth`, an integer 1–16384.

   Anything else is `INVALID_PARAMS`.
2. Each capture first reads `Page.getLayoutMetrics`. From it the engine takes
   the CSS visual viewport (`pageX`, `pageY`, `clientWidth`, `clientHeight`)
   and computes the device pixel ratio as device `clientWidth` divided by CSS
   `clientWidth`.
3. When `maxWidth` is smaller than `clientWidth × dpr`, the capture passes
   `clip: {x: pageX, y: pageY, width: clientWidth, height: clientHeight,
   scale: maxWidth / (clientWidth × dpr)}`. The image is never upscaled.
4. `format`, `width` and `height` are read from the encoded image's own
   header, not from the request or from arithmetic. The PNG `IHDR` and the
   JPEG `SOF0`/`SOF2` markers are parsed by a small pure function that
   decodes only a prefix of the base64.

   `ParseScreenshotResult` hard-codes `image/png` today. After this change a
   wrong label, or a wrong scale formula, shows up in the metadata and in the
   CLI's option check, instead of passing silently.

   The formula in step 3 assumes that CDP multiplies `clip.scale` by the
   device pixel ratio. That is how a Puppeteer `deviceScaleFactor` screenshot
   behaves, but it is unverified at a ratio other than 1, because this
   machine runs at 1. If the assumption is wrong, the header-read width
   exposes it.
5. The response carries the metadata iOS, Android and macOS already send:
   - `width`, `height`: the encoded image's pixel size, from step 4;
   - `viewportWidth`, `viewportHeight` (CSS);
   - `devicePixelRatio`;
   - `imageScaleX`, `imageScaleY`;
   - `format`;
   - `resolution: "viewport"`.

   With this, a scaled image still maps back to CSS coordinates.
6. `fullPage: false` is accepted. `fullPage: true` stays `INVALID_PARAMS`.
7. The capture code moves out of `desktop_engine_control.cpp` (707 lines,
   already over the limit) into `desktop_engine_screenshot.cpp`.
8. The native `/mcp` schema changes from `format: {const: "png"}` to the
   format enum plus `quality` and `maxWidth`.

CLI:

- `kelpie_screenshot` changes:
  - `quality` becomes `z.number().int().min(1).max(100)`;
  - it gains `maxWidth` (`z.number().int().min(1).max(16384)`);
  - `screenshotBody` passes both through unchanged;
  - the description says which platforms honour `maxWidth`: Windows and
    Linux.
- `kelpie screenshot` gains `--max-width <px>`.
- **Clear error when a device does not honour an option.** After a
  successful capture, `screenshotOptionError(request, response, device)` in
  `packages/cli/src/client/screenshot-options.ts` fails in either of these
  cases. It lives in the client layer because both the MCP server and the
  `kelpie screenshot` command use it.
  - `format: "jpeg"` was requested and the response format is not `jpeg`;
  - `maxWidth` was requested and the response `width` is greater than
    `maxWidth`.

  The failure is `SCREENSHOT_OPTION_UNSUPPORTED`:
  - It is a CLI-generated code, like `DEVICE_NOT_FOUND`.
  - The message names the option, what came back, the device and its
    platform, and the fix (update the app, omit the option, or shrink the
    window with `kelpie_resize_viewport`).
  - It does not quote a version. An alias device's `version` is its
    readiness record's format version (`helpers.ts:45`), not the app's, so it
    would mislead.
  - The result carries no image. The point of `maxWidth` is to keep an
    oversized image away from the client.
- The check is on the result, not on a platform table, so it also catches a
  new CLI talking to an old app. This relies on `width` being the image's
  pixel width. iOS, Android and macOS already send that, and Windows does
  once this change lands.
- A device that refuses an option itself, such as an old Windows build
  answering `INVALID_PARAMS: format must be png`, is passed through
  unchanged. That error already names the option.
- The `kelpie screenshot` command runs the same check.

**Tests.**
- Native unit tests for `ScreenshotParams`:
  - a JPEG request with quality;
  - quality out of range;
  - `maxWidth` rejected when it is 0 or not an integer;
  - `fullPage: false` accepted and `fullPage: true` rejected.
- Native unit tests for the scale arithmetic, as a pure function, including
  a device pixel ratio of 2.
- Native unit tests for the header reader: PNG, baseline JPEG, progressive
  JPEG, and a truncated or garbage prefix.
- CLI unit tests:
  - the schema ranges;
  - pass-through of `maxWidth` and `quality`;
  - the option check (format mismatch; width over `maxWidth`; width equal to
    `maxWidth`; `maxWidth` without a `width` in the response);
  - the command flag.
- Live: a JPEG at quality 60 and `maxWidth` 960 of Hacker News and of a
  Wikipedia article. The decoded image must be at most 960 px wide and under
  200 KB of base64.

## C5 — A minimised window answers with an error

**Root cause.** A minimised top-level window stops producing frames. CDP then
hands back the last frame, or a tiny surface, and the handler reports success.
The page itself does not know it is hidden: `evaluate` reported
`visible 1918x957` while the window was minimised.

**Change.**
- In the new `desktop_engine_screenshot.cpp`, on the UI thread and before
  `Page.captureScreenshot`, the engine checks
  `IsIconic(GetAncestor(host->GetWindowHandle(), GA_ROOT))`. This check is
  under `#if defined(_WIN32)`.
- When the window is minimised, the engine fails with `WINDOW_MINIMIZED` and
  the message "The browser window is minimised, so it has no current image.
  Restore the window and retry."
- Both `screenshot` and `screenshot-annotated` go through this path.
- The new code maps to HTTP 409, because the request conflicts with the
  window's state. It is added to:
  - the native `ErrorCode` enum and its tables;
  - the shared `ErrorCode` and `ErrorHttpStatus`;
  - the error table in `docs/api/README.md`.
- Other methods keep working while the window is minimised, as they do
  today.
- Linux has no check yet. `docs/functionality.md` states this.
- The check and the capture are not atomic. A minimise that lands between
  them can still yield one stale frame. The docs say "returns an error while
  the window is minimised", not "never returns a stale image".

**Tests.**
- Native: the router maps `WINDOW_MINIMIZED` to 409.
- Live: minimise the window with
  `ShowWindow(hwnd, SW_MINIMIZE)` from PowerShell. `kelpie_screenshot` must
  return `isError` with `WINDOW_MINIMIZED`. After a restore it must succeed.
  Both assertions are made on the steady state, after the window has settled.

## C6 — Long profile paths start

**Root cause.** The readiness record is written to
`readiness.json.<64-hex launch id>.tmp`, then renamed
(`profile_session.cpp:113-114`). The suffix adds 69 characters to the path.
With long paths disabled (`LongPathsEnabled=0`), a 194-character profile
directory produces a 278-character temp path, and startup fails with "Unable
to write the readiness record". The long-path manifest entry does nothing
while the machine policy is off.

**Change.**
- The temp file becomes a sibling in the same directory named
  `~<first 8 hex of the launch id>.tmp`. That is 13 characters, shorter than
  `readiness.json` (14), so whenever the final path is valid the temp path is
  valid too.
- The 8-hex suffix keeps two launches apart when they share an explicit
  `--readiness-file` directory. The profile lock already serialises launches
  of one profile.
- When a write fails and the path is 260 characters or longer, the error names
  the path length and the Windows limit. It no longer says only "Unable to
  write".

**Tests.**
- `apps/windows/tests/profile_session_test.cpp`:
  - a profile directory of 244 characters, so that `readiness.json` is exactly
    259 characters, publishes its record;
  - no temp file is left behind;
  - a path over the limit fails with the length in the message.
- Live: launch with a 194-character profile under
  `%LOCALAPPDATA%\Kelpie\profiles\`. This is the path length from the evidence.

## C7 — `kelpie_discover` finds the Windows browser

**Deviation from the follow-up text: no mDNS on Windows.** The follow-up asks
for Windows to advertise itself on mDNS, "so `kelpie discover` and
`kelpie_discover` find it". The goal holds, but mDNS is the wrong way to reach
it:

- **Windows mDNS was removed on purpose.** Commit `63ed078`
  ("integrate sandboxed CEF desktop runtime") made the control plane
  loopback-only and removed `StartMdns()`/`StopMdns()`. The HTTP server binds
  `127.0.0.1`, rejects any non-loopback `Host` header, and requires the
  per-launch token from the protected readiness file
  (`desktop_http_server.cpp:125-139`). `MdnsWindows` was left compiled but
  never started.
- **Advertising would announce an address nobody can use.** The advert would
  carry the machine's LAN addresses. No LAN peer can connect to them, and a
  peer without the token cannot drive the browser anyway. The advert would
  also broadcast the machine's name and model to the network.
- **Advertising would break `kelpie discover`.** That command probes loopback
  only when the mDNS browse is empty (`commands/discover.ts:18-24`). With an
  advert present, it would list the LAN address and skip the probe, so every
  command would fail to connect.
- **The real cause is narrower.** `kelpie discover`, `kelpie describe` and the
  implicit device lookup all fall back to the loopback probe. The MCP tool
  `kelpie_discover` does not (`server.ts:337-343`). `kelpie discover` already
  finds the browser; the evidence shows it did.

**Change.**
- A new `packages/cli/src/discovery/discover.ts` exports
  `discoverDevices(scanMs)`: an mDNS scan enriched with capabilities, then the
  loopback probe when the scan found nothing.
- Both `commands/discover.ts` and the `kelpie_discover` MCP tool use it, so
  the two cannot drift apart again.
- `mdns_windows.h` gains a two-line comment saying why the class is not
  started, so the next reader does not "fix" it.
- Deleting the class is left as a follow-up.

**Tests.** `tests/mcp/discover.test.ts`, with scan and probe mocked:
- When mDNS is empty and the probe finds a device, `kelpie_discover` returns
  it.
- When mDNS finds a device, the probe is not called.

**Live check.** `kelpie_discover` through the stdio probe lists the running
Windows instance.

## C8 — `wait_for_navigation` after a click

**Root cause.** The engine counts only navigations requested through the API:
`Navigate`, `Back`, `Forward` and `Reload` increment `navigation_requested`
(`desktop_engine_control.cpp:458-485`). The wait compares against that count
(`evaluate_handler.cpp:76-112`), with this result:
- When a click starts the navigation, the count does not move.
- If nothing was ever requested, the wait fails with "No navigation has been
  requested".
- If an earlier API navigation had completed, the wait returns that stale
  success at once.

**Semantics after this change.** `wait-for-navigation` waits for the
main-frame navigation that started after the tab's most recent
navigation-capable action, whether the API or the page started it:

- If that navigation has already finished, the wait returns at once.
- If it is still loading, the wait returns when it finishes.
- If none has started, the wait waits up to `timeout` for one to start and
  finish. When the time runs out it returns `TIMEOUT`, with the message "No
  navigation started within N ms".
- A load error on that navigation returns `NAVIGATION_ERROR`, as today.

The navigation-capable actions are `navigate`, `back`, `forward`, `reload`,
`click`, `tap`, `fill`, `type`, `press-key`, `select-option`, `check`,
`uncheck` and `evaluate`. A fresh tab has had no action, so its baseline is 0
and its first load counts.

**Change.** The per-tab counters move into a small pure struct,
`NavigationTracker` (`native/engine-chromium-desktop/src/navigation_tracker.h`),
that can be unit-tested without CEF.

| Field | Meaning |
|---|---|
| `started` | Main-frame navigations started, by the API or the page |
| `finished` | Navigations that finished loading |
| `baseline` | The value of `started` at the last navigation-capable action |
| `error` | The load error of the latest navigation, if any |

The events that drive it:

| Event | Effect |
|---|---|
| `MarkAction()` | `baseline = started` |
| `ApiNavigationRequested()` | `MarkAction()`, then `++started`, and `error` is cleared |
| `OnLoadStart` for the main frame, when `started == finished` | `++started` and `error` is cleared. This is a page-started load; the API's own load is not counted twice |
| `OnLoadingStateChange(false)` with no error | `finished = started` |
| `OnLoadError` for the main frame, except `ERR_ABORTED` | Records `error` |

- `OnLoadStart` is new wiring. `DesktopCefClient` implements `OnLoadEnd`,
  `OnLoadError` and `OnLoadingStateChange` today, but not `OnLoadStart`.
- `ERR_ABORTED` is what CEF reports when a newer navigation supersedes a load,
  or a link turns out to be a download. It is not a failure of the navigation
  being waited for. Today's `OnLoadError` records it as one; the tracker
  ignores it.
- **Thread affinity.** Every tracker read and write happens on the CEF UI
  thread. The load events already run there, and the wait reads the state
  through `RunOnUi`.
- `MarkAction` runs in a UI task that completes before the action dispatches
  its input. The handler resolves the tab, runs `MarkAction` through
  `RunOnUi`, then acts. A load that the action starts can therefore only be
  counted after the baseline is taken.

- The interaction handlers and `evaluate` call `MarkAction` after resolving
  the tab and before acting.
- The wait reads `baseline` once, when it starts, and then polls
  `Since(baseline)`, which answers not-started, loading, finished or failed.
- Same-document navigations (`pushState`, hash changes) do not fire
  `OnLoadStart` and are not counted. That is the same as today.

**Tests.**
- `NavigationTracker` unit tests:
  - an API navigation;
  - a page navigation after a click;
  - a navigation that finished before the wait started;
  - no navigation at all;
  - a load error;
  - a second page load while the first is still loading;
  - an `ERR_ABORTED` followed by a completed load, which succeeds.
- Live, on a fixture page with a link and a button that does not navigate:
  - click the link, then `wait_for_navigation` returns and the URL has
    changed;
  - click the button, then `wait_for_navigation` with `timeout: 2000` returns
    `TIMEOUT`;
  - `navigate` followed by `wait_for_navigation` still works on a fast page;
  - a button that calls `history.pushState` does not count as a navigation,
    so the wait times out.

---

## Protocol changes

**HTTP `/v1/screenshot`**
- New optional `maxWidth`: an integer. The image's pixel width is at most this
  value; the image is never upscaled and keeps its aspect ratio.
- `width` and `height` are the encoded image's pixel size on every platform.
- On desktop Chromium, `format: "jpeg"`, `quality` and `maxWidth` are honoured,
  `fullPage: false` is accepted, and the viewport-mapping metadata is added.
- A new error, `WINDOW_MINIMIZED` (409).
- iOS, Android and macOS ignore `maxWidth` for now (see Out of scope).

**HTTP `/v1/wait-for-navigation` on desktop Chromium.** The semantics change as
described in C8.

**MCP (CLI)**
- `kelpie_screenshot`:
  - gains `maxWidth`;
  - `quality` becomes an integer 1–100;
  - the result is metadata-only text plus `structuredContent` plus a single
    image item;
  - a new CLI error, `SCREENSHOT_OPTION_UNSUPPORTED`.
- `kelpie_get_page_text` gains `maxChars` (default 20 000), and its result
  gains `truncated` (always), plus `totalChars` and `note` when it truncated.
- `timeout` on `kelpie_click`, `kelpie_fill`, `kelpie_wait_for_element` and
  `kelpie_wait_for_navigation`:
  - it is an integer from 1 to 30000;
  - the HTTP request waits `timeout + 5 s`, or 15 s when `timeout` is
    omitted.
- `kelpie_discover` falls back to the loopback probe.
- The catalogue digest reported by `kelpie describe` changes. That is the
  intended signal to integrators that the catalogue changed.

**MCP (native `/mcp`)**
- Screenshots are sent once.
- The screenshot schema gains the `jpeg` format, `quality` and `maxWidth`.
- `kelpie_get_page_text` gains `maxChars` with the same truncation fields.

## Docs that change with the code

| File | What changes |
|---|---|
| `docs/api/core.md` | `screenshot` (`maxWidth`, metadata, `WINDOW_MINIMIZED`) and `waitForNavigation` (the new semantics) |
| `docs/api/llm.md` | `getPageText`: both response shapes, and the MCP `maxChars` truncation fields |
| `docs/api/README.md` | Error table: `WINDOW_MINIMIZED`, plus a note on the CLI's `SCREENSHOT_OPTION_UNSUPPORTED` |
| `docs/cli.md` | `kelpie screenshot --max-width`, and an MCP note on timeouts, the screenshot result shape and `maxChars` |
| `docs/functionality.md` | The Windows screenshot paragraph (JPEG, `maxWidth`, the minimised error) |

## Verification plan

**CLI.**
- `pnpm --filter @unlikeotherai/kelpie test`
- `pnpm --filter @unlikeotherai/kelpie lint`
- `pnpm -r build`
- `tsc --noEmit` for the CLI.

**Native.**
- `scripts/build-windows.ps1`, which runs CTest.
- The acceptance harness at `tests/windows/run-release-acceptance.mjs`.
- A live run of the MCP probe against a copy built from this worktree, with
  its own `--profile-dir` and `--port`. It covers navigate, click then wait,
  a JPEG under 200 KB, the minimised error, a long profile and
  `kelpie_discover`.

## Out of scope (recorded, not fixed here)

- `maxWidth` on iOS, Android and macOS. The CLI's option check makes the gap
  explicit until they land it; iOS and Android must land it together.
- Other tools that the CLI still cuts at 10 s: `kelpie_play_script`,
  `kelpie_safari_auth`, `kelpie_ai_ask` and `kelpie_ai_load`. They take no
  `timeout` argument, so C2's rule does not reach them.
- `kelpie_group_screenshot` returns each device's base64 inside its text
  result.
- Screenshots of a background tab on Windows, whose window is hidden. A
  hidden window may have the same stale-frame problem as a minimised one.
- The loopback probe loses the real device id, the engine and the display
  size, because it expects nested `get-device-info` fields while desktop
  Chromium sends them flat.
- Deleting `MdnsWindows`.

---

## Cross-Provider Review

**How it ran.** Reviewer: `kimix exec` (provider `kimi`, model `k3-256k`), run
on 2026-09-23 against this document as first committed (`ea9dec6`). It was
told to be adversarial, to read only eight source files, and to answer in
under 800 words. It finished in about three minutes and used 42,758 tokens.

It could not check claims about files outside those eight. The claim it
singled out — that iOS, Android and macOS report `width` as the image's pixel
width — was checked afterwards:
- iOS: `apps/ios/Kelpie/Handlers/HandlerContext.swift:28`
- macOS: `apps/macos/Kelpie/Handlers/ScreenshotHandler.swift:28`
- Android: `apps/android/app/src/main/java/com/kelpie/browser/handlers/ScreenshotHandler.kt:61`

All three set `width` to the rendered image's width.

Each finding and what was done with it:

1. **High, C8: `ERR_ABORTED` counted as a failure. Accepted.** CEF reports it
   for a superseded load or a download. The tracker now ignores it, and a new
   test covers "aborted, then completed".
2. **High, C8: race between the baseline and `OnLoadStart`. Accepted in part.**
   The race as described is reversed: the baseline is taken *before* the
   action, so the action's own load always counts after it. The thread
   affinity was unstated, though. The design now puts every tracker access on
   the CEF UI thread, with `MarkAction` in a UI task that completes before the
   input is dispatched.
3. **High, C4: `clip.scale` off by the device pixel ratio. Not accepted as
   stated; the risk it points at is real.** Chromium multiplies `clip.scale`
   by the device scale factor, which is how Puppeteer `deviceScaleFactor`
   screenshots behave, so `maxWidth / (clientWidth × dpr)` is the expected
   formula. Neither side verified it at a ratio other than 1. Two changes
   follow:
   - `width` and `height` now come from the encoded image's header, not from
     arithmetic, so a wrong formula is visible rather than silent.
   - A unit test pins the formula at dpr 2. The unverified live case is
     recorded in C4.
4. **Medium, C4: the MIME type taken from the request. Accepted.** The format
   comes from the image header, the same parse as finding 3.
5. **Medium, C2: the margin does not cover queueing. Accepted as a documented
   limit.** It is not engineered around: requests are not serialised behind a
   whole-tab lease for their full duration, and an agent drives one tab at a
   time.
6. **Medium, C8: a page load started during an in-flight load is merged.
   Rejected.** `finished` advances only when CEF reports that loading has
   stopped, and it does not report that until the superseding load has
   finished too. The merged count cannot produce a "finished" answer for a
   superseded load. A test ("a second page load while the first is still
   loading") pins this.
7. **Medium, C8: `OnLoadStart` is not wired today. Accepted.** The design says
   so. A live check that `pushState` is not counted was added.
8. **Medium, C3: UTF-16 on one surface, UTF-8 on the other. Accepted.** Both
   surfaces count UTF-16 code units. The native side counts them while walking
   the UTF-8, and a shared astral-boundary case is tested on both.
9. **Medium, C6: a custom `--readiness-file` shorter than 13 characters.
   Rejected.** The CLI and the acceptance harness always use `readiness.json`
   inside the profile. A tiny custom name in a directory near `MAX_PATH` is
   not a case anyone hits. The improved error message still names the path
   length if it happens. Extended-length (`\?\`) paths are the complete fix;
   they are recorded as a follow-up, because CEF's own profile paths would
   then be the limit.
10. **Low, C6: two launches whose ids share the first 8 hex characters.
    Rejected.** The chance is 1 in 2³², and it needs two launches sharing an
    explicit readiness directory at the same moment.
11. **Low, C2: `.max(30000)` and integer `quality` are breaking. Accepted as a
    documentation point.** Values above 10 s never worked over MCP, so no
    working caller breaks. `docs/cli.md` records both as a tightening.
12. **Low, C4: add `maxWidth` and `quality` to `kelpie_screenshot_annotated`.
    Rejected for now.** No platform could honour them there today. Windows
    does not expose the annotated tool, and iOS, Android and macOS do not know
    `maxWidth`, so every oversized result would be refused. Add them when a
    platform supports them.
13. **Low, C5: the minimised check is not atomic with the capture. Accepted.**
    This is a wording change, and the live check asserts the steady state.

---

## Implementation notes: native side

These notes record where the native implementation refined or departed from
the design above, and what the live checks measured. They cover C1 and C3 on
the app's own `/mcp`, and C4 to C8. The live checks ran against a build from
this branch on this machine (device pixel ratio 1), driven through
`kelpie --browser <alias> mcp`.

**C4. CDP, as designed; WIC was not needed.** `clip.scale` behaves under CEF
windowed rendering. JPEG quality 60 at `maxWidth` 960:

| Page | Image | JPEG | Whole MCP response |
|---|---|---|---|
| Hacker News | 960×483 | 35 KB | 47.9 KB |
| Wikipedia article | 960×483 | 51 KB | 69.4 KB |

The evidence measured 529 KB and 911 KB for the same pages. One refinement
came from the live check. `Page.getLayoutMetrics`' CSS visual viewport
excludes the page's scrollbars, but an unclipped capture includes them: a
1921 px viewport came back as a 1936 px image. Two consequences:

- A `maxWidth` between the two widths skipped the clip and returned an image
  wider than asked.
- `imageScaleX` read 1.0078 instead of 1.

So a `maxWidth` capture is always a clip of the visual viewport, at a scale
capped at 1, and the engine reports the scale it captured at
(`image_scale`) rather than the handler dividing widths. The dpr-2 formula
is pinned by a unit test only; this machine runs at 1.

**C5.** Besides `IsIconic` on the root window, a tab host window with an
empty client area also returns `WINDOW_MINIMIZED`, with its own message.
Live:

- While minimised, both PNG and JPEG screenshots returned `WINDOW_MINIMIZED`;
  `evaluate`, `navigate` and `wait-for-navigation` kept working.
- After restoring, screenshots succeeded again.

**C6.** As designed. In addition, the profile-lock failure no longer reports
every error as "This profile is already in use": only a sharing violation
means that, and a lock path of `MAX_PATH` or more names its length. The
stale-record check uses the non-throwing `exists()`, so an over-long path
reaches that explanation instead of an exception. Live, a 194-character
profile under `%LOCALAPPDATA%\Kelpie\profiles\` launched, published its
readiness record, and could be driven over MCP.

**C7. No native change.** The task text asked for `MdnsWindows` to be
started. This design rejects that for the reasons in C7, which were
verified before implementing:

- the listener refuses a non-loopback bind and a non-loopback `Host`
  header;
- commit 63ed078 removed `StartMdns`.

Live, `kelpie_discover` listed this build (`local:127.0.0.1:8426`) through
the loopback probe.

**C8. Two refinements to `NavigationTracker`.**

- `MarkAction()` sets `baseline = finished`, not `started`. A load that is
  still in flight when an action runs therefore still counts, and a wait
  after it waits for that load to finish.
- A main-frame `OnLoadError` while the tab is idle counts as a navigation.
  CEF never calls `OnLoadStart` for a navigation that fails before commit,
  so a page-started navigation to an unreachable address would otherwise
  time out as "No navigation started".

`ERR_ABORTED` also leaves the tab's `loading` flag alone, since it says
nothing about the load now in progress.

A third fix came from the live check. The last poll of a wait only gets what
is left of the timeout, and when the UI thread did not answer in those
milliseconds, the caller got RunOnUi's generic "Browser operation timed
out". A poll now gets the remaining time rounded up, and at least 50 ms. A poll
that times out has therefore always run past the deadline, and ends the
wait with the wait's own message. Truncating the budget to whole
milliseconds had left the last poll 0 or 1 ms.

Live results for C8:

| After | Result |
|---|---|
| Click on a link | 23 ms |
| Click on a slow link | 1545 ms |
| `evaluate` that navigates | Followed |
| `back` | 48 ms |
| Click that does not navigate | `TIMEOUT` after 2 s: "No navigation started within 2000 ms" |
| `pushState` | `TIMEOUT` after 2 s: "No navigation started within 2000 ms" |
| API navigation that fails before commit | `NAVIGATION_ERROR` |
| Page navigation that fails before commit | `NAVIGATION_ERROR` |

**C1 and C3 on the app's own `/mcp`.** Both landed as designed. Live:

- A JPEG screenshot's base64 appeared exactly once in the response.
- `kelpie_get_page_text` with `maxChars` 500 cut 77,395 characters with the
  note.

**Structure.** `desktop_engine_control.cpp` was 691 lines. The move-only
split leaves it at 457 lines of tab lifecycle, the UI-thread bridge,
`Evaluate` and `DevTools`. Navigation moved to `desktop_engine_navigation.cpp`,
and cookies, trusted input and dialogs to `desktop_engine_page.cpp` (since
replaced by main's own split; see "Merging main's release-gate fixes").

**Found along the way.**

- **`kelpie browser launch <name> --port N` always launched on 8420.** The
  program-level `--port` took the value. Fixed.
- **A second Kelpie can bind a loopback port another Kelpie already
  listens on.** cpp-httplib sets `SO_REUSEADDR`, after which Windows
  rejects `SO_EXCLUSIVEADDRUSE`. Recorded as a separate task, not fixed
  here.
- **The release acceptance harness (not run by CI) had four defects that
  kept it from starting or comparing correctly.** They are fixed: the
  hidden spawn, the double-unwrapped evaluate result, the non-canonical URL
  comparison, and the CLI phase's fixed port. It still does not pass end to
  end on this machine, because of four failures that predate this change:
  - the occupied-port check expects the app to exit;
  - press-key's keydown is not delivered;
  - a click that opens `alert()` blocks for 10 s;
  - a `set-cookie` it expects to be refused succeeds.

  In a local run with those steps skipped, the screenshot and wait checks
  this change added passed. The run stopped at the cookie step, before the
  harness's MCP and CLI phases. The one-copy `/mcp` screenshot and the
  CLI's `--port` were checked directly instead.

### Cross-Provider Review of the native implementation

**How it ran.** Reviewer: `kimix exec` (provider `kimi`, model `k3-256k`),
on 2026-09-23. It was told to be adversarial and read-only, and to look for
event sequences that give a wrong wait result or an oversized screenshot. It
read four files:

- `navigation_tracker.h`
- the load events in `desktop_engine_client.cpp`
- `WaitForNavigation` and `Evaluate` in `evaluate_handler.cpp`
- `desktop_screenshot_planner.cpp`

It used 20,074 tokens, returned four findings and changed no files.

1. **A same-document API navigation wedges the tracker. Rejected, on
   evidence.** The worry was that `navigate` to a fragment, or `back` onto
   a `pushState` entry, fires no loading events, so `finished` would never
   catch up. Live on CEF 152, both waits returned in 26–30 ms: CEF reports
   loading start and stop for same-document navigations. The following
   no-op wait and link click behaved normally.
2. **A stale error survives a superseding commit. Accepted.** A commit that
   merged into an in-flight navigation kept the earlier load's error.
   `LoadStarted` now clears the error on every main-frame commit, and a
   test covers "fails after commit, then superseded by a commit that
   loads".
3. **A download that replaces an API navigate is reported as success.
   Rejected.** This follows from the reviewed decision (review finding 1
   above) to ignore `ERR_ABORTED`, which is documented in `core.md`. The
   same code arrives when a newer navigation supersedes a load, which is
   far more common.
4. **`maxWidth` is exceeded when the deprecated `visualViewport` is
   missing. Rejected as hypothetical.** CEF 152 sends it, as verified live.
   A build that dropped it would report an oversized `width`, which the
   CLI's option check refuses, rather than failing silently.

## End-to-end check through the CLI's MCP server

On 2026-09-23 a build of this branch (`scripts/build-windows.ps1`, all 38
CTest tests passing) was driven the way an agent drives it:

- registered as a CLI alias with its own profile under
  `%LOCALAPPDATA%\Kelpie\profiles\`;
- started with `kelpie browser launch <alias> --port 8431`;
- called over `kelpie --browser <alias> mcp`, a stdio JSON-RPC session that
  listed 94 tools.

The client counted how many times each image's base64 occurred in the raw
response line. It was once in every screenshot result.

| Check | Result |
|---|---|
| Navigate to Hacker News, then `wait_for_navigation` | Returned at 891 ms with `isLoading: false`; `readyState` was `complete` |
| Click a story link, then `wait_for_navigation` | 479 ms (nobodywho.ai), 1208 ms (openai.com), 227 ms (an HN comments page); URL and title were the new page's, `readyState` `complete` |
| `wait_for_navigation` with no navigation | `TIMEOUT` "No navigation started within 2000 ms" at 2024 ms |
| JPEG, `maxWidth: 1280`, 1600 px viewport, default quality | 1280×727: Hacker News 117 KB, Wikipedia 160 KB |
| The same with `quality: 60` | Hacker News 83 KB |
| JPEG, `maxWidth: 1280`, maximised 1936 px viewport | Wikipedia 1280×617: 125 KB, or 90 KB at quality 60 |
| `kelpie_get_page_text` on Wikipedia's "World War II" (173,330 characters) | 20,000 characters with `truncated`, `totalChars` and the note; `maxChars: 5000` cut markdown to 5,000 |
| `wait_for_element`, `timeout: 20000`, element added after 15 s | Succeeded at 15,006 ms |
| The same, element never added | The device's own `TIMEOUT` at 20,023 ms; the evidence had the CLI's cut-off at 10,017 ms |
| Window minimised | JPEG and PNG screenshots returned `WINDOW_MINIMIZED`; `evaluate` kept working; after a restore the screenshot succeeded |
| `kelpie discover` and `kelpie_discover` | Both listed the instance as `local:127.0.0.1:8431` through the loopback probe. A 5 s `_kelpie._tcp` browse found no advert, as C7 intends |

The whole response for the 160 KB Wikipedia JPEG was 215 KB, because base64
adds a third. A client that must keep every result under 200 KB asks for
`quality: 60` or a smaller `maxWidth`.

**Seen along the way, outside this change.**

- **A maximised window's client area runs past the monitor.** `WM_NCCALCSIZE`
  returns 0 whenever `wparam` is `TRUE` (`win32_shell.cpp`), maximised or
  not, so the client area is the whole window rectangle. Windows places a
  maximised window 8 px beyond each edge of the work area. On a 1920×1080
  display the viewport measured 1936×926. A screenshot includes those 8 px
  on each side; the person at the screen does not see them.
- **The window went back to its previous rectangle about 1.5 s after every
  resize. Not Kelpie.** This happened after a maximise, after
  `kelpie_resize_viewport`, and after a direct `SetWindowPos`. Nothing in
  `apps/windows/src` restores the window rectangle. The cause was a helper
  script on the test machine, outside this repository. Every couple of
  seconds it shrank any Kelpie window built from this worktree to
  960×720. Its log recorded each shrink of the verification build. The
  checks above ran inside that 1.5 s window, and every screenshot reports
  the size it actually captured.
- **One JPEG came back tiled**, with the old frame repeated inside the new
  size. It was taken about a second after an external maximise, so most
  likely while that script was resizing the window. Four later attempts
  were clean, as was every capture taken straight after
  `kelpie_resize_viewport`. It was not reproduced.

## Merging main's release-gate fixes

`main` gained five commits while this branch was open. Three of them
touched the same code as C8, the engine split and the acceptance harness:

- 7c422dc, "make the Windows control surface pass its release acceptance
  gate";
- 4fb23bf, "remember window placement, fail hidden startups promptly";
- 305750c, "split desktop_engine_control.cpp along its responsibilities".

The merges keep both sides' behaviour:

- **`navigate` now waits for its own load, as on main.** Main added
  `handlers/navigation_wait`, which polled the old `requested` / `completed`
  counters. `AwaitNavigation` now runs on the `NavigationTracker` instead.
  It takes the tracker state read after the action and waits for the first
  navigation after that state's baseline. `navigate` and
  `wait-for-navigation` share it. The API navigation moves the baseline
  when it starts, so `navigate` waits for its own load and not an earlier
  one. The poll floor and the "No navigation started" message moved into it
  with the loop.
- **One split of `desktop_engine_control.cpp`, main's.** Main split the
  same file (305750c) while this branch had its own split. The merge keeps
  main's files: `desktop_engine_control_support` for the shared helpers,
  `desktop_engine_input.cpp` for trusted input and dialogs, and
  `desktop_engine_page_control.cpp` for `Evaluate`, cookies and `DevTools`.
  It also keeps two of this branch's files. `desktop_engine_navigation.cpp`
  holds the tracker-based navigation, and `desktop_engine_screenshot.cpp`
  holds the new `Screenshot`. The old PNG-only `Screenshot` is gone from
  `page_control`. This branch's `desktop_engine_page.cpp` was a byte-for-byte
  copy of main's input and cookie code, so it is removed. `IsNavigableUrl`
  moved into `desktop_engine_control_support`. That file now also has the
  helpers this branch had added to `desktop_engine_impl.h`: `RemainingTimeout`
  and the `RunDevTools` declaration.
- **The harness launches hidden again.** This branch had started the
  browser visible because a hidden launch never became ready. Main fixed
  the cause: startup now checks the browser child's own `WS_VISIBLE`. So the
  harness is back to main's hidden launch, and the README paragraph that
  said otherwise is gone. Main's URL and `evaluate` fixes replaced this
  branch's copies of the same fixes.

### Checked again after the merges

The merged branch was built with `scripts/build-windows.ps1`; all 39 CTest
tests passed. It was packaged with `scripts/package-windows.ps1`. The
release acceptance harness then ran end to end and passed, with its hidden
launch, its CLI phase and Nessie's stdio client. So did an MCP drive through
`kelpie --browser <alias> mcp` (94 tools), on port 8438 with a profile of its
own. The window was held at 943×597 by the helper script described above.

| Check | Result |
|---|---|
| `navigate` to Hacker News | Returned when loaded: `loadTime` 917 ms, `isLoading: false` |
| `wait_for_navigation` straight after it | Returned at once (13 ms): that load had already finished |
| Click the first story, then wait | 662 ms; the URL was the story's and `readyState` was `complete` |
| `back`, then wait | 825 ms, back on Hacker News |
| Click a button that does not navigate, then wait 2 s | `TIMEOUT` "No navigation started within 2000 ms" at 2024 ms |
| JPEG of Wikipedia's "World War II", quality 60 | 943×597, 83 KB (whole response 112 KB) |
| The same at default quality | 99 KB (response 133 KB) |
| `maxWidth: 640` | 640×405 JPEG, 64 KB, `imageScaleX` 0.679 |
| Base64 copies per screenshot response | 1 in every case |
| `kelpie_get_page_text`, default | 20,000 of 173,330 characters, with `truncated`, `totalChars` and the note |
| `wait_for_element`, `timeout: 20000`, element added at 12 s | Succeeded at 12,029 ms |
| Window minimised | JPEG and PNG screenshots returned `WINDOW_MINIMIZED`; `evaluate` still worked; after a restore the screenshot succeeded |
| `kelpie_discover` and `kelpie discover` | Both listed `local:127.0.0.1:8438` through the loopback probe |
