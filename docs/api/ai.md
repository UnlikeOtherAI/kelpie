# Kelpie — AI API

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

### `POST /v1/ai-catalog`

Lists the approved on-device model catalog with download URLs and per-model metadata. Supported on iOS, Android, and macOS. Requires a HuggingFace token configured on the device (set in Settings); without one it returns `AUTH_REQUIRED`.

Request: no parameters.

```json
{
  "success": true,
  "models": [
    {
      "id": "gemma-4-e2b-q4",
      "name": "Gemma 4 E2B Q4",
      "hugging_face_repo": "bartowski/gemma-4-E2B-it-GGUF",
      "hugging_face_file": "gemma-4-E2B-it-Q4_K_M.gguf",
      "size_bytes": 2500000000,
      "ram_when_loaded_gb": 3.8,
      "capabilities": ["text", "vision", "audio"],
      "min_ram_gb": 8.0,
      "recommended_ram_gb": 16.0,
      "quantization": "Q4_K_M",
      "context_window": 8192,
      "summary": "Understands text, images, and speech for local page analysis.",
      "best_for": "General local browsing assistance with text, vision, and audio input",
      "speed_rating": "moderate",
      "download_url": "https://huggingface.co/bartowski/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_K_M.gguf"
    }
  ]
}
```

### `POST /v1/ai-fitness`

Scores a catalog model against a device's resources. Supported on iOS, Android, and macOS. Requires a HuggingFace token configured on the device (`AUTH_REQUIRED` otherwise).

```json
{
  "model": "gemma-4-e2b-q4",   // required, catalog model ID
  "ramGB": 32,                  // optional, total device RAM in GB to score against
  "diskGB": 50                  // optional, free disk space in GB to score against
}
```

Response — `fitness` is one of `recommended`, `possible`, `not_recommended`, or `no_storage`, with a human-readable `message` (empty when `recommended`):

```json
{
  "success": true,
  "fitness": "recommended",
  "message": ""
}
```

Fitness levels: `no_storage` (free disk is below the download size), `not_recommended` (RAM is below the model's minimum), `possible` (RAM is below the recommended value or disk headroom is tight — may run slowly), `recommended` (comfortably fits).

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
| `AUTH_REQUIRED` | `ai-catalog`/`ai-fitness` need a HuggingFace token configured on the device |
| `AI_UNAVAILABLE` | The device's AI manager is not initialized |
| `MISSING_PARAM` | `ai-fitness` was called without the required `model` |
