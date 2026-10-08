# Embedded on-device inference

Windows, Android (64-bit) and iOS share a pinned llama.cpp CPU runtime. It runs
inside Kelpie without Ollama, a listening server or a network connection. This
backend accepts text and chat messages. Import an **instruction-tuned GGUF**
with a llama.cpp-supported chat template; vision/audio projectors and arbitrary
model formats are not supported. Model weights are user data, never bundled.

Settings / Local AI offers **Import GGUF model** and **Use imported model** on
both mobile platforms. Windows offers **Choose GGUF** and **Load on device**.
Import copies the mobile file into app-private storage; the last imported file
can be reused after restart. Loading is explicit after restart, so opening the
browser does not immediately allocate a model. Start with a small model on a
6 GB tablet. Memory admission leaves room for the browser and operating system;
an oversized file returns `MODEL_MEMORY_LIMIT` with a smaller-model/LAN suggestion.

## Device HTTP / MCP

Authenticated `POST /v1/ai-load`:

```json
{"backend":"native","model":"/device/path/model.gguf","contextSize":2048}
```

The path is on the device running Kelpie. On mobile, use the import control to
copy a model from Files/Documents. `contextSize` is bounded to 256–8192 tokens.

`ai-infer` accepts `prompt`, optional `text`, or `messages` containing string
`role`/`content` pairs (system, user, assistant). `maxTokens` defaults to 256 and
is bounded to 1–4096; input plus output must fit the context. Temperature is 0–2.
Responses include `backend: native`, `response`, `tokensUsed`, `finishReason`
and `inferenceTimeMs`. Every request starts a fresh context; caller-supplied
messages provide conversation history. `ai-cancel` stops active evaluation;
`ai-unload` releases model memory. Concurrent operations fail with `AI_BUSY`.

Errors include `MODEL_NOT_FOUND`, `MODEL_LOAD_FAILED`,
`MODEL_TEMPLATE_UNSUPPORTED`, `MODEL_MEMORY_LIMIT`, `CONTEXT_TOO_LONG`,
`INPUT_NOT_SUPPORTED` and `INFERENCE_CANCELLED`.

## Windows remote inference

Windows Settings / Local AI can save, edit, remove, refresh models, test and use
named OpenAI-compatible endpoints, including Ollama `/v1`. The address bar's
Settings menu opens this native window; it also provides a prompt, answer and
optional current-page-text checkbox. API keys and endpoint configuration are
stored together in a per-profile, current-user DPAPI-encrypted file. Public
HTTP/MCP responses never return keys. Direct MCP accepts endpoint metadata;
set API keys through native settings or authenticated HTTP, not model prompts.

Use `http://127.0.0.1:11434/v1` only for a server on that Windows computer.
On a tablet use the server computer's reachable LAN address. Saving does not
connect. Refresh/Test/Use explicitly connect. HTTPS certificates are validated,
cross-origin redirects are refused, and Windows credentials are never sent.

Windows supports text/page-context requests and non-streaming OpenAI chat.
Its remote browser-agent tool loop, server capability probes and automatic
health polling are not implemented; requesting `agent: true` fails explicitly.
Use `ai-endpoint-health {refresh:true}` for a fresh probe. Cached health expires
after 90 seconds. Mobile's existing OpenAI agent and endpoint controls continue
to work. No backend automatically switches to a different model, server or
cloud service after failure. Select a LAN endpoint when a device is too small.

## Build

`KELPIE_LOCAL_LLM` defaults on for Windows, Android and iOS. llama.cpp is pinned
to commit `8345f333951c661d166b00e6f9362e553768f292`. The CPU runtime is linked
statically; no separate inference executable is installed. GPU/NPU acceleration
is not enabled in this baseline. Tests can run a real GGUF using
`test_local_inference <path>`; the default test needs no downloaded weights.
