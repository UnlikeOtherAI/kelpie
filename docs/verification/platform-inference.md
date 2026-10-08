# Inference platform coverage

Verified on 2026-10-08 for Windows 0.1.10, Android 0.1.12 and iOS 0.1.13.
The shared address-history correction also ships in macOS 0.1.28 and Linux 0.1.8.

| Capability | Windows | iOS | Android |
| --- | --- | --- | --- |
| Imported GGUF on-device text inference | Embedded CPU runtime | Embedded CPU runtime | Embedded CPU runtime |
| OpenAI-compatible endpoint settings, models, test and selection | Implemented | Implemented | Implemented |
| Text and selected page-context inference through a LAN endpoint | Implemented | Implemented | Implemented |
| Remote browser agent | Not implemented | Existing implementation | Existing implementation |
| Automatic fallback based on device power | Not implemented | Not implemented | Not implemented |

The portable runtime uses llama.cpp with at most four CPU threads. It does not
require Google AICore, Apple Intelligence or a GPU. GGUF models are imported by
the user; no weights are bundled. Model size, supported chat template, context
size and available memory determine whether a model can run. A successful small
model test does not establish support for larger models or acceptable quality
for arbitrary prompts. See [the local API contract](../api/local-gguf.md).

## Choosing local or remote inference

Windows Settings / Local AI offers a GGUF file picker, model load/unload, endpoint
settings and a prompt box. Mobile Settings / Local AI offers matching import,
load/unload and endpoint controls. Select an imported model to run on this device,
or save, test and explicitly select a LAN endpoint to use a stronger machine.
On mobile, localhost means the mobile device, not the Windows computer.

For an Ollama server listening on Minis, the tested base URL is
`http://192.168.1.215:11434/v1`. Kelpie does not configure server listening addresses
or firewall rules. Remote inference sends the supplied prompt and any explicitly
requested page context to the selected server. Selecting a remote endpoint
unloads the portable local model. Local weights are not automatically loaded
after application restart. Failure never silently selects another model, server
or cloud service. See [the endpoint contract](../api/ai-endpoints.md).

Windows supports non-streaming text/page-context inference; it rejects browser
agent requests and media inputs. The portable runtime has the same text-only
scope on all three platforms. Existing mobile platform and remote-agent backends
remain separate choices. Android's older Google reflection adapter is not the
runtime used or verified here.

## Verification evidence

- Windows: sandboxed CEF Release build and 45 native tests passed. The acceptance
  suite passed HTTP, direct MCP, CLI-alias access, native navigation and readiness
  cleanup. A real SmolLM2-135M-Instruct Q8 GGUF generated a 13-token greeting in
  154 ms. The selected LAN `gemma4:e4b` model answered `2 + 2` with `4` in 34.7 s.
  Settings and the local file picker rendered. Full keyboard interaction with
  the owned file-picker window was not established by the UI automation tool.
- Android: full Gradle build, lint and unit tests passed on Ubuntu. A physical
  DOOGEE T30S (Android 14, arm64, approximately 6 GB RAM) imported the same GGUF
  through the system file picker and ran it successfully. A 13-token greeting
  took 10.9 s in the debug build with Wi-Fi disabled and 0.7 s in the optimized
  release build. Wi-Fi was restored and the
  tablet received `4` from the Minis LAN model in 24.1 s. The development-signed
  release APK installs as an update without deleting user data.
- iOS: Swift lint, simulator build and the unit/UI test suite passed on the Mac.
  The native bridge generated text from the real GGUF fixture in the iPhone 17
  Pro simulator. Physical iPhone/iPad execution and real-server iOS inference
  were not verified. The simulator does not establish physical-device speed.
- macOS: Swift lint and Apple Silicon Release build passed. Xcode 27 still emits
  existing concurrency/CEF/build metadata warnings; a warning-free Apple build
  is not established.
- macOS native tests: all 12 tests for enabled backends passed.
- Linux: Release build and all 26 native tests passed on Ubuntu.
- CLI: lint/build passed, with 608 tests passing and 64 skipped. CLI code and npm
  versions are unchanged by this inference release.

Android CI also exposed an existing token-comparison defect: XOR accumulation
could cancel differing bytes and accept unequal hashes. Android now OR-accumulates
all byte differences, matching iOS, with deterministic counterexample tests.

Timing measurements are individual smoke tests, not performance benchmarks.
Cancellation, invalid parameters, missing model files, endpoint failure without
fallback, encrypted Windows persistence and secret redaction have focused tests.
The Windows encrypted endpoint store uses per-user DPAPI; credentials are not
returned in endpoint-list responses.

## Address-bar search and existing history

All five native shells use the shared address resolver and history store. Words
and phrases such as `GitHub` search Google. Domains, localhost, IPv4, bracketed
IPv6 and explicit schemes remain addresses; empty input does nothing.

Existing malformed entries such as `https://github/` previously overrode search
before the resolver ran. Shared history completion now ignores these entries
for bare search input, without deleting history. Explicitly typed URLs can still
complete intranet hosts, and valid domain history still autocompletes normally.
Regression tests cover malformed history, explicit schemes, localhost, IPs and
valid domains. On the physical T30S, typing `GitHub` in the release build opened
Google results while the old malformed history entry was still present.
HTTP/MCP `navigate` continues to accept URLs directly.
