# New-window links as tabs, and opening other apps

## Problem

Reported on macOS (WebKit) with Slack's workspace list:

1. Slack's "Launching KiloMayo" page navigates to `slack://…`. Kelpie silently drops the
   navigation. Chrome and Safari ask "Open Slack?" and launch the app.
2. Since native pop-ups landed (#251), every `target=_blank` link and every `window.open()`
   opens a small pop-up window or sheet. Slack's workspace link opens the launch page in that
   pop-up, and "use Slack in your browser" then loads the whole Slack web app inside it.

Both problems exist on every platform: macOS WebKit and Chromium, Windows and Linux (desktop
CEF engine), iOS and Android.

## Decision

Follow Chrome's split between tabs and pop-ups:

- A new browsing context that asks for pop-up presentation keeps the native pop-up window or
  sheet from #251 (sign-in providers).
- Anything else (`<a target=_blank>`, `window.open(url)` without features) opens a **new
  foreground tab** in the root browser window of the opener, with the opener's storage
  partition. The engine-supplied opener relationship is preserved where the engine hands Kelpie
  the new context (WebKit, Android); Kelpie never reconnects a `noopener` context.
- A navigation to a scheme the engine cannot load (`slack:`, `zoommtg:`, `mailto:`, `tel:`,
  `intent:` on Android…) is cancelled and Kelpie asks the person whether to open the other app.
  Only on confirmation does Kelpie hand the URL to the OS.

### Classification per engine

| Engine | Pop-up when | Notes |
| --- | --- | --- |
| WebKit (macOS, iOS) | `WKWindowFeatures` has `x`, `y`, `width` or `height` | A deliberate approximation through public API. WebKit's own `wantsPopup()` is private. `popup=yes`, `toolbar=no` or `resizable=no` without geometry open as tabs; `popup=no,width=…` opens a pop-up. Sign-in providers pass geometry. |
| Android WebView | `onCreateWindow(isDialog = true)` | Chromium sets `isDialog` for `NEW_POPUP`. |
| CEF (macOS Chromium, Windows, Linux) | `target_disposition == NEW_POPUP` | Chromium's own spec "is popup" result. |

### New-tab plumbing

- **WebKit (macOS/iOS):** `createWebViewWith` returns a web view created from WebKit's
  configuration inside a new tab, so WebKit keeps whatever opener relationship it set up. The
  configuration gets a fresh `WKUserContentController` with Kelpie's bridge scripts (the rule
  #251 already uses for pop-ups). The tab is marked as a real page before it is published.
  A tab-like open from inside a pop-up goes to the root browser store, not the pop-up's
  isolated store, so closing the pop-up does not close the tab. `window.close()` from a
  script-opened tab closes that tab.
- **Android:** `onCreateWindow(isDialog = false)` creates a configured tab without loading a URL
  and hands its `WebView` to `WebViewTransport`. Tab-like opens from a pop-up dialog also go to
  the `TabStore`. `onCloseWindow` closes a script-opened tab.
- **CEF (all three):** `OnBeforePopup` cannot hand a Chromium context to a tab, so tab-like opens
  are cancelled and replayed as a new tab for the target URL, as the desktop engine did before
  #251. Replay only happens when it is safe enough: the open came from a user gesture and has a
  real URL. Empty or `about:blank` targets (pages that write into or navigate the new window
  later) and opens without a gesture keep the native pop-up. Known limits of replay: no
  `window.opener`, and a form POST to a new window becomes a GET.
  - Desktop partition lookup fails closed: the source is the opener tab, or the root tab a
    native pop-up was opened from; if that tab is gone or closing, nothing opens.
  - macOS Chromium native pop-ups have no tab owner (#251); their own new-window opens stay
    native pop-ups. macOS Chromium already refuses partitioned tabs.

New tabs are appended and selected, matching each platform's "new tab" behaviour.

### External apps

Web-loadable schemes stay with the engine: `http`, `https`, `about`, `data`, `blob`, `file`,
`javascript`, plus schemes the engine registered (WebKit: `WKWebView.handlesURLScheme` or a
configured `WKURLSchemeHandler`).

Eligibility, applied before any lookup or prompt, on tabs and pop-ups alike:

- The source web view is on screen (macOS: in a visible window and not hidden; iOS: in a
  window; Android: `isShown`).
- The request comes from the main frame, or from a subframe with the main frame's origin.
  Third-party frames cannot ask.
- A link activation / user gesture may always ask. Without one, a document may ask once; the
  allowance resets when a new main-frame document commits. One prompt at a time per window.
- The prompt names the requesting origin (from the source frame's security origin) and, where
  the OS can resolve it, the target app.

Per platform:

- **macOS WebKit:** resolve the handler with `NSWorkspace.urlForApplication(toOpen:)`; no handler
  → drop. Window-modal sheet "Open “Slack”?" / "https://kilomayo.slack.com wants to open this
  app." with "Open Slack" / "Cancel". On confirm, re-check the web view is still on screen and
  open the URL with the app named in the prompt.
- **iOS:** alert "Open in another app?" naming the requesting origin and the URL scheme, then
  `UIApplication.open`; a failed open is ignored. iOS cannot resolve app names for arbitrary
  schemes.
- **Android:** `intent:` URLs are parsed, then rebuilt as a clean `ACTION_VIEW` intent with only
  data URI, optional package and `CATEGORY_BROWSABLE`: no component, selector, extras or flags.
  `file:`/`content:`/`javascript:` data URIs are refused. Confirm dialog, then `startActivity`;
  when no activity matches, load `browser_fallback_url` if it is http(s), else show "No app can
  open this link".
- **CEF:** first check whether Chrome-style browsers already show Chromium's external protocol
  dialog. If they do, keep it. If not, `OnProtocolExecution` (IO thread) returns with OS
  execution disabled and posts an immutable copy of the request to the UI thread, which applies
  the rules above and launches through the OS after confirmation.

Prompts are native UI only; they are not routed through the JS dialog API. Agents never need to
launch another app, and a cancelled navigation leaves the page usable.

## Out of scope

- "Always allow this site to open X" persistence.
- Background tabs (middle-click/Cmd-click) — no current Kelpie UI for them.
- Hosting a CEF-created context inside a tab to keep `window.opener` for tab-like opens.

## Tests

- macOS/iOS WebKit: a `target=_blank` link and `window.open(url)` add a selected tab in the
  opener's partition; plain `window.open(url)` keeps `window.opener`, `noopener` does not;
  `window.open(url, n, 'width=…')` still opens a pop-up; a tab-like open from a pop-up lands in
  the root store and survives the pop-up closing; `window.close()` closes a script-opened tab;
  scheme classification.
- Android: instrumented test for a `target=_blank` link opening a tab; intent rebuild unit test.
- Desktop CEF: disposition/replay rule unit test.
- Manual: Slack's workspace list → launch page in a new tab → "Open Slack" prompt → "use Slack
  in your browser" loads in that tab; a sign-in pop-up with geometry still opens a pop-up.

## Cross-Provider Review

Codex (GPT) reviewed the first draft adversarially. Accepted:

- Prompt eligibility: visible source, main-frame or same-origin frame, once per document
  without a gesture, one prompt at a time, revalidate on confirm, name the requesting origin and
  launch the named app.
- Android intents are rebuilt from scratch rather than "sanitised" in place.
- CEF replay is limited to gesture-initiated opens with a real URL; blank targets keep the native
  pop-up; replay limits are documented. Desktop partition lookup fails closed.
- No blanket `window.opener` promise; tests cover plain `window.open` and `noopener` separately.
- Script-opened tabs live in the root store and close on `window.close()`.
- Pop-up delegates (iOS `WKPopupViewController`, Android `WebPopupPresenter`) get the same
  external-app and new-tab rules.
- CEF `OnProtocolExecution` runs on the IO thread; any prompt is posted to the UI thread.
- The WebKit justification was wrong: geometry is a documented approximation, not a workaround
  for `noopener` parsing.

Not adopted:

- Requiring a user gesture for every external-app prompt. Slack's launch page (the reported
  case) navigates to `slack://` on load, which Chrome and Safari both allow once; the
  once-per-document allowance covers it without allowing loops.
- Keeping a per-tab delegate on iOS background tabs. A background tab without a delegate cannot
  open other apps or windows at all (WebKit fails closed), so it is not a security gap. The new
  tab gets its delegate before WebKit loads into it.
- Detecting POST targets in CEF: `OnBeforePopup` does not expose the method. Documented instead.
