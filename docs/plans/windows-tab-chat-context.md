# Windows tab chat and shared desktop page evidence

## Root cause

The Windows Local AI settings dialog submits only the latest prompt. Its optional
page read has no tab ID, so multi-tab reads fail admission. Conversation state
also disappears whenever the dialog closes. Native GGUF inference already accepts
complete role messages and reports context-window overflow; the caller loses
history before it reaches the runtime. Desktop page text uses innerText alone,
which omits accessible names of image and SVG logos.

## Repair

Each native desktop tab owns one in-memory, mutex-protected TabChatSession. The
Windows dialog captures the active tab and session when it opens, sends the
complete conversation, and displays that conversation in the existing result
area. Navigating and closing/reopening the dialog keep it. Closing the browser
tab, including API closes and partition deletion, clears it and invalidates an
in-flight reply under the same session mutex. Concurrent sends cannot append a
second user turn. A closed session cannot be revived by a late success or error.
Conversation data never enters the restorable browser session.

Current page context is enabled initially and retains the existing checkbox.
Each request targets the captured tab and generation. A single desktop page-text
evaluation returns URL, title, body text and separately collected visible image
alt, ARIA names and SVG titles. Windows verifies snapshot types before sending
it, preserves labels separately from bounded body text, and surfaces failed or
malformed reads without invoking inference. Page evidence is attached only to the
current user turn and is explicitly untrusted. All previous user/assistant turns
remain intact; native token and request limits produce explicit errors.

Linux has no existing AI handlers or chat UI. Its shared page-text read gains
accessible names and metadata; this repair adds no Linux inference service.

## Cross-Provider Review

The root agent sent this supplement to local Google Gemma before implementation.
Accepted findings: snapshot read/parse errors must remain explicit; tab closure
must invalidate completions under the same mutex and token check; tests must
cover late replies, closed/reopened tabs and concurrent sends. Disk persistence
was rejected because the requested lifetime ends with tab close. A second
session registry and additional diagram/registry requirements were rejected as
unnecessary; the native tab directly owns its session.

## Verification

Focused tests cover more than ten turns, two independent tab conversations,
duplicate and concurrent sends, late replies and errors after close, reopened
tabs, page targeting, accessible-name evidence, malformed snapshots and read
failures. Linux native CMake/CTest verifies shared desktop compilation; Windows
CEF CI verifies native Windows integration when the LAN hosts lack its toolchain.

Linux live acceptance exposed a reentrant shutdown defect: CEF can invoke
`OnBeforeClose` synchronously from `CloseBrowser`, invalidating an iterator over
the live tab list. GDB confirmed a null session mutex in `Impl::Shutdown`;
the previous Linux 0.1.8 executable passed the same shutdown/restore flow.
Shutdown now snapshots session, DevTools and browser ownership before callbacks,
and releases the snapshot before `CefShutdown`. Partition deletion already uses
stable browser handles. The permanent Linux harness asserts normal exit status
and readiness removal, so a crash fails directly instead of appearing as a
shutdown timeout.

The final Linux CEF/GTK build passed all 27 native tests and the unmodified
release acceptance harness, including accessible logo evidence, viewport
resize/reset, both normal shutdowns, persistent session restore and readiness
cleanup. A baseline-reproduced viewport timeout occurred on one retry; the
unpressured final run passed. Windows 0.1.11 CEF CI and candidate live core flow
passed before this shared shutdown fix; the final integrated PR must rebuild
and test the final Windows source before merge.
