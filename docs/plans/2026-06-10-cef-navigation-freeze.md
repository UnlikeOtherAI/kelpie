# CEF (Chromium) navigation freeze — investigation log

**Status:** OPEN. Keep iterating until fixed.
**Tracking issue:** UnlikeOtherAI/kelpie#74
**Owner:** Claude (Opus) + Codex + Gemini opinions

## Symptom

On the macOS app's Chromium (CEF) engine, the browser **navigates exactly once, then freezes**. The first navigation (about:blank → first URL) commits and renders. Every subsequent `navigate` issues the network request (test server logs it) but the main frame never commits — no `OnLoadStart`/`OnLoadEnd` for the new URL, `get_main_frame()->get_url()` stays frozen, `eval`/`screenshot` reflect the stale page. User-visible: "Chromium doesn't work at all."

Reproduces on **CEF 146.0.9 and 148.0.10** → pre-existing, not the version bump.

## Environment / integration facts (verified)

- `cef_initialize` settings: `no_sandbox=1`, `multi_threaded_message_loop=0`, `external_message_pump` NOT set. (CEFBridge.mm ~386-406)
- Message loop pumped by a **60 Hz NSTimer on the main thread** calling `cef_do_message_loop_work()`. (CEFRenderer.swift:81; CEFBridge.mm:423-425)
- Windowed CEF (not windowless): browser created with `parentView` = `CEFHostView`; `windowless=0` in logs.
- Browser created with initial url `about:blank`, identifier `main`. (CEFBridge.mm ensureBridge / create_browser_sync)
- Navigation path: HTTP `navigate` → `HandlerContext.load` → `CEFRenderer.load` → `CEFBridge.loadURL` → `copyMainFrame` (= `activeBrowser`→`get_main_frame`) → `frame->load_url(frame, url)`. (CEFBridge.mm:561)
- `activeBrowser` = `_createdBrowser ?: _callbackBrowser`. `_createdBrowser` from `create_browser_sync` return; `_callbackBrowser` from LifeSpanHandler `OnAfterCreated`. Both id=1, both `is_valid=1`. (CEFBridge.mm:539-543)
- Client registers ONLY: life_span_handler (OnAfterCreated, OnBeforeClose, OnBeforePopup→1), load_handler (OnLoadingStateChange/Start/End), display_handler (OnAddressChange/title/console). NO request_handler / OnBeforeBrowse. (CEFBridgeSupport.mm:500-502)
- `cefBridgeUpdateCurrentURL` (drives `_currentURL`, echoed by navigate response) is called from OnLoadStart/OnLoadEnd, main-frame only. After the first nav it stays frozen → confirms OnLoadStart/End don't fire for subsequent navs.

## Diagnostic evidence

- `[CEFRenderer] load` and `[CEFDIAG] loadURL` fire for **every** navigation (load_url IS called each time).
- Test server receives **every** request (GET /?a=1, /console?q=A, etc.).
- `[CEFDIAG] loadURL ... liveMainFrameURL=` shows the live `get_main_frame()->get_url()` BEFORE each load: it equals the FIRST committed URL and never advances.
- First nav: about:blank → `/` commits (`eval location.href = http://…/`, `document.title = Home OK`, bodyLen=4).
- All later navs: live frame frozen at first URL; `_currentURL` frozen; no OnLoadStart/End.
- Flaky across launches only in WHICH page ends up frozen (sometimes about:blank, if the first real nav never lands while the window settles).

## Hypotheses

- H1 — **TID_UI / thread**: navigations issued on a thread that isn't TID_UI, so they're dropped after the first. (But first nav works on main thread; pump is on main thread. Needs `cef_currently_on(TID_UI)` confirmation.) — UNDER TEST
- H2 — **stale browser handle**: `activeBrowser` (`_createdBrowser`) goes stale after first commit; `_callbackBrowser` is the live one. — UNTESTED (cheap)
- H3 — **`frame->load_url` post-first-nav no-op in windowed CEF**; need `load_request` / browser-host nav / re-get main frame after OnLoadEnd. — `load_request` tried, INCONCLUSIVE (broke eval, destabilized renderer)
- H4 — **message-loop pump insufficient / reentrancy**: `cef_do_message_loop_work()` timer doesn't drive a second navigation to commit; may need `external_message_pump=1` + OnScheduleMessagePumpWork, or `cef_run_message_loop`. — UNTESTED
- H5 — **renderer/compositor surface not live** after first paint, so commits stall. — UNTESTED
- H6 — **something reverts the navigation** (cookie sync / reload) post-load. (But first nav not reverted.) — LOW

## Attempts log (do NOT retry without reason)

| # | Date | Change | Result |
|---|------|--------|--------|
| A1 | 2026-06-10 | Diagnostic logging in `loadURL` (live main-frame URL, browserID, has_document) + `evaluateJS` (frame URL) | Confirmed load_url called every time; live frame frozen after first nav. Kept (local, reverted before ship). |
| A2 | 2026-06-10 | Swap `frame->load_url` → `frame->load_request` (CefRequest GET) | INCONCLUSIVE: eval round-trips returned empty, renderer became unresponsive. Reverted. May have hit `INVALID_INITIATOR_ORIGIN` or a bad state. |
| A3 | 2026-06-10 | Message-loop timer → `RunLoop.main.add(timer, forMode: .common)` + pump tick log | NO EFFECT on freeze. Pump tick fires steadily at 60 Hz unconditionally even when frozen → **message-pump starvation RULED OUT** (we already over-pump; the "no timer floor" theory doesn't apply). Kept the .common change (correct regardless). |
| A4 | 2026-06-10 | `activeBrowser` prefer `_callbackBrowser` (OnAfterCreated) over `_createdBrowser` | NO EFFECT. eval/screenshot still blank. |
| A5 | 2026-06-10 | (Gemini) after create_browser_sync: `host->was_resized()` + `host->set_focus(1)` (gemini wrote `send_focus`, hallucinated — corrected to `set_focus`) | NO EFFECT. 0/5 launches render. |
| — | 2026-06-10 | BASELINE: installed 0.1.5 (renderer-pointer fix only) | Also blank. → Bug is **almost-always-broken**, not 50/50 flaky. Earlier "Home OK" hits were rare good launches. Matches user's "doesn't work at all". |

**Convergent expert root cause (research + Gemini):** startup race between macOS NSView/CALayer readiness and CEF renderer/GPU compositor — renderer fails to get a drawable surface, stays at empty about:blank; browser process advances nav state (load events fire) but renderer never commits. Also: Chromium special-cases about:blank (maybeLoadEmpty, bypasses resource pipeline); CEF #763: browser created with about:blank initial URL misbehaves on subsequent loads.

**Caveat to investigate:** macOS 26.2 (Tahoe, bleeding-edge) — windowed CEF compositor may be broken on this OS for BOTH 146 and 148. If no code fix works, likely needs OSR (windowless) rendering or a newer CEF.

| A6 | 2026-06-10 | Create browser with a `data:` document instead of `about:blank` | NO EFFECT. 0/5. eval still `about:blank` (renderer doesn't even load the data: doc). |
| A7 | 2026-06-10 | Clear CEF cache dir (`$TMPDIR/kelpie-cef-cache`) before launch | NO EFFECT. Not cache corruption. |
| A8 | 2026-06-10 | Launch with `--disable-site-isolation-trials --disable-features=IsolateOrigins,site-per-process` (no rebuild; CEF reads process argv) | NO EFFECT. Cross-origin renderer-process swap RULED OUT. |

## CONCLUSION (2026-06-10, pause point)

- The renderer process runs (2 renderer helpers spawn, `1+1`→`2` works) but **never loads/commits ANY document** — stuck at `about:blank`, almost always, on macOS 26.2 — while the browser process advances nav state (OnLoadStart/End fire, network request made).
- **Ruled out:** message pump (over-pump at 60Hz, ticks steady), browser-handle choice, `was_resized`+`set_focus`, `about:blank`-vs-`data:` creation URL, cache corruption, site isolation / process swap.
- **Key web finding:** Chrome 142+ FIXED macOS-26-Tahoe blank-rendering; CEF 148 = Chromium 148 (> 142) and CEF 146 also has it → so this is **almost certainly OUR windowed-CEF integration racing** (NSView/CALayer compositor readiness vs renderer surface attach), NOT a pure OS incompatibility. Stock CEF 148 should render on Tahoe.
- It worked a few times very early in the session → a startup race our integration almost always loses now.

## RECOMMENDED NEXT STEPS (larger effort, beyond quick fixes)
1. **Compare against stock cefclient/cefsimple @ CEF 148** on this Mac to confirm our-integration-vs-upstream. (Definitive.)
2. **Match the macOS cefclient hosting-view setup** — it uses a dedicated hosting view/window; our plain layer-backed `CEFHostView` may not give the renderer a valid compositing surface on Tahoe. Investigate `cef_window_info` flags, the view's layer/CARenderer attachment, and creating the browser only after the view has actually drawn once.
3. **Fallback: switch the Chromium engine to OSR (windowless) rendering** — implement `OnPaint` + draw the bitmap + map input. Removes all windowed-surface dependence; heavier but robust.

Sources: magpcss ceforum t=17240 (CEF blank when attaching to existing NSView; macOS example uses UnderlayOpenGLHostingWindow), issues.chromium.org/442887787, support.google.com Tahoe threads, Adobe Dreamweaver Tahoe CEF crash report.

## REFINED SYMPTOM (after A3/A4)

- `eval` is reliable: `1+1` → `2`. It reports the page genuinely empty: `location.href=about:blank`, `document.title=''`, `document.body.innerHTML.length=0`. Screenshot blank.
- Yet the navigate **response URL updates** to the new URL (browser-process `OnLoadStart`/`OnLoadEnd` fire; `frame->get_url` in the callback = new URL) and the network request is made.
- **So: the browser process reports navigation to the new URL, but the renderer's main frame stays stuck at `about:blank` (empty DOM, nothing painted).** JS runs in that about:blank document.
- Flaky **per launch**: some launches the first real nav DOES render ("Home OK") and then it's fine; some launches it's blank from the start. → looks like a **startup race** in the renderer/compositor, not a per-navigation issue.
- Message pump and handle-choice ruled out. Leading suspects now: renderer/GPU surface not live for windowed CEF (compositor never commits), or browser↔renderer navigation desync.

## Ruled out

- Navigation interception (no request handler / OnBeforeBrowse).
- Hidden-state suspension (`was_hidden(true)` only on engine-switch isHidden toggle; no deferral logs between navs).
- The version bump (146 and 148 identical).
- The active-renderer pointer bug (separate, FIXED + shipped in 0.1.5).

## External opinions

### Online research (WebSearch)
- "Navigation only works once" is the classic symptom of an external/manual message pump WITHOUT a timer fallback; the official `MainMessageLoopExternalPump` polls at a ~30Hz floor (`kMaxTimerDelay`). Sources: magpcss.org ceforum t=17352, t=14862; cefpython #246/#245.
- CEF issue #3341: a mojo message-ordering bug where `OnLoadEnd` can fire with the pre-load URL.
- Recommended: prefer `multi_threaded_message_loop=1` or `cef_run_message_loop()` over manual `cef_do_message_loop_work()`.

### Codex
- (long; converges on message-pump scheduling + using the OnAfterCreated browser handle.)

### Gemini
- Two recommendations: (1) implement `external_message_pump=1` + `OnScheduleMessagePumpWork` with a timer; (2) **use the `OnAfterCreated` browser handle for all calls**, not the `create_browser_sync` return.

## KEY FINDING (2026-06-10, decisive)

The pump tick fires steadily at 60 Hz even when navigation is frozen → **pump starvation RULED OUT**. The real split:
- The navigate response URL (`_currentURL`, updated by OnLoadStart/OnLoadEnd which fire on the **OnAfterCreated / `_callbackBrowser`** handle) DOES advance to the new URL → the navigation commits at the browser level.
- But `eval` / `screenshot` / `load_url` go through `activeBrowser` = `_createdBrowser` (the `create_browser_sync` return), whose `get_main_frame()` is `about:blank` and whose surface is blank.

→ The two handles disagree. Fix candidate: make `activeBrowser` (and frame/host access) use `_callbackBrowser` (OnAfterCreated) instead of `_createdBrowser`.
