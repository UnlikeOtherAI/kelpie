# Android browser gateway

Android exposes authenticated `POST /v1/browser-control` and `POST /mcp` through
the existing Ktor listener, pairing bearer policy, header validation and body
bounds. Pairing still requires on-device approval. Kotlin drives authorization
and native dispatch; schemas, compact catalogs, extension descriptors, references
and uncertainty come from `native/core-mcp` through JNI.

The direct MCP catalog has four tools: `kelpie_browser_control`, `kelpie_extensions`,
`kelpie_extension_tools`, and `kelpie_extension`. Extension availability follows
registered, supported Android handlers. `ai-infer` and `ai-record` retain their HTTP
entry points; recursive browser inference is excluded from direct gateway extensions.

The existing OpenAI-compatible browser agent uses a gateway per run, the same
compact catalog and its task-list tool. Its rich extension admission retains the
existing semantic read/click/fill/select/check permissions. Navigation, arbitrary
evaluation, screenshots, cookies, storage and tab creation/closing remain outside
that inference scope. `allowActions:false` removes common mutations. Read-only
inference refuses an inactive target; action-enabled inference can select it
initially. Every operation rechecks the pinned active tab and both canonical
`tabId` and extension argument `tabId`. Plain OpenAI and embedded GGUF inference
keep optional pinned page context; GGUF does not acquire an agent loop.

One coroutine mutex serializes complete gateway transactions and ordinary legacy
browser operations across HTTP, MCP and inference. Legacy mutations invalidate
all live sessions; common mutations invalidate other live sessions as well. Main
frame navigation queues per-tab invalidation before the next transaction. Script
playback owns its nested handler sequence; abort/status and inference cancellation
remain reachable during playback. Recording gates still refuse browser operations.
Renderer dispatch is bounded at 30 seconds. Cancellation resets native state and
preserves its uncertain outcome, without an automatic repeat. Per-run handles close
after inference; Activity teardown closes remaining handles after the listener.

The fixed reader uses `WebView.evaluateJavascript` in the page realm; this binding
has no private DOM content world. Ephemeral object identity detects ordinary stale
or replaced nodes, but page scripts can observe or interfere with that registry.
This is a correctness guard, not hostile-page isolation. Common ref actions use
fixed DOM activation/append semantics in the same realm; rich interaction
extensions retain their existing events. Android has no registered native keypress
handler, so common keypress is omitted. Common screenshots support viewport PNG;
the rich extension retains its formats and full-page options.

Build on Ubuntu with Java 17, Android SDK, Node 20+ and pnpm in PATH:
`cd apps/android && ./gradlew build`. CMake generates the common contract from
shared sources and links `kelpie_core_mcp` into `kelpie_jni`; schema copies are
never committed. JVM tests cover authentication, scope, serialization, refusal,
timeout/cancellation and ownership. Native CTest covers canonical validation and
ref lifetime. Emulator verification exercises JNI and the real HTTP/MCP renderer
path separately; an emulator pass does not establish physical-device acceptance.
