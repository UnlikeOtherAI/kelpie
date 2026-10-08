# Inference platform coverage

Source audit of the OpenAI-compatible endpoint implementation merged in PR #163,
and the existing native/platform backends, on 2026-10-08.

| Capability | Windows | iOS | Android |
| --- | --- | --- | --- |
| OpenAI-compatible endpoint settings, models, test and selection | Missing | Implemented | Implemented |
| Text inference and browser agent using a selected endpoint | Missing | Implemented | Implemented |
| Inference on another LAN computer | Missing | OpenAI-compatible or Ollama endpoint | OpenAI-compatible or Ollama endpoint |
| Built-in on-device inference | Missing | Foundation Models, only when available | Not wired: AI Edge dependency is disabled and implementation is a reflection placeholder |
| Automatic fallback based on device power | Missing | Not implemented | Not implemented |

"Implemented" describes source coverage, not a successful physical-device test.
PR #163 passed Android build/lint, iOS simulator build, Swift project/lint and
repository lint checks before merging. Its reported real-server agent test ran
on macOS; it did not establish real-server inference on either mobile platform.

## Running inference locally or on the LAN

On mobile, Settings / Local AI exposes OpenAI-compatible endpoints. Save the
server's base URL, select a model, test it and explicitly use it. On a phone,
`localhost` is that phone. To use a more powerful LAN computer, enter that
computer's reachable hostname/IP and inference port, for example
`http://minis.local:11434/v1` for an already configured Ollama server. The server
must already listen on that network address. Kelpie does not configure servers
or firewall rules.

Selecting a LAN endpoint is the supported alternative when platform inference
is unavailable. Failure never silently changes endpoint/model or sends data to a
cloud service. See [the endpoint contract](../api/ai-endpoints.md).

The Windows shell currently registers no `ai-*` handlers and exposes no endpoint
settings. Merely linking `core-ai`, which supplies catalog/storage/Ollama helpers,
does not provide this feature. Windows needs a desktop endpoint service, secure
credential storage integration, HTTP/MCP registration, a tab-pinned agent bridge,
and native settings wired to the same endpoint contract before claiming parity.

Android's `PlatformAIEngine` checks for an absent AI Edge class and cannot execute
on-device inference in the released build. It needs a supported SDK integration,
real availability checks and inference tests on supported physical hardware.
RAM/disk fitness scores and a model catalog alone do not implement a runtime.

## Verification of the address-search release

- Windows: sandboxed CEF release build, 43 native tests and the HTTP/direct-MCP/
  CLI-alias acceptance suite passed. Real keyboard input after page focus opened
  Google results for `GitHub`.
- iOS: Swift lint, simulator build, 116 unit tests and the keyboard-driven
  `AddressSearchUITests` regression passed on the Mac. The Google page rendered.
- Android: full Gradle build, lint and unit tests passed on Ubuntu. Installed
  emulator app input `GitHub` opened Google. A paired HTTP test saved and selected
  an OpenAI-compatible endpoint on Minis, loaded `gemma4:e4b`, and received `4`
  from `ai-infer` for `2 + 2` in 26.5 seconds. The temporary endpoint was removed.
- macOS: Swift lint and the Apple Silicon Release build passed; the running
  release candidate reported version 0.1.27. Xcode 27 emitted warnings in existing
  concurrency/CEF/build metadata code. Apple test builds also emitted dependency
  warnings; warning-free Apple builds are not established.
- Linux: Release build and 26 native tests passed on Ubuntu.
- CLI: lint/build passed, with 608 tests passing and 64 skipped. A child-process
  startup timeout under concurrent C++ compilation passed when rerun.

Physical mobile devices, real-server iOS inference, and automatic fallback were
not verified. Windows inference remains unimplemented. The shared resolver has
27 cases covering search, Unicode, explicit URLs, hostnames, IP addresses and
the C buffer bridge.

## Address-bar search

All five native shells use `core-protocol`'s address-input resolver. Previously,
each shell prepended HTTPS to any text without a scheme, turning `GitHub` into
`https://GitHub`. Words and phrases now go to Google with a UTF-8 percent-encoded
query. Domains, localhost, IPv4, bracketed IPv6 and explicit schemes remain
addresses; empty input does nothing. Existing history completions still navigate
to the displayed completed URL. HTTP/MCP `navigate` continues to accept URLs
directly, without applying address-bar search policy.
