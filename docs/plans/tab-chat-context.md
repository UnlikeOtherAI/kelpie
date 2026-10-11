# Tab-scoped local AI context across existing platform surfaces

## Root cause

The macOS panel sends a tab ID only for OpenAI-compatible endpoints. Ollama's page tool and summary also omit the ID. HandlerContext correctly rejects untargeted reads in a multi-tab window, but `try?` converts that failure into `{}`. The prompt then presents this as page content. Text extraction misses logos represented by image alt text or SVG accessible names. The window owns a single chat session, resets it on every URL change, and sends only ten previous messages; native inference ignores history entirely.

## Repair

- Make each Tab own its in-memory AIChatSession. Bind the panel to the active Tab's session and remove URL-change resets. Closing a tab clears its session and invalidates in-flight completions; navigating, switching tabs, and hiding the panel preserve it. No disk persistence or second session registry.
- Send the captured tab ID and complete user/assistant message history for every backend. Keep actions disabled by default and reset action permission on navigation without erasing conversation.
- Use one throwing, tab-targeted page snapshot for local chat, with title, URL, body text, image alt/ARIA labels and SVG titles. Keep labels separately so text limits cannot drop them. Treat page data as untrusted evidence, distinguish an empty page from a read failure, and surface extraction errors instead of asking the model to invent an answer.
- Ollama receives role messages; native inference receives an explicitly delimited conversation alongside the current page. Retain existing non-chat API behavior. Existing model context-window limits remain applicable; remove the arbitrary ten-message UI cap.
- Regression tests cover two tabs, accessible logos, page-read errors, request history beyond ten turns, tab switching/navigation/close, and stale in-flight replies. No new controls or mobile UI changes.

## Verification and delivery

Run macOS Swift lint, Xcode build/tests on this Mac (Apple frameworks required), and the installed app against local Ollama. Verify page questions and recall with multiple tabs. Verify iOS/Android API parity and Windows/Linux native builds with targeted tests. Bump the five affected native components, open one PR, merge after checks, publish their artifacts and a dated GitHub release, then install and verify the published builds on available hosts. The CLI is unchanged.

## Cross-Provider Review

Reviewed before implementation by Codex and Google Gemma 4 E4B through local Ollama. Claude CLI was attempted but unavailable due to its weekly limit.

Accepted: pin the session and page to the same tab; strict snapshot decoding; explicit read-error reporting; permit conversation recall in prompts; guard duplicate sends and both successful/failed late completions; reset action permission in the owning tab lifecycle. Complete history remains subject to the model context window, with a clear native context-limit error.

Rejected: adding a second session registry (Tab owns the session), blocking model-health refresh during requests (no await before the selected model is captured), and cancelling work simply when switching tabs (the request should finish in its originating tab). Closing a tab invalidates its completion without invoking the existing global backend cancellation API. Existing Stop behavior is outside this local-chat repair.


## Platform scope

The user requested Sol agents across all platforms and confirmed that this repair covers existing AI paths only. macOS has the chat sidebar; Windows has an Ask/result surface. iOS and Android expose AI APIs without a chat panel, so their fixes preserve caller-supplied conversations and correct page targeting. Linux has no local AI chat service; shared page extraction is covered without introducing a new service or UI. Mobile implementations must remain equivalent.

Windows uses the same ownership rule through `DesktopEngine::Tab` with a mutex-protected conversation and completion token. Google Gemma reviewed this supplement before implementation: accepted explicit extraction failures and synchronized close/completion tests; rejected cross-launch persistence because the requested lifetime ends on tab close. Separate Sol agents own macOS, mobile, and Windows/Linux changes, integrated into one delivery.

## Acceptance evidence

- macOS: Swift lint, 161 Xcode tests and arm64 Release build passed. A real Gemma/Ollama conversation read GitHub customer names and recalled a phrase after tab switching, navigation and panel reopening. The packaged Release build also passed page grounding and recall.
- iOS: 11 focused tests exercised real WKWebViews, background tabs and stale view pointers. Swift lint and arm64 Simulator Release build passed; the installed app reported 0.1.14. Authenticated live API pairing was unavailable, so native router tests provide the page-read evidence.
- Android: full Gradle build and bundleRelease, lint and 115 tests each in Debug and Release passed on Ubuntu. The signed release installed/launched in an API 35 emulator and reported 0.1.13. Physical mobile devices were unavailable.
- Windows: CEF CI build/native tests passed and the candidate package passed live HTTP/MCP, accessible logo and tab-isolation checks on Maxis. No real Windows model server was running. The final integrated PR rebuilds the shared shutdown fix.
- Linux: CEF/GTK build, all 27 native tests and the full live release harness passed, including page evidence, partition/session restoration and both clean shutdowns.
- CLI: lint/build/tests passed on Maxis; 608 tests passed and 64 device-dependent tests were skipped. Existing Xcode warnings remain.
