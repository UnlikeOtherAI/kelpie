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

## Address-bar search

All five native shells use `core-protocol`'s address-input resolver. Previously,
each shell prepended HTTPS to any text without a scheme, turning `GitHub` into
`https://GitHub`. Words and phrases now go to Google with a UTF-8 percent-encoded
query. Domains, localhost, IPv4, bracketed IPv6 and explicit schemes remain
addresses; empty input does nothing. Existing history completions still navigate
to the displayed completed URL. HTTP/MCP `navigate` continues to accept URLs
directly, without applying address-bar search policy.
