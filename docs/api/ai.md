# Mollotov — AI API

AI methods expose the active local inference backend on each device. The HTTP shape is shared across platforms, but the backing engine differs:

- macOS: native GGUF via `llama.cpp` or remote Ollama
- iOS: platform AI (Apple Intelligence) by default when supported, with remote Ollama as an override
- Android: platform AI (Gemini Nano) by default when supported, with remote Ollama as an override

Mobile platform AI is text-only. Vision and audio inference require a backend that supports those inputs.

## Methods

### `POST /v1/ai-status`

Returns the current backend, whether it is ready to serve inference, and the capabilities exposed by that backend.

Example response on iOS with platform AI active:

```json
{
  "success": true,
  "loaded": true,
  "backend": "platform",
  "capabilities": ["text"]
}
```

Example response on iOS with remote Ollama active:

```json
{
  "success": true,
  "loaded": true,
  "backend": "ollama",
  "model": "llava:7b",
  "capabilities": ["text"],
  "ollamaEndpoint": "http://192.168.1.50:11434"
}
```

### `POST /v1/ai-load`

Switches the active backend.

- On iOS and Android, omitting `model` or passing `"platform"` switches back to platform AI.
- Passing an `ollama:`-prefixed model switches the device to remote Ollama.
- Plain GGUF model IDs and direct GGUF paths are not supported on mobile.

Examples:

```json
{ "model": "platform" }
```

```json
{ "model": "ollama:llava:7b", "ollamaEndpoint": "http://192.168.1.50:11434" }
```

### `POST /v1/ai-unload`

Clears any explicitly selected remote model and reverts the device to the platform backend.

Example response:

```json
{ "success": true }
```

### `POST /v1/ai-infer`

Runs inference against the active backend.

- Platform AI on mobile currently accepts text only.
- Remote Ollama on mobile proxies the request to the configured `/api/generate` or `/api/chat` endpoint.
- If Ollama is configured but unavailable, the request fails explicitly instead of silently falling back.

Examples:

```json
{
  "prompt": "Summarise this page in 3 bullet points",
  "context": "page_text"
}
```

```json
{
  "prompt": "What about the enterprise tier?",
  "messages": [
    { "role": "system", "content": "Answer briefly." },
    { "role": "user", "content": "What are the prices?" },
    { "role": "assistant", "content": "The page shows three tiers." }
  ]
}
```

Success response:

```json
{
  "success": true,
  "response": "The page shows three pricing tiers...",
  "tokensUsed": 187,
  "inferenceTimeMs": 1450
}
```

### `POST /v1/ai-record`

Audio capture control for chat input flows.

- `action: "start"` prepares recording
- `action: "stop"` returns base64 audio payload data
- `action: "status"` reports recording state

The current iOS implementation is a transport stub backed by `AVAudioEngine` structure only. It preserves the endpoint contract while native recording is wired later.

## Error Codes

| Code | Meaning |
|---|---|
| `PLATFORM_AI_UNAVAILABLE` | Platform AI is unavailable on the current device or not yet wired |
| `OLLAMA_NOT_AVAILABLE` | Ollama could not be reached during load |
| `OLLAMA_MODEL_NOT_FOUND` | The requested Ollama model is not installed |
| `OLLAMA_DISCONNECTED` | Ollama dropped or failed during inference |
| `AUDIO_NOT_SUPPORTED` | The active backend does not accept raw audio input |
| `VISION_NOT_SUPPORTED` | The active backend does not accept image input |
| `RECORDING_ALREADY_ACTIVE` | `ai-record` start was called while already recording |
| `NO_RECORDING_ACTIVE` | `ai-record` stop was called without an active recording |
