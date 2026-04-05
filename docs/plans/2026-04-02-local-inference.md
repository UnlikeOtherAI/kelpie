# Local Inference Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add on-device LLM inference to Kelpie — the CLI manages model downloads from Hugging Face, the macOS browser loads and runs them, and new MCP tools let LLMs ask the local model to summarise/describe/analyse the current page without sending data to the cloud.

**Architecture:** The CLI owns model lifecycle (download, list, delete) using GGUF files from Hugging Face. Each browser app exposes new HTTP endpoints for model loading/unloading and inference. The MCP server adds tools to query model status and run inference. On macOS, inference runs via `llama.cpp` as a compiled Swift package. On mobile, platform AI (Apple Intelligence on iOS, Gemini Nano on Android) is the default backend — no download needed, text-only. Mobile also supports remote Ollama as an upgrade path for vision-capable models.

**Tech Stack:** llama.cpp (Swift package), Hugging Face Hub API (REST), GGUF model format, existing Kelpie HTTP/MCP patterns.

---

## System Design

### Model Storage

```
~/.kelpie/models/
  registry.json            # Tracks downloaded models, metadata, source URLs
  gemma-4-e2b-q4/
    model.gguf
    metadata.json          # Name, size, quantization, capabilities, source URL
  moondream2-q4/
    model.gguf
    metadata.json
```

Mobile model storage:
- iOS: `<app>/Documents/models/`
- Android: `<app>/files/models/`

**Shared model store (macOS).** Both the CLI and the macOS app read and write `~/.kelpie/models/`. Either can download, delete, or list models. File-level locking (`flock`) prevents concurrent writes during downloads.

### Config File

```
~/.kelpie/ai-config.json
```

Single source of truth for the active AI state. Every browser window, the CLI, and the MCP server all read and watch this file.

```json
{
  "activeModel": "gemma-4-e2b-q4",
  "backend": "native",
  "ollamaEndpoint": "http://localhost:11434",
  "ollamaModel": null,
  "loadedAt": "2026-04-02T14:30:00Z"
}
```

| Field | Description |
|---|---|
| `activeModel` | Model ID currently loaded (null = none) |
| `backend` | `"native"`, `"ollama"`, or `"platform"` (mobile default) |
| `ollamaEndpoint` | Ollama API URL (persisted across sessions) |
| `ollamaModel` | Ollama model name when backend is ollama (e.g. `"llava:7b"`) |
| `loadedAt` | ISO 8601 timestamp of last load — informational only, shown in `ai status` output. Not used for staleness detection (the in-memory engine is the authority). |

**Who writes:**
- macOS app (any window) — when user loads/unloads via the Models tab
- CLI — when user runs `kelpie ai load` / `kelpie ai unload`
- All writes use `flock` to prevent corruption

**Who watches:**
- Every macOS browser window watches `ai-config.json` via `DispatchSource.makeFileSystemObjectSource` (FSEvents). When the file changes, all windows update their `AIState` immediately — the brain pill, the panel's Chat tab header, and the Models tab active indicator all reflect the new model within one frame.
- The CLI reads it on startup for `kelpie ai status` (local mode, no device needed).

**Cross-window behavior:** Switching models in one browser window writes `ai-config.json` → FSEvents fires → all other windows pick up the change. Since only one model can be loaded at a time (process-wide), all windows share the same loaded model. Each window has its own independent chat history, but the model is global.

**`registry.json` vs `ai-config.json`:**
- `registry.json` — tracks which models are downloaded (persistent inventory)
- `ai-config.json` — tracks which model is currently active (runtime state)

**Startup reconciliation:** On app launch, `ai-config.json` may claim a model is loaded from a previous session that crashed or was force-quit. The app must clear `activeModel` to `null` on every startup — the in-memory `InferenceEngine` is the true authority for whether a model is loaded. The config file is only authoritative for `ollamaEndpoint` (persisted setting) and as a cross-window notification channel. It is not a cache of runtime state across restarts.

**Write-ownership rule:** Only the process that owns the `InferenceEngine` (the macOS app) may write `activeModel` and `backend` fields. The CLI must use HTTP (`POST /v1/ai-load`) to trigger model changes — it must never write `ai-config.json` directly for load/unload. Direct file edits by users or scripts are ignored for model state; the app treats them as no-ops since the in-memory engine hasn't changed.

**FSEvents watching:** Watch the *directory* (`~/.kelpie/`) and filter for `ai-config.json` filename changes, not the file descriptor directly. This handles delete+recreate patterns from atomic writes. If the file is deleted, the app recreates it with `activeModel: null`.

The macOS app also watches `~/.kelpie/models/` directory for download changes (CLI adding/removing model files). Both watches use the same FSEvents mechanism.

The CLI can also manage models on a running device remotely via HTTP:
- `kelpie ai load <model> --device mac` → `POST /v1/ai-load`
- `kelpie ai unload --device mac` → `POST /v1/ai-unload`
- `kelpie ai status --device mac` → `POST /v1/ai-status`

Downloads always happen locally (CLI or app write to disk) — the HTTP API only handles load/unload/status/inference.

### Approved Model Registry

The CLI ships with a built-in list of approved models (JSON embedded in the package). Each entry specifies:

```ts
interface ApprovedModel {
  id: string;                    // e.g. "gemma-4-e2b-q4"
  name: string;                  // e.g. "Gemma 4 E2B Q4"
  huggingFaceRepo: string;       // e.g. "bartowski/gemma-4-E2B-it-GGUF"
  huggingFaceFile: string;       // e.g. "gemma-4-E2B-it-Q4_K_M.gguf"
  sha256: string;                // SHA-256 of the GGUF file — verified after download
  sizeBytes: number;             // Approximate download size
  ramWhenLoadedGB: number;       // RAM consumed when model is active (~1.5x file size)
  capabilities: string[];        // ["text", "vision", "audio"] — audio = model accepts raw audio input (max 30s)
  memory: boolean;               // true = supports multi-turn conversation, false = stateless Q&A only
  platforms: string[];           // ["macos", "ios", "android"]
  minRamGB: number;              // Minimum total device RAM to run
  recommendedRamGB: number;      // Comfortable total device RAM (no amber warning)
  quantization: string;          // "Q4_K_M", "Q8_0", etc.
  contextWindow: number;         // Max context in tokens (e.g. 8192 for Gemma 2B)
  description: ModelDescription; // Structured description for UI display
}

interface ModelDescription {
  summary: string;               // 1 sentence: what does this model do?
  strengths: string[];           // 2-3 bullet points
  limitations: string[];         // 1-2 bullet points
  bestFor: string;               // "Best for: ___"
  speedRating: "fast" | "moderate" | "slow";
}
```

**`memory` field:** Indicates whether the model can maintain context across multiple queries. Native GGUF models are `memory: false` — every query is a fresh start with no conversation history. Ollama models are `memory: true` — Ollama handles context server-side, so the in-app chat sends a sliding window of recent exchanges via `/api/chat`. MCP callers always get stateless behavior regardless of the `memory` flag. The UI shows this as a badge so users know what to expect.

**`capabilities` values:**

| Capability | Meaning |
|---|---|
| `text` | Accepts text prompts (all models) |
| `vision` | Accepts image input — can describe screenshots |
| `audio` | Accepts raw audio input — model processes speech natively (max 30s) |

**Voice input routing:** When the user taps the 🎤 button in the chat input, the browser checks the loaded model's capabilities:

- **Model has `audio` capability** (e.g. Gemma 4 E2B): Raw audio (16-bit PCM WAV, 16kHz mono) is sent directly to the model via `ai-infer`. The model handles both transcription and understanding in a single pass. This is the preferred path — higher quality than platform STT.
- **Model lacks `audio` capability** (text-only): Falls back to platform speech-to-text (SFSpeechRecognizer on Apple, SpeechRecognizer on Android), then sends the transcribed text as a normal chat message. Degraded experience but still functional.

The brain pill itself toggles the chat panel (macOS) or navigates to the chat screen (mobile). It is NOT the mic trigger — the mic lives inside the chat input area.

Mobile apps (iOS/Android) embed their own curated subset of this list. To add a model to the mobile list, users raise a PR against the relevant app.

On macOS via CLI, users can also specify an arbitrary Hugging Face GGUF URL to download — the approved list is the default, not a restriction.

**Hugging Face downloads require no account.** All approved models use public repos (community quantizations like bartowski's). The `resolve/main/` download URL works with a plain GET, no auth headers. Gated models (e.g., Meta's official Llama releases) require accepting a license + HF token, but those are not in our approved list. If a user specifies a custom gated model URL, the download will fail with a clear 401 error — the CLI should suggest they provide a HF token via `--token` or the `HF_TOKEN` env var.

**Only one model loaded at a time.** The browser loads a single model into memory. Loading a second model requires unloading the first. This is a hard constraint — we can't afford to keep multiple models in RAM, especially on devices with 8-16 GB.

**macOS native inference requires Apple Silicon (M1+).** llama.cpp depends on the Neural Engine and unified memory architecture. On Intel Macs, native GGUF inference is disabled. However, **Ollama-only mode is available on Intel** — if Ollama is detected, Intel users see the brain pill and can use Ollama models. The AI panel's Models tab shows only Ollama models (no native download cards). If Ollama is not running, AI is fully hidden on Intel. Check at startup: `sysctl("hw.optional.arm64")`.

### Ollama Integration

If the user has Ollama installed, Kelpie detects it and surfaces Ollama-managed models as a second-tier option alongside the native GGUF models.

**Detection:** Check if the Ollama API is reachable at `http://localhost:11434/api/tags` (the default Ollama endpoint). This is a simple GET that returns a JSON list of installed models. No configuration needed — if Ollama is running, we find it.

**Display in `kelpie ai list`:**

```
Native Models (GGUF via llama.cpp)
─────────────────────────────────────────────────────
  gemma-4-e2b-q4      2.5 GB   text, vision   ✓ downloaded
  gemma-4-e2b-q8      5.0 GB   text, vision   not downloaded

─── Ollama Models (detected at localhost:11434) ────
  llama3.2:3b          2.0 GB   text
  gemma2:2b            1.6 GB   text
  llava:7b             4.7 GB   text, vision
```

**How Ollama models work in the inference pipeline:**

When the user loads an Ollama model, the browser doesn't load a GGUF file — instead, the `ai-infer` endpoint proxies the request to Ollama's API. This means:

1. `ai-load` with an Ollama model ID sets the engine mode to `ollama` and records the model name — no file path needed, no memory consumed in the browser process
2. `ai-infer` detects the Ollama backend and routes:
   - **In-app (brain pill / floating menu):** Uses `/api/chat` with a sliding window of recent messages (last 10 exchanges). Users can ask follow-ups.
   - **Via MCP (`kelpie_ai_ask`):** Uses `/api/generate` with a single prompt. Stateless, no history.
3. `ai-unload` clears the state and conversation history — Ollama manages its own model memory
4. `ai-status` reports `backend: "ollama"` so the caller knows which engine is active

**Request routing in AIHandler:**

```
ai-infer request arrives
  → check backend mode
  → if "native": run llama.cpp inference (existing path)
  → if "ollama": POST to Ollama API with prompt + image
      → parse Ollama response
      → return in standard Kelpie response format
  → if "platform": route to platform AI (iOS: Foundation Models, Android: AI Edge SDK)
      → text-only — reject image/audio inputs with VISION_NOT_SUPPORTED / AUDIO_NOT_SUPPORTED
      → return in standard Kelpie response format
```

**Ollama API usage:**

```
# List models
GET http://localhost:11434/api/tags
→ { "models": [{ "name": "llama3.2:3b", "size": 2000000000, ... }] }

# Generate — stateless, single prompt (used by MCP)
POST http://localhost:11434/api/generate
{ "model": "llama3.2:3b", "prompt": "...", "stream": false }
→ { "response": "...", "total_duration": 1234, "eval_count": 50 }

# Generate with vision
POST http://localhost:11434/api/generate
{ "model": "llava:7b", "prompt": "...", "images": ["<base64>"], "stream": false }
→ { "response": "...", "total_duration": 2345, "eval_count": 80 }

# Chat — multi-turn with history (used by in-app brain pill)
POST http://localhost:11434/api/chat
{ "model": "llama3.2:3b", "messages": [
    { "role": "system", "content": "<system prompt>" },
    { "role": "user", "content": "What's on this page?" },
    { "role": "assistant", "content": "The page shows..." },
    { "role": "user", "content": "What about the pricing?" }
  ], "stream": false }
→ { "message": { "role": "assistant", "content": "..." }, "total_duration": 1500 }
```

**CLI model ID convention:**

- Native models: `gemma-4-e2b-q4` (plain ID)
- Ollama models: `ollama:llama3.2:3b` (prefixed with `ollama:`)

This prefix makes it unambiguous in all commands:
```
kelpie ai load ollama:llava:7b --device mac
kelpie ai ask "describe this page" --device mac --context screenshot
```

**No download management for Ollama:** Kelpie doesn't pull or delete Ollama models — the user manages those with `ollama pull` / `ollama rm` directly. Kelpie only reads what's available.

### Architecture Layers

```
┌─────────────────────────────────────────────┐
│                 LLM (Claude)                │
│         Uses MCP tools to interact          │
├─────────────────────────────────────────────┤
│              CLI MCP Server                 │
│  kelpie_ai_*  tools (model + inference)   │
├─────────────────────────────────────────────┤
│              CLI Commands                   │
│  kelpie ai pull / list / rm / status      │
├─────────┬───────────────────────────────────┤
│  Model  │     HTTP Client                   │
│  Store  │  POST /v1/ai-load                 │
│ (~/.m/) │  POST /v1/ai-unload              │
│         │  POST /v1/ai-infer               │
│         │  GET  /v1/ai-status              │
├─────────┴───────────────────────────────────┤
│           Browser App (macOS)               │
│                                             │
│  AIHandler (HTTP handler)                   │
│  ┌─────────────────────────────────────┐    │
│  │ ai-load: load model (native/ollama) │    │
│  │ ai-unload: free model from memory   │    │
│  │ ai-status: report loaded model      │    │
│  │ ai-infer: route to active backend   │    │
│  └──────────┬──────────────┬───────────┘    │
│             │              │                │
│  ┌──────────▼────┐  ┌─────▼──────────┐  ┌──▼─────────────┐│
│  │ Native Engine │  │ Ollama Proxy   │  │ Platform AI    ││
│  │ (llama.cpp)   │  │ localhost:11434│  │ (mobile only)  ││
│  │ Load GGUF     │  │ /api/generate  │  │ Apple Intel.   ││
│  │ Run locally   │  │ Forward prompt │  │ Gemini Nano    ││
│  └───────────────┘  └────────────────┘  └────────────────┘│
└─────────────────────────────────────────────┘
```

### HTTP API (Browser App Endpoints)

All new endpoints use the existing `/v1/` prefix pattern.

#### `POST /v1/ai-load`

Load a model into memory. Only one model can be loaded at a time. Supports both native GGUF and Ollama backends.

```json
// Request (native GGUF by model ID — resolved to local path by the handler)
{ "model": "gemma-4-e2b-q4" }

// Request (native GGUF by absolute path — for custom models)
{ "path": "/Users/foo/.kelpie/models/custom/model.gguf" }

// Request (Ollama model — local)
{ "model": "ollama:llava:7b" }

// Request (Ollama model — remote endpoint, used by mobile devices)
{ "model": "ollama:llava:7b", "ollamaEndpoint": "http://192.168.1.50:11434" }

// Response (success — auto-unloads previous model if any)
{ "success": true, "model": "gemma-4-e2b-q4", "backend": "native", "loadTimeMs": 2340 }

// Response (success — Ollama)
{ "success": true, "model": "llava:7b", "backend": "ollama", "loadTimeMs": 12 }

// Response (error — file not found)
{ "success": false, "error": { "code": "MODEL_NOT_FOUND", "message": "No GGUF file at specified path" } }

// Response (error — Ollama not running)
{ "success": false, "error": { "code": "OLLAMA_NOT_AVAILABLE", "message": "Ollama is not running at localhost:11434" } }
```

#### `POST /v1/ai-unload`

Unload the current model, freeing memory.

```json
// Request
{}

// Response
{ "success": true }
```

#### `POST /v1/ai-status`

Report the current inference state.

```json
// Response (native model loaded)
{
  "success": true,
  "loaded": true,
  "model": "gemma-4-e2b-q4",
  "backend": "native",
  "capabilities": ["text", "vision"],
  "memoryUsageMB": 2800
}

// Response (Ollama model loaded)
{
  "success": true,
  "loaded": true,
  "model": "llava:7b",
  "backend": "ollama",
  "capabilities": ["text", "vision"],
  "ollamaEndpoint": "http://localhost:11434"
}

// Response (remote Ollama — mobile)
{
  "success": true,
  "loaded": true,
  "model": "llava:7b",
  "backend": "ollama",
  "capabilities": ["text", "vision"],
  "ollamaEndpoint": "http://192.168.1.50:11434"
}

// Response (no model)
{
  "success": true,
  "loaded": false
}
```

#### `POST /v1/ai-infer`

Run inference. The model generates a response to the prompt. Supports text, vision (base64 image), and audio (base64 WAV, max 30 seconds) inputs.

**Routing:** The `ai-infer` endpoint handles both stateless single-shot and multi-turn Ollama chat. The presence of the `messages` field determines which path:
- `messages` absent → single-shot (native llama.cpp or Ollama `/api/generate`)
- `messages` present → multi-turn (Ollama `/api/chat` only — ignored for native models)

The in-app chat panel sends `messages` for Ollama models with `memory: true`. MCP callers and the CLI always omit `messages` (stateless).

```json
// Request — single-shot (MCP, CLI, or native model)
{
  "prompt": "Summarise this page content in 3 bullet points",
  "context": "page_text",
  "maxTokens": 512,
  "temperature": 0.7
}

// Request — multi-turn Ollama chat (in-app panel only)
{
  "prompt": "What about the enterprise tier?",
  "messages": [
    { "role": "system", "content": "<system prompt>" },
    { "role": "user", "content": "What are the prices?" },
    { "role": "assistant", "content": "The page shows three tiers..." }
  ],
  "context": "page_text",
  "maxTokens": 512
}

// Request (with screenshot)
{
  "prompt": "Describe what you see on this page",
  "context": "screenshot",
  "maxTokens": 512
}

// Request (with raw audio — model has audio capability)
{
  "audio": "<base64 WAV/PCM data, 16kHz mono, max 30 seconds>",
  "context": "page_text",
  "maxTokens": 512
}

// Request (voice transcribed by platform STT — model lacks audio)
{
  "prompt": "What are the prices on this page?",
  "voiceTranscription": true,
  "context": "page_text",
  "maxTokens": 512
}

// Request (explicit data — debugging)
{
  "prompt": "What language is this code?",
  "text": "<html>...</html>",
  "maxTokens": 256
}

// Response
{
  "success": true,
  "response": "The page shows a pricing table with three tiers...",
  "tokensUsed": 187,
  "inferenceTimeMs": 1450
}

// Response (audio-capable model — includes transcription)
{
  "success": true,
  "transcription": "What are the prices on this page?",
  "response": "The page shows three pricing tiers: Basic at $9/mo, Pro at $29/mo, and Enterprise at $99/mo.",
  "tokensUsed": 6243,
  "inferenceTimeMs": 2100
}

// Error — no model loaded
{ "success": false, "error": { "code": "NO_MODEL_LOADED", "message": "Load a model first with ai-load" } }

// Error — audio sent to model without audio capability
{ "success": false, "error": { "code": "AUDIO_NOT_SUPPORTED", "message": "Model does not support audio. Transcribe via platform STT and resend as text." } }

// Error — Ollama unreachable mid-inference
{ "success": false, "error": { "code": "OLLAMA_DISCONNECTED", "message": "Lost connection to Ollama during inference" } }
```

**Voice input routing (browser-side):**

The browser decides how to handle voice input before calling `ai-infer`:

1. User taps 🎤 in chat input → browser records audio (max 30s, 16-bit PCM WAV, 16kHz mono)
2. Browser checks loaded model's capabilities via cached `ai-status`
3. **If model has `audio` capability:** Send raw audio in the `audio` field → model transcribes and responds in one pass (preferred — higher quality)
4. **If model lacks `audio` capability:** Transcribe locally via platform STT (SFSpeechRecognizer / SpeechRecognizer) → send transcribed text in the `prompt` field (fallback)

The `voiceTranscription: true` flag is metadata — the harness treats it identically to a typed prompt. It's recorded for analytics/debugging.

### Inference Harness (Agent Loop)

A 2B model cannot handle a massive context dump. Instead of loading everything upfront, the harness runs a lightweight agent loop: the model gets a minimal page summary, decides what tools it needs, the harness executes them, feeds results back, and the model answers.

**Why a harness:**
- 2B models have limited context windows and degrade with large inputs
- Most questions only need 1-2 data sources, not all 12
- The model should request what it needs, not receive everything
- Keeps inference fast — small prompt → fast response

#### System Prompt

The harness prepends a fixed system prompt to every inference call. This prompt is embedded in the browser app, not configurable by the user.

```
You are a browser assistant built into Kelpie. You answer questions about the web page currently loaded in the browser.

Rules:
- Be concise. One to three sentences unless the user asks for detail.
- Only answer questions you can answer from the page data provided. If you cannot answer, say so in one sentence.
- Do not make up information. Do not guess URLs, prices, or facts not present in the data.
- Do not engage in general conversation, tell jokes, discuss weather, or answer questions unrelated to the current page.
- If the user asks something about the page and you need more data, use a tool call.
- When referencing page elements, include the CSS selector when available.
- When reporting errors, include the exact error message.

You have access to these tools. Call them by responding with a JSON tool call:
{tools_block}

Respond with EITHER a tool call OR a final answer, never both.

Tool call format:
{"tool": "tool_name", "args": {"key": "value"}}

Final answer format:
{"answer": "your response", "references": [...]}
```

The `{tools_block}` is injected at runtime — a compact list of available tools with one-line descriptions. This keeps the system prompt small and stable.

#### Available Tools (Harness-Side)

The harness exposes a curated subset of Kelpie's handlers as tools the model can call. These are NOT the MCP tools — they're internal shortcuts that run in-process without HTTP round-trips.

| Tool | Description | Maps to |
|---|---|---|
| `get_text` | Get readable page text (title, content, word count) | `get-page-text` |
| `get_screenshot` | Take a viewport screenshot | `screenshot` |
| `get_dom` | Get HTML of an element (default: body, max 2000 chars) | `get-dom` with truncation |
| `get_element` | Get text/attributes of a specific CSS selector | `get-element-text` + `get-attributes` |
| `find_element` | Find elements by text content | `find-element` |
| `get_forms` | Get form field names, types, and values | `get-form-state` |
| `get_errors` | Get JavaScript errors | `get-js-errors` |
| `get_console` | Get recent console messages (last 20) | `get-console-messages` with limit |
| `get_network` | Get recent network requests (last 20) | `get-network-log` with limit |
| `get_cookies` | Get cookies for current page | `get-cookies` |
| `get_storage` | Get localStorage keys and values | `get-storage` |
| `get_links` | Get all links on the page (href + text) | `query-selector-all` for `a[href]` |
| `get_visible` | Get visible interactive elements | `get-visible-elements` |
| `get_a11y` | Get accessibility tree (max depth 3) | `get-accessibility-tree` with depth limit |

Every tool applies aggressive truncation — the harness caps each tool result at a token budget (default 1500 tokens) to prevent blowing the model's context. Long DOM trees, large console logs, and verbose network logs are trimmed to fit.

#### Agent Loop

```
1. Build initial prompt:
   - System prompt (fixed, ~300 tokens)
   - Page summary (auto-gathered, ~100 tokens):
     title, URL, word count, error count, form count
   - User's question or voice transcription

2. Run inference → model responds

3. If response is a tool call:
   - Execute the tool in-process (no HTTP)
   - Truncate result to token budget
   - Append tool result to conversation
   - Run inference again (step 2)
   - Max 3 tool calls per query (hard limit, prevents loops)

4. If response is a final answer:
   - Extract answer text and references
   - Return to caller
```

**Max 3 rounds:** The model gets at most 3 tool calls before it must answer. This prevents infinite loops and keeps response time under control. A typical query uses 0-1 tool calls.

#### Page Summary (Auto-Gathered)

Every inference call starts with a lightweight page summary that costs ~100 tokens. This gives the model enough context to decide if it needs tools.

```
Page: "Pricing - Acme Corp"
URL: https://acme.com/pricing
Words: 1,247
Forms: 1 (3 fields)
JS Errors: 2
Console: 8 messages (3 warnings, 2 errors)
Network: 34 requests (2 failed)
Links: 47
Interactive elements: 12
```

This summary is cheap to gather (runs in-process from cached state) and tells the model what's available without loading any of it. If the user asks "are there any errors?", the model sees `JS Errors: 2` and calls `get_errors` to get the details.

#### Conversation Modes

**Native GGUF models (via MCP and brain pill):** Stateless. Every query is completely self-contained — no conversation history, no memory of previous questions, no session state. Each tap of the brain pill starts from zero. The harness builds a fresh context for every inference call: system prompt + page summary + user question. Nothing is carried over.

**Why stateless for native:** A 2B model cannot maintain coherent multi-turn conversation — it loses track, hallucinates, and contradicts itself. Single-shot Q&A is where small models actually work well.

**Ollama models — in-app (brain pill / floating menu):** Chat-capable. The app maintains a sliding window of recent exchanges within the session and sends them to Ollama's `/api/chat` endpoint. Users can ask follow-up questions ("what about the third column?") and the model has prior context. The window is capped at the last 10 exchanges to prevent unbounded growth. Session resets when the user navigates to a new page or closes the browser.

**Ollama models — via MCP:** Stateless. Every `kelpie_ai_ask` call is a single prompt in, single answer out. No history is carried between MCP calls. This keeps MCP tool usage predictable for orchestrating LLMs.

**The `memory` flag:** The model registry's `memory: boolean` field controls which mode the harness uses. `false` = always stateless (native GGUFs). `true` = chat-capable in the app UI, stateless via MCP. Ollama models default to `memory: true` since Ollama handles context server-side.

**Ollama `/api/chat` request format:**

```json
{
  "model": "llava:7b",
  "messages": [
    { "role": "system", "content": "<system prompt>" },
    { "role": "user", "content": "What's on this page?" },
    { "role": "assistant", "content": "The page shows a pricing table..." },
    { "role": "user", "content": "What's the cheapest tier?" }
  ],
  "stream": false
}
```

#### Token Budget Management

The context window for Gemma 2B models is **8K tokens** (not 128K — that's the larger Gemma variants). Audio and vision consume tokens at a higher rate:

| Input type | Token cost |
|---|---|
| Text | ~1 token per 4 characters |
| Audio (30s clip, native) | ~6,000 tokens (audio encoder output) |
| Audio (5s clip, native) | ~1,000 tokens |
| Audio (STT fallback) | ~20-50 tokens (just transcribed text) |
| Screenshot (1120 visual tokens — max quality) | ~1,120 tokens |
| Screenshot (280 visual tokens — default) | ~280 tokens |
| Screenshot (70 visual tokens — fast/low) | ~70 tokens |

The harness uses `280` visual tokens (default) for screenshots unless the caller specifies otherwise. This is a good balance — enough to see page layout and read large text, not enough to read 8px footnotes.

**Budget allocation:**

| Component | Budget (text-only) | Budget (voice + screenshot) |
|---|---|---|
| System prompt | ~300 | ~300 |
| Page summary | ~100 | ~100 |
| User prompt | ~100 | — |
| Audio input (native) | — | ~1,000-6,000 |
| Screenshot | — | ~280 |
| Tool results (per call, max 3) | ~1,500 each | ~1,000 each |
| Model response | ~500 | ~500 |
| **Total worst case** | ~5,500 | ~10,180 |

Well within 8K, but the tight budgets are about quality — small models produce better answers with focused input. When native audio is present, tool result budgets are reduced from 1,500 to 1,000 tokens to keep the total reasonable. When the STT fallback is used, audio costs ~30 tokens instead of ~6,000, so full tool budgets apply.

#### Truncation Strategy

Each tool result is truncated to fit its budget:

- **Text content:** First N characters, with a `[truncated, {total} chars total]` suffix
- **DOM:** Outer HTML of the target element, children collapsed after depth 2
- **Lists (console, network, errors):** Most recent N entries, with a `[{total} total, showing last {N}]` header
- **Screenshots:** Passed directly to the vision encoder (no truncation, but scaled to the model's expected resolution)

#### Example: Voice Query Flow

User taps brain, says: "Why is the form not working?"

```
Round 1:
  System prompt + page summary + "Why is the form not working?"
  → Model responds: {"tool": "get_errors"}

Round 2:
  + Tool result: [2 errors: "TypeError: email is undefined at line 42", "Uncaught ReferenceError: validate at line 18"]
  → Model responds: {"tool": "get_forms"}

Round 3:
  + Tool result: [1 form, 3 fields: email (empty, required), password (filled), submit (button)]
  → Model responds: {"answer": "The form has 2 JS errors. The email field is empty but required, and there's a TypeError at line 42 trying to read the email value. Fill in the email field to fix the submission.", "references": [{"type": "element", "selector": "input[name=email]"}, {"type": "error", "message": "TypeError: email is undefined", "line": 42}]}
```

Total: 3 inference calls, ~2000 tokens of context, ~3 seconds on M2.

#### Caller-Provided Context (Override)

The `context` field on the `ai-infer` request is still supported as a way for the MCP caller (or CLI) to pre-load specific data. When provided, the harness skips the agent loop and does a single-shot inference with the pre-loaded context:

- `"page_text"` — runs `get-page-text`, prepends readable text
- `"screenshot"` — takes a viewport screenshot, passes as image input
- `"dom"` — runs `get-dom`, prepends HTML
- `"accessibility"` — runs `get-accessibility-tree`, prepends the tree
- omitted — uses the agent loop (default)

This is an escape hatch for callers who know exactly what context is needed. The agent loop is the default for interactive use (UI brain pill, voice).

### MCP Tools

All new tools use the `kelpie_ai_` prefix.

#### Browser Tools (per-device)

| Tool | Description | Method |
|------|-------------|--------|
| `kelpie_ai_status` | Get the inference engine status on a device — whether a model is loaded, which model, capabilities, memory usage | `aiStatus` |
| `kelpie_ai_load` | Load a model on a device from a file path | `aiLoad` |
| `kelpie_ai_unload` | Unload the current model from a device, freeing memory | `aiUnload` |
| `kelpie_ai_ask` | Ask the local model a question about the current page. Supports text prompt, voice audio (base64 WAV, max 30s), and context modes to auto-gather page data. Returns the model's response. Runs entirely on-device. | `aiInfer` |
| `kelpie_ai_record` | Start/stop audio recording on the device microphone. Returns base64 WAV when stopped. | `aiRecord` |

#### CLI Tools (model management)

| Tool | Description | Kind |
|------|-------------|------|
| `kelpie_ai_models` | List all available models: approved registry, downloaded, and Ollama-detected. Ollama models appear with an `ollama:` prefix. | `discovery` |
| `kelpie_ai_pull` | Download a model from Hugging Face to the local model store | `discovery` |
| `kelpie_ai_remove` | Delete a downloaded model from the local store | `discovery` |

### CLI Commands

```
kelpie ai pull <model-id>       Download a model (from approved list or HF URL)
kelpie ai list                  List approved models and their download status
kelpie ai rm <model-id>         Delete a downloaded model
kelpie ai status [--device X]   Check what model is loaded on a device
kelpie ai load <model-id> [--device X]    Load model on device
kelpie ai unload [--device X]   Unload model from device
kelpie ai ask "<prompt>" [--device X] [--context page_text|screenshot|dom|accessibility]
                                  Run inference on the device's loaded model
```

The `pull` command:
1. Resolves model-id against the approved registry
2. If not found and it looks like a HF repo path (contains `/`), treats it as a custom HF GGUF
3. Downloads to `~/.kelpie/models/<model-id>/model.gguf` with progress bar
4. Writes `metadata.json` with source info

The `load` command:
1. Sends `POST /v1/ai-load { "model": "<model-id>" }` to the target device
2. The **device** resolves the model ID to its local file path (the CLI never sends absolute paths — the model must be downloaded on the target device)

### Error Handling

The MCP tools should return clear, actionable errors:

| Error Code | Meaning | Action |
|---|---|---|
| `NO_MODEL_LOADED` | Inference requested but no model is loaded | Use `kelpie_ai_load` first |
| `MODEL_ALREADY_LOADED` | Load requested but a model is already active | Use `kelpie_ai_unload` first, or use the loaded model |
| `MODEL_NOT_FOUND` | The specified model file doesn't exist locally | Use `kelpie_ai_pull` to download it |
| `MODEL_TOO_LARGE` | Device doesn't have enough RAM for this model | Try a smaller quantization or different model |
| `INFERENCE_FAILED` | The model failed to generate a response | Check model compatibility, try a simpler prompt |
| `VISION_NOT_SUPPORTED` | Screenshot context requested but model has no vision capability | Use `page_text` context instead, or load a vision-capable model |
| `AUDIO_NOT_SUPPORTED` | Raw audio sent to a model without audio capability | Browser should transcribe via platform STT and resend as text |
| `TRANSCRIPTION_FAILED` | Platform speech-to-text failed to transcribe audio | Try again, speak more clearly, or type the query |
| `OLLAMA_DISCONNECTED` | Ollama became unreachable during inference | Check if Ollama is still running |
| `CHECKSUM_MISMATCH` | Downloaded file SHA-256 doesn't match expected hash | Re-download the model |
| `DOWNLOAD_IN_PROGRESS` | Another process is already downloading this model | Wait for it to finish |
| `RECORDING_ALREADY_ACTIVE` | `ai-record` start called while already recording | Stop current recording first |
| `NO_RECORDING_ACTIVE` | `ai-record` stop called with no active recording | Start recording first |
| `MIC_PERMISSION_DENIED` | Microphone permission not granted | Grant microphone access in System Settings |
| `OLLAMA_NOT_AVAILABLE` | Ollama backend requested but the API is unreachable | Start Ollama or check the endpoint URL |
| `OLLAMA_MODEL_NOT_FOUND` | The specified Ollama model isn't installed | Run `ollama pull <model>` to install it |
| `PLATFORM_AI_UNAVAILABLE` | Platform AI requested but not available on this device | Device doesn't support Apple Intelligence / Gemini Nano |

---

## Implementation Tasks

**Prerequisite (not a numbered task — do first):** Extend `DeviceInfo.system` in `packages/shared/src/device-types.ts` to add `diskFreeGB: number`, `chipset: string`. Update all platform implementations (macOS, iOS, Android) to report these fields. The UI plan's hardware fitness scoring depends on them.

### Task 1: Approved Model Registry (CLI)

**Files:**
- Create: `packages/cli/src/ai/models.ts`
- Test: `packages/cli/tests/ai/models.test.ts`

**Step 1: Write the failing test**

```ts
import { describe, it, expect } from "vitest";
import { getApprovedModels, findModel } from "../../src/ai/models.js";

describe("approved model registry", () => {
  it("returns a non-empty list of approved models", () => {
    const models = getApprovedModels();
    expect(models.length).toBeGreaterThan(0);
    expect(models[0]).toHaveProperty("id");
    expect(models[0]).toHaveProperty("huggingFaceRepo");
  });

  it("finds a model by id", () => {
    const model = findModel("gemma-4-e2b-q4");
    expect(model).toBeDefined();
    expect(model!.id).toBe("gemma-4-e2b-q4");
  });

  it("returns undefined for unknown model", () => {
    expect(findModel("nonexistent")).toBeUndefined();
  });
});
```

**Step 2: Run test to verify it fails**

Run: `cd packages/cli && pnpm test -- --run tests/ai/models.test.ts`
Expected: FAIL — module not found

**Step 3: Write minimal implementation**

`packages/cli/src/ai/models.ts`:
```ts
export interface ModelDescription {
  summary: string;
  strengths: string[];
  limitations: string[];
  bestFor: string;
  speedRating: "fast" | "moderate" | "slow";
}

export interface ApprovedModel {
  id: string;
  name: string;
  huggingFaceRepo: string;
  huggingFaceFile: string;
  sha256: string;
  sizeBytes: number;
  ramWhenLoadedGB: number;
  capabilities: string[];
  memory: boolean;
  platforms: string[];
  minRamGB: number;
  recommendedRamGB: number;
  quantization: string;
  contextWindow: number;
  description: ModelDescription;
}

const approvedModels: ApprovedModel[] = [
  {
    id: "gemma-4-e2b-q4",
    name: "Gemma 4 E2B Q4",
    huggingFaceRepo: "bartowski/gemma-4-E2B-it-GGUF",
    huggingFaceFile: "gemma-4-E2B-it-Q4_K_M.gguf",
    sha256: "", // TODO: fill after first download verification
    sizeBytes: 2_500_000_000,
    ramWhenLoadedGB: 3.8,
    capabilities: ["text", "vision", "audio"],
    memory: false,
    platforms: ["macos"],
    minRamGB: 8,
    recommendedRamGB: 16,
    contextWindow: 8192,
    quantization: "Q4_K_M",
    description: {
      summary: "Understands text, images, and speech — can describe screenshots and answer voice questions.",
      strengths: ["Describe what's on a webpage from a screenshot", "Summarise articles and extract key info", "Answer voice questions about page content"],
      limitations: ["Slower when processing images", "May struggle with very long pages (over 10,000 words)"],
      bestFor: "General page analysis with visual and voice understanding",
      speedRating: "moderate",
    },
  },
  {
    id: "gemma-4-e2b-q8",
    name: "Gemma 4 E2B Q8",
    huggingFaceRepo: "bartowski/gemma-4-E2B-it-GGUF",
    huggingFaceFile: "gemma-4-E2B-it-Q8_0.gguf",
    sha256: "", // TODO: fill after first download verification
    sizeBytes: 5_000_000_000,
    ramWhenLoadedGB: 8,
    capabilities: ["text", "vision", "audio"],
    memory: false,
    platforms: ["macos"],
    minRamGB: 16,
    recommendedRamGB: 32,
    contextWindow: 8192,
    quantization: "Q8_0",
    description: {
      summary: "Higher quality version of Gemma 4 — more accurate but needs more memory.",
      strengths: ["More accurate responses, especially for nuanced questions", "Better at complex page layouts", "Same vision + audio as Q4"],
      limitations: ["Needs 16 GB RAM minimum", "Slightly slower than Q4"],
      bestFor: "When accuracy matters more than speed",
      speedRating: "moderate",
    },
  },
];

export function getApprovedModels(): ApprovedModel[] {
  return approvedModels;
}

export function findModel(id: string): ApprovedModel | undefined {
  return approvedModels.find((m) => m.id === id);
}
```

**Step 4: Run test to verify it passes**

Run: `cd packages/cli && pnpm test -- --run tests/ai/models.test.ts`
Expected: PASS

**Step 5: Commit**

```bash
git add packages/cli/src/ai/models.ts packages/cli/tests/ai/models.test.ts
git commit -m "feat(cli): add approved model registry for local inference"
```

---

### Task 2: Model Store — Download & Manage (CLI)

**Files:**
- Create: `packages/cli/src/ai/store.ts`
- Test: `packages/cli/tests/ai/store.test.ts`

**Step 1: Write the failing test**

```ts
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { mkdtempSync, rmSync, existsSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { ModelStore } from "../../src/ai/store.js";

describe("ModelStore", () => {
  let dir: string;
  let store: ModelStore;

  beforeEach(() => {
    dir = mkdtempSync(join(tmpdir(), "kelpie-models-"));
    store = new ModelStore(dir);
  });

  afterEach(() => {
    rmSync(dir, { recursive: true, force: true });
  });

  it("lists no models initially", () => {
    expect(store.listDownloaded()).toEqual([]);
  });

  it("reports model not downloaded", () => {
    expect(store.isDownloaded("gemma-4-e2b-q4")).toBe(false);
  });

  it("returns model path when registered", () => {
    store.register("gemma-4-e2b-q4", { name: "Gemma 4 E2B Q4", capabilities: ["text", "vision"] });
    expect(store.isDownloaded("gemma-4-e2b-q4")).toBe(true);
    expect(store.getModelPath("gemma-4-e2b-q4")).toContain("model.gguf");
  });

  it("removes a model", () => {
    store.register("gemma-4-e2b-q4", { name: "Gemma 4", capabilities: ["text"] });
    store.remove("gemma-4-e2b-q4");
    expect(store.isDownloaded("gemma-4-e2b-q4")).toBe(false);
  });
});
```

**Step 2: Run test to verify it fails**

Run: `cd packages/cli && pnpm test -- --run tests/ai/store.test.ts`
Expected: FAIL — module not found

**Step 3: Write minimal implementation**

`packages/cli/src/ai/store.ts` — manages `~/.kelpie/models/` directory, reads/writes `registry.json`, creates model subdirectories, returns file paths. Uses `node:fs` only.

Key methods:
- `listDownloaded(): DownloadedModel[]`
- `isDownloaded(id: string): boolean`
- `getModelPath(id: string): string | undefined`
- `getModelDir(id: string): string` — returns the directory for a model (creates if needed)
- `register(id: string, meta: ModelMeta): void` — marks model as downloaded, writes metadata.json
- `remove(id: string): void` — deletes model directory and registry entry

**Step 4: Run test to verify it passes**

Run: `cd packages/cli && pnpm test -- --run tests/ai/store.test.ts`
Expected: PASS

**Step 5: Commit**

```bash
git add packages/cli/src/ai/store.ts packages/cli/tests/ai/store.test.ts
git commit -m "feat(cli): add model store for managing downloaded GGUF files"
```

---

### Task 3: Hugging Face Download (CLI)

**Files:**
- Create: `packages/cli/src/ai/download.ts`
- Test: `packages/cli/tests/ai/download.test.ts`

**Step 1: Write the failing test**

```ts
import { describe, it, expect } from "vitest";
import { buildDownloadUrl, parseHuggingFaceUrl } from "../../src/ai/download.js";

describe("HuggingFace download", () => {
  it("builds a download URL from repo and file", () => {
    const url = buildDownloadUrl("bartowski/gemma-4-E2B-it-GGUF", "gemma-4-E2B-it-Q4_K_M.gguf");
    expect(url).toBe("https://huggingface.co/bartowski/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_K_M.gguf");
  });

  it("parses a full HF URL into repo and file", () => {
    const result = parseHuggingFaceUrl("https://huggingface.co/TheBloke/some-model-GGUF/resolve/main/model.Q4_K_M.gguf");
    expect(result).toEqual({ repo: "TheBloke/some-model-GGUF", file: "model.Q4_K_M.gguf" });
  });

  it("parses a repo/file shorthand", () => {
    const result = parseHuggingFaceUrl("TheBloke/some-model-GGUF/model.Q4_K_M.gguf");
    expect(result).toEqual({ repo: "TheBloke/some-model-GGUF", file: "model.Q4_K_M.gguf" });
  });
});
```

**Step 2: Run test to verify it fails**

Run: `cd packages/cli && pnpm test -- --run tests/ai/download.test.ts`
Expected: FAIL

**Step 3: Write minimal implementation**

`packages/cli/src/ai/download.ts`:
- `buildDownloadUrl(repo, file)` — constructs `https://huggingface.co/{repo}/resolve/main/{file}`
- `parseHuggingFaceUrl(input)` — handles full URLs and `owner/repo/file` shorthand
- `downloadModel(url, destPath, sha256, onProgress)` — streams the file to disk with progress callback. Writes to a `.tmp` file and renames on completion (atomic write). After download, verifies SHA-256 against the expected hash — if mismatch, deletes the file and throws `CHECKSUM_MISMATCH`.
- Download uses a per-model lock file (`<modelDir>/.downloading`) to prevent two CLI processes from downloading the same model simultaneously. If the lock file exists and the process holding it is still alive (check PID stored in the lock), abort with "download already in progress." If the PID is dead (crashed), clean up the orphaned `.tmp` and `.downloading` files, then proceed.
- On startup, `ModelStore.cleanOrphans()` scans all model directories for stale `.tmp` and `.downloading` files from crashed processes and removes them.

**Step 4: Run test to verify it passes**

Run: `cd packages/cli && pnpm test -- --run tests/ai/download.test.ts`
Expected: PASS

**Step 5: Commit**

```bash
git add packages/cli/src/ai/download.ts packages/cli/tests/ai/download.test.ts
git commit -m "feat(cli): add HuggingFace GGUF download support"
```

---

### Task 4: Ollama Detection & Proxy (CLI)

**Files:**
- Create: `packages/cli/src/ai/ollama.ts`
- Test: `packages/cli/tests/ai/ollama.test.ts`

**Step 1: Write the failing test**

```ts
import { describe, it, expect } from "vitest";
import { parseOllamaModelId, isOllamaModelId, buildOllamaGenerateRequest } from "../../src/ai/ollama.js";

describe("Ollama integration", () => {
  it("detects Ollama model IDs by prefix", () => {
    expect(isOllamaModelId("ollama:llama3.2:3b")).toBe(true);
    expect(isOllamaModelId("gemma-4-e2b-q4")).toBe(false);
  });

  it("extracts model name from prefixed ID", () => {
    expect(parseOllamaModelId("ollama:llava:7b")).toBe("llava:7b");
    expect(parseOllamaModelId("ollama:llama3.2:3b")).toBe("llama3.2:3b");
  });

  it("builds a generate request for text", () => {
    const req = buildOllamaGenerateRequest("llava:7b", "describe this", { maxTokens: 256 });
    expect(req.model).toBe("llava:7b");
    expect(req.prompt).toBe("describe this");
    expect(req.stream).toBe(false);
    expect(req.options.num_predict).toBe(256);
  });

  it("builds a generate request with image", () => {
    const req = buildOllamaGenerateRequest("llava:7b", "describe this", { image: "base64data" });
    expect(req.images).toEqual(["base64data"]);
  });
});
```

**Step 2: Run test to verify it fails**

Run: `cd packages/cli && pnpm test -- --run tests/ai/ollama.test.ts`
Expected: FAIL — module not found

**Step 3: Write minimal implementation**

`packages/cli/src/ai/ollama.ts`:

```ts
export const OLLAMA_PREFIX = "ollama:";
export const DEFAULT_OLLAMA_ENDPOINT = "http://localhost:11434";

export function isOllamaModelId(id: string): boolean {
  return id.startsWith(OLLAMA_PREFIX);
}

export function parseOllamaModelId(id: string): string {
  return id.slice(OLLAMA_PREFIX.length);
}

export interface OllamaModel {
  name: string;
  size: number;
  digest: string;
  modifiedAt: string;
}

export async function detectOllama(endpoint = DEFAULT_OLLAMA_ENDPOINT): Promise<boolean> {
  try {
    const res = await fetch(`${endpoint}/api/tags`, { signal: AbortSignal.timeout(2000) });
    return res.ok;
  } catch {
    return false;
  }
}

export async function listOllamaModels(endpoint = DEFAULT_OLLAMA_ENDPOINT): Promise<OllamaModel[]> {
  const res = await fetch(`${endpoint}/api/tags`, { signal: AbortSignal.timeout(5000) });
  if (!res.ok) return [];
  const data = (await res.json()) as { models: OllamaModel[] };
  return data.models ?? [];
}

export interface OllamaGenerateRequest {
  model: string;
  prompt: string;
  stream: false;
  images?: string[];
  options: { num_predict?: number; temperature?: number };
}

export function buildOllamaGenerateRequest(
  model: string,
  prompt: string,
  opts: { maxTokens?: number; temperature?: number; image?: string } = {},
): OllamaGenerateRequest {
  const req: OllamaGenerateRequest = {
    model,
    prompt,
    stream: false,
    options: {},
  };
  if (opts.maxTokens) req.options.num_predict = opts.maxTokens;
  if (opts.temperature) req.options.temperature = opts.temperature;
  if (opts.image) req.images = [opts.image];
  return req;
}

export async function ollamaGenerate(
  endpoint: string,
  request: OllamaGenerateRequest,
): Promise<{ response: string; totalDuration: number; evalCount: number }> {
  const res = await fetch(`${endpoint}/api/generate`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(request),
  });
  if (!res.ok) throw new Error(`Ollama error: ${res.status} ${res.statusText}`);
  const data = (await res.json()) as { response: string; total_duration: number; eval_count: number };
  return { response: data.response, totalDuration: data.total_duration, evalCount: data.eval_count };
}
```

**Step 4: Run test to verify it passes**

Run: `cd packages/cli && pnpm test -- --run tests/ai/ollama.test.ts`
Expected: PASS

**Step 5: Commit**

```bash
git add packages/cli/src/ai/ollama.ts packages/cli/tests/ai/ollama.test.ts
git commit -m "feat(cli): add Ollama detection, model listing, and inference proxy"
```

---

### Task 5: CLI `ai` Commands

**Files:**
- Create: `packages/cli/src/commands/ai.ts`
- Modify: `packages/cli/src/commands/index.ts` — add `registerAI(program)` import and call

**Step 1: Implement the CLI commands**

`packages/cli/src/commands/ai.ts`:
```ts
import type { Command } from "commander";

export function registerAI(program: Command): void {
  const ai = program.command("ai").description("Local AI model management and inference");

  ai.command("list")
    .description("List approved models, download status, and Ollama models if available")
    .action(async () => {
      // 1. Show native approved models with download status
      // 2. Probe Ollama at localhost:11434 — if reachable, list its models below a separator
      // 3. If Ollama not running, silently skip (no error)
    });

  ai.command("pull <model>")
    .description("Download a model from HuggingFace")
    .action(async (model: string) => { /* ... */ });

  ai.command("rm <model>")
    .description("Delete a downloaded model")
    .action(async (model: string) => { /* ... */ });

  ai.command("status")
    .description("Check inference status on a device")
    .option("-d, --device <device>", "Target device")
    .action(async (opts) => { /* ... */ });

  ai.command("load <model>")
    .description("Load a model on a device")
    .option("-d, --device <device>", "Target device")
    .action(async (model: string, opts) => { /* ... */ });

  ai.command("unload")
    .description("Unload model from a device")
    .option("-d, --device <device>", "Target device")
    .action(async (opts) => { /* ... */ });

  ai.command("ask <prompt>")
    .description("Run inference on the device's loaded model")
    .option("-d, --device <device>", "Target device")
    .option("-c, --context <mode>", "Context mode: page_text, screenshot, dom, accessibility")
    .option("--max-tokens <n>", "Max tokens", "512")
    .option("--temperature <t>", "Temperature", "0.7")
    .action(async (prompt: string, opts) => { /* ... */ });
}
```

**Step 2: Register in index.ts**

Add `import { registerAI } from "./ai.js";` and `registerAI(program);` in the AI section.

**Step 3: Build and verify**

Run: `cd packages/cli && pnpm build`
Expected: Compiles without errors

**Step 4: Commit**

```bash
git add packages/cli/src/commands/ai.ts packages/cli/src/commands/index.ts
git commit -m "feat(cli): add ai subcommands for model management and inference"
```

---

### Task 6: MCP Tool Definitions

**Files:**
- Modify: `packages/cli/src/mcp/tools.ts` — add AI browser tools and CLI tools
- Modify: `packages/shared/src/mcp-tools.ts` — add tool names to registries

**Step 1: Add browser tool definitions to `tools.ts`**

Add to the `browserTools` array:

```ts
// AI / Local Inference
{ name: "kelpie_ai_status", description: "Get the local inference engine status — whether a model is loaded, which model, its capabilities, and memory usage", method: "aiStatus", schema: { device }, bodyFromArgs: passthrough },
{ name: "kelpie_ai_load", description: "Load a model on a device for local inference. Pass a model ID (resolved to local path) or an ollama: prefixed ID. The model must be downloaded first (use kelpie_ai_pull). Only one model at a time — auto-unloads the current model.", method: "aiLoad", schema: { device, model: z.string().describe("Model ID (e.g. 'gemma-4-e2b-q4') or Ollama model (e.g. 'ollama:llava:7b')") }, bodyFromArgs: passthrough },
{ name: "kelpie_ai_unload", description: "Unload the current model from a device, freeing memory", method: "aiUnload", schema: { device }, bodyFromArgs: passthrough },
{ name: "kelpie_ai_ask", description: "Ask the locally-loaded model a question about the current page. Use 'context' to auto-gather page data (page_text, screenshot, dom, accessibility) or provide 'text' directly. Returns the model's response. This runs entirely on-device — no data is sent to the cloud.", method: "aiInfer", schema: { device, prompt: z.string().optional().describe("Question or instruction for the model (omit if sending audio)"), audio: z.string().optional().describe("Base64-encoded WAV audio (16kHz mono, max 30s) — requires audio-capable model"), context: z.enum(["page_text", "screenshot", "dom", "accessibility"]).optional().describe("Auto-gather page context before prompting"), text: z.string().optional().describe("Raw text input (alternative to context)"), maxTokens: z.number().optional().describe("Maximum tokens to generate (default 512)"), temperature: z.number().optional().describe("Sampling temperature (default 0.7)") }, bodyFromArgs: passthrough },
```

**Step 2: Add CLI tool definitions**

Add to the `cliTools` array:

```ts
// AI Model Management
{ name: "kelpie_ai_models", description: "List all approved models and their download status", method: "aiModels", kind: "discovery", schema: {}, bodyFromArgs: filterBody },
{ name: "kelpie_ai_pull", description: "Download a model from HuggingFace to the local model store. Accepts a model ID from the approved list or a HuggingFace repo path.", method: "aiPull", kind: "discovery", schema: { model: z.string().describe("Model ID or HuggingFace repo path (e.g. 'gemma-4-e2b-q4' or 'owner/repo/file.gguf')") }, bodyFromArgs: filterBody },
{ name: "kelpie_ai_remove", description: "Delete a downloaded model from the local store", method: "aiRemove", kind: "discovery", schema: { model: z.string().describe("Model ID to remove") }, bodyFromArgs: filterBody },
```

**Step 3: Update `packages/shared/src/mcp-tools.ts`**

Add to `BrowserMcpTools`:
```ts
"kelpie_ai_status",
"kelpie_ai_load",
"kelpie_ai_unload",
"kelpie_ai_ask",
"kelpie_ai_record",
```

Add to `CliMcpTools`:
```ts
"kelpie_ai_models",
"kelpie_ai_pull",
"kelpie_ai_remove",
```

Add to `httpToMcp`:
```ts
"ai-status": "kelpie_ai_status",
"ai-load": "kelpie_ai_load",
"ai-unload": "kelpie_ai_unload",
"ai-infer": "kelpie_ai_ask",
"ai-record": "kelpie_ai_record",
```

Add to `BrowserToolUnsupportedPlatforms`:
```ts
kelpie_ai_status: ["linux", "windows"],
kelpie_ai_load: ["linux", "windows"],
kelpie_ai_unload: ["linux", "windows"],
kelpie_ai_ask: ["linux", "windows"],
kelpie_ai_record: ["linux", "windows"],
```

Update shared tests (`packages/shared/tests/index.test.ts`) to account for the new tool count and error codes.

**Step 4: Add AI CLI tool handlers in `server.ts`**

The AI CLI tools (`kelpie_ai_models`, `kelpie_ai_pull`, `kelpie_ai_remove`) are `discovery` kind but need custom handling in `handleDiscovery()` — they don't scan for devices, they manage local model state. Add a new handler branch:

```ts
if (method === "aiModels") {
  const store = getModelStore();
  const approved = getApprovedModels();
  const downloaded = store.listDownloaded();
  // Also probe Ollama if reachable
  const ollamaModels = await listOllamaModels().catch(() => []);
  return { content: [{ type: "text", text: JSON.stringify({ success: true, approved, downloaded, ollama: ollamaModels }) }] };
}

if (method === "aiPull") {
  const { model } = args;
  const store = getModelStore();
  // Resolve model ID → HuggingFace URL, download to store, verify sha256
  // Return { success: true, id, path } on completion
}

if (method === "aiRemove") {
  const { model } = args;
  const store = getModelStore();
  store.remove(model);
  return { content: [{ type: "text", text: JSON.stringify({ success: true, removed: model }) }] };
}
```

Note: `listDownloaded()` must return the absolute file path for each downloaded model so that MCP callers can pass the model ID to `kelpie_ai_load` (which resolves it to a path internally).

**Step 5: Build and test**

Run: `cd packages/cli && pnpm build && pnpm test`
Expected: All pass

**Step 6: Commit**

```bash
git add packages/cli/src/mcp/tools.ts packages/shared/src/mcp-tools.ts packages/cli/src/mcp/server.ts
git commit -m "feat(mcp): add AI inference and model management tools"
```

---

### Task 7: macOS — llama.cpp Swift Package Integration

**Files:**
- Modify: `apps/macos/Kelpie.xcodeproj/project.pbxproj` — add llama.cpp SPM dependency
- Create: `apps/macos/Kelpie/AI/InferenceEngine.swift`

**Step 1: Add llama.cpp Swift Package**

Add the `ggerganov/llama.cpp` Swift package to the Xcode project via SPM. The package URL is `https://github.com/ggerganov/llama.cpp.git`. Pin to a stable release tag.

**Step 2: Implement InferenceEngine**

`apps/macos/Kelpie/AI/InferenceEngine.swift`:

```swift
import Foundation
import llama

/// Process-level singleton. Runs inference on a background thread to avoid blocking UI.
/// Published properties are updated on @MainActor for SwiftUI binding.
final class InferenceEngine: ObservableObject, @unchecked Sendable {
    static let shared = InferenceEngine()

    @MainActor @Published private(set) var isLoaded = false
    @MainActor @Published private(set) var modelName: String?
    @MainActor @Published private(set) var capabilities: [String] = []

    private let queue = DispatchQueue(label: "com.kelpie.inference", qos: .userInitiated)
    private var model: OpaquePointer?  // llama_model
    private var ctx: OpaquePointer?    // llama_context

    struct InferenceResult {
        let text: String
        let tokensUsed: Int
        let inferenceTimeMs: Int
    }

    func load(path: String, name: String, capabilities: [String]) async throws {
        // Run llama_model_load on background queue — heavy I/O
        // Update @MainActor published properties after success
    }

    func unload() async {
        // llama_free, llama_model_free on background queue
        // Clear @MainActor published state
    }

    func infer(prompt: String, audio: Data? = nil, image: Data? = nil,
               maxTokens: Int = 512, temperature: Float = 0.7) async throws -> InferenceResult {
        // Run tokenize + sample + decode on background queue
        // Never blocks main thread — UI stays responsive during inference
    }

    var memoryUsageMB: Int {
        // Report approximate memory used by model + context
    }

    enum InferenceError: Error {
        case noModelLoaded
        case alreadyLoaded(current: String)
        case loadFailed(String)
        case inferenceFailed(String)
        case visionNotSupported
        case audioNotSupported
    }
}
```

**Step 3: Build and verify**

Build the macOS app in Xcode. Verify llama.cpp compiles and links.

**Step 4: Commit**

```bash
git add apps/macos/
git commit -m "feat(macos): integrate llama.cpp Swift package and InferenceEngine"
```

---

### Task 8: macOS — Inference Harness & System Prompt

**Files:**
- Create: `apps/macos/Kelpie/AI/InferenceHarness.swift`
- Create: `apps/macos/Kelpie/AI/SystemPrompt.swift`
- Create: `apps/macos/Kelpie/AI/PageSummary.swift`

**Step 1: Implement the system prompt**

`apps/macos/Kelpie/AI/SystemPrompt.swift`:

```swift
enum SystemPrompt {
    /// The fixed system prompt prepended to every inference call.
    /// {tools_block} is replaced at runtime with the available tool descriptions.
    static let template = """
    You are a browser assistant built into Kelpie. You answer questions about the web page currently loaded in the browser.

    Rules:
    - Be concise. One to three sentences unless the user asks for detail.
    - Only answer questions you can answer from the page data provided. If you cannot answer, say so in one sentence.
    - Do not make up information. Do not guess URLs, prices, or facts not present in the data.
    - Do not engage in general conversation, tell jokes, discuss weather, or answer questions unrelated to the current page.
    - If you need more data about the page, use a tool call.
    - When referencing page elements, include the CSS selector when available.
    - When reporting errors, include the exact error message.

    You have access to these tools:
    {tools_block}

    Respond with EITHER a tool call OR a final answer, never both.
    Tool call: {"tool": "tool_name", "args": {"key": "value"}}
    Final answer: {"answer": "your response", "references": [...]}
    """

    /// Compact tool descriptions injected into {tools_block}.
    static let toolDescriptions = """
    get_text - Get readable page text (title, content, word count)
    get_screenshot - Take a viewport screenshot
    get_dom(selector?) - Get HTML of an element (default: body, max 2000 chars)
    get_element(selector) - Get text and attributes of a CSS selector
    find_element(text) - Find elements by text content
    get_forms - Get form field names, types, and values
    get_errors - Get JavaScript errors
    get_console - Get recent console messages (last 20)
    get_network - Get recent network requests (last 20)
    get_cookies - Get cookies for current page
    get_storage - Get localStorage keys and values
    get_links - Get all links on the page
    get_visible - Get visible interactive elements
    get_a11y - Get accessibility tree (depth 3)
    """

    static func build() -> String {
        template.replacingOccurrences(of: "{tools_block}", with: toolDescriptions)
    }
}
```

**Step 2: Implement PageSummary**

`apps/macos/Kelpie/AI/PageSummary.swift`:

```swift
/// Gathers a lightweight page summary (~100 tokens) for the harness.
struct PageSummary {
    let title: String
    let url: String
    let wordCount: Int
    let formCount: Int
    let errorCount: Int
    let consoleCount: Int
    let networkRequestCount: Int
    let linkCount: Int
    let interactiveElementCount: Int

    func formatted() -> String {
        """
        Page: "\(title)"
        URL: \(url)
        Words: \(wordCount)
        Forms: \(formCount)
        JS Errors: \(errorCount)
        Console: \(consoleCount) messages
        Network: \(networkRequestCount) requests
        Links: \(linkCount)
        Interactive elements: \(interactiveElementCount)
        """
    }

    /// Gather from the current page via HandlerContext JS evaluation.
    @MainActor
    static func gather(from context: HandlerContext) async -> PageSummary {
        // Runs lightweight JS queries to collect counts, not content
    }
}
```

**Step 3: Implement InferenceHarness**

`apps/macos/Kelpie/AI/InferenceHarness.swift`:

The harness orchestrates the agent loop:
1. Build prompt: system prompt + page summary + user question
2. Run inference
3. If tool call → execute tool, append result, re-run (max 3 rounds)
4. If final answer → parse and return

```swift
/// Instantiated per-request with the requesting window's HandlerContext.
/// NOT a singleton — each HTTP request or chat message creates a fresh harness
/// bound to the correct window's page state.
struct InferenceHarness {
    private let engine = InferenceEngine.shared
    private let context: HandlerContext  // The window that received this request
    private let maxRounds = 3
    private let toolTokenBudget = 1500

    struct Result {
        let answer: String
        let references: [Reference]
        let toolCallsMade: Int
        let totalTokens: Int
        let totalTimeMs: Int
        let transcription: String?  // If audio input was used
    }

    struct Reference {
        let type: String       // "element", "error", "console", "network"
        let selector: String?
        let message: String?
        let description: String?
    }

    func run(prompt: String, audio: Data? = nil, preloadedContext: String? = nil) async throws -> Result {
        // 1. If preloadedContext is set, single-shot (no agent loop)
        // 2. Otherwise: gather page summary, run agent loop
    }

    private func executeTool(_ name: String, args: [String: String]) async -> String {
        // Dispatch to handler context, truncate result to toolTokenBudget
    }

    private func truncate(_ text: String, maxTokens: Int) -> String {
        // Approximate: 1 token ≈ 4 chars. Truncate with suffix.
    }
}
```

**Step 4: Build and verify**

Build macOS app, verify harness compiles.

**Step 5: Commit**

```bash
git add apps/macos/Kelpie/AI/
git commit -m "feat(macos): add inference harness with agent loop, system prompt, and page summary"
```

---

### Task 9: macOS — AIHandler HTTP Endpoints

**Files:**
- Create: `apps/macos/Kelpie/Handlers/AIHandler.swift`
- Modify: `apps/macos/Kelpie/Network/ServerState.swift` — register AI handlers

**Step 1: Implement AIHandler**

`apps/macos/Kelpie/Handlers/AIHandler.swift`:

```swift
import Foundation

struct AIHandler {
    static func register(on state: ServerState) {
        state.router.register("ai-status") { _ in
            // Return loaded state, model name, capabilities, memory
        }

        state.router.register("ai-load") { body in
            // If body has "path": load native GGUF via inferenceEngine.load()
            // If body has "ollama": set backend to ollama, store model name + endpoint
            //   Optionally verify Ollama is reachable before confirming
            // Return success or error
        }

        state.router.register("ai-unload") { _ in
            // Call inferenceEngine.unload()
        }

        state.router.register("ai-infer") { body in
            // Extract prompt, context mode, maxTokens, temperature
            // If context == "page_text": gather page text via existing handler
            // If context == "screenshot": take screenshot, encode as base64
            // Check backend mode:
            //   "native" → run llama.cpp inference
            //   "ollama" → forward to Ollama API endpoint
            // Return result in standard format
        }
    }
}
```

The `ai-infer` handler with `context` modes should reuse existing handler logic:
- `page_text`: call the same JS that `getPageText` uses, prepend to prompt
- `screenshot`: call `HandlerContext.takeSnapshot()`, pass image bytes to model
- `dom`: call the same JS that `getDOM` uses, prepend to prompt
- `accessibility`: call the same JS that `getAccessibilityTree` uses, prepend to prompt

**Step 2: Register in ServerState**

In `ServerState.registerHandlers()`, add `AIHandler.register(on: self)`.

**Step 3: Build and verify**

Build macOS app, verify new endpoints appear when calling `GET /health` or testing via curl.

**Step 4: Commit**

```bash
git add apps/macos/Kelpie/Handlers/AIHandler.swift apps/macos/Kelpie/Network/ServerState.swift
git commit -m "feat(macos): add AI HTTP endpoints for model loading and inference"
```

---

### Task 10: macOS — Apple Silicon Detection Gate

**Files:**
- Create: `apps/macos/Kelpie/AI/AIState.swift`
- Modify: `apps/macos/Kelpie/KelpieApp.swift` — check at startup

**Step 1: Implement AIState**

`apps/macos/Kelpie/AI/AIState.swift`:

```swift
import Foundation

/// Global AI availability state. Checked once at startup, never changes.
final class AIState: ObservableObject {
    static let shared = AIState()

    /// True on Apple Silicon (native + Ollama) or Intel with Ollama detected.
    /// All AI UI is hidden when false.
    @Published private(set) var isAvailable: Bool = false
    let isAppleSilicon: Bool

    private init() {
        var result: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let err = sysctlbyname("hw.optional.arm64", &result, &size, nil, 0)
        isAppleSilicon = (err == 0 && result == 1)
        // On Apple Silicon: always available (native + Ollama)
        // On Intel: available only if Ollama is detected (checked async at startup)
        isAvailable = isAppleSilicon
    }

    /// Called at startup after Ollama detection completes.
    func enableOllamaOnly() {
        if !isAppleSilicon { isAvailable = true }
    }
}
```

**Step 2: Gate all AI UI on `AIState.shared.isAvailable`**

- Brain pill in URLBarView: hidden when `!AIState.shared.isAvailable`
- AI section in SettingsView: hidden
- AI brain button in FloatingMenuView: hidden
- AI chat panel: cannot open

**Step 3: Build and verify on Intel (if available) or verify the sysctl check**

Run: Build macOS app, verify brain pill appears on Apple Silicon.

**Step 4: Commit**

```bash
git add apps/macos/Kelpie/AI/AIState.swift apps/macos/Kelpie/KelpieApp.swift
git commit -m "feat(macos): gate AI features behind Apple Silicon detection"
```

---

### Task 11: macOS — Audio Recording & ai-record Endpoint

**Files:**
- Create: `apps/macos/Kelpie/AI/AudioRecorder.swift`
- Modify: `apps/macos/Kelpie/Handlers/AIHandler.swift` — add ai-record handler

**Step 1: Implement AudioRecorder**

`apps/macos/Kelpie/AI/AudioRecorder.swift`:

```swift
import AVFoundation

/// Records microphone audio as 16-bit PCM WAV, 16kHz mono.
/// Max 30 seconds, auto-stops. Output: Data containing WAV bytes.
final class AudioRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsedMs: Int = 0

    private var engine: AVAudioEngine?
    private var buffer = Data()
    private let maxDuration: TimeInterval = 30
    private var timer: Timer?

    func start() throws {
        // Request mic permission, configure AVAudioEngine
        // Tap input node at 16kHz mono
        // Auto-stop after maxDuration
    }

    func stop() -> Data {
        // Stop engine, prepend WAV header to buffer, return
    }
}
```

**Step 2: Add ai-record handler**

In `AIHandler.swift`, register `ai-record`:
```swift
state.router.register("ai-record") { body in
    let action = body["action"] as? String ?? "status"
    switch action {
    case "start":
        try recorder.start()
        return ["success": true, "recording": true]
    case "stop":
        let audio = recorder.stop()
        return ["success": true, "audio": audio.base64EncodedString(), "durationMs": recorder.elapsedMs]
    case "status":
        return ["success": true, "recording": recorder.isRecording, "elapsedMs": recorder.elapsedMs]
    default:
        return ["success": false, "error": "Unknown action"]
    }
}
```

**Step 3: Build and verify**

Build macOS app, verify `ai-record` endpoint responds.

**Step 4: Commit**

```bash
git add apps/macos/Kelpie/AI/AudioRecorder.swift apps/macos/Kelpie/Handlers/AIHandler.swift
git commit -m "feat(macos): add audio recorder and ai-record HTTP endpoint"
```

---

### Task 12: iOS — Platform AI Handler

**Files:**
- Create: `apps/ios/Kelpie/AI/AIState.swift`
- Create: `apps/ios/Kelpie/AI/PlatformAIEngine.swift`
- Create: `apps/ios/Kelpie/Handlers/AIHandler.swift`
- Modify: `apps/ios/Kelpie/Network/Router.swift` — register AI routes

**Step 1: Implement PlatformAIEngine**

```swift
import Foundation
import FoundationModels

/// Wraps Apple Intelligence for text-only inference.
/// Available on iPhone 15 Pro+ / iPad M-series.
struct PlatformAIEngine {
    static var isAvailable: Bool {
        if #available(iOS 26, *) {
            return SystemLanguageModel.isAvailable
        }
        return false
    }

    func infer(prompt: String) async throws -> String {
        guard #available(iOS 26, *) else { throw AIError.platformUnavailable }
        let model = SystemLanguageModel.default
        let response = try await model.generateResponse(to: prompt)
        return response.content
    }
}
```

**Step 2: Implement AIHandler for iOS**

Same HTTP endpoints as macOS (`ai-status`, `ai-load`, `ai-unload`, `ai-infer`), but:
- `backend` defaults to `"platform"` when no Ollama is configured
- `ai-infer` routes to `PlatformAIEngine` for platform backend
- `ai-infer` routes to Ollama proxy for ollama backend
- No native GGUF support (Phase 2)

**Step 3: AIState — always-available on supported devices**

```swift
final class AIState: ObservableObject {
    static let shared = AIState()
    let isAvailable: Bool

    private init() {
        isAvailable = PlatformAIEngine.isAvailable
    }
}
```

**Step 4: Build and verify**

Build iOS app, verify AI endpoints respond with platform backend.

**Step 5: Commit**

```bash
git add apps/ios/Kelpie/AI/ apps/ios/Kelpie/Handlers/AIHandler.swift apps/ios/Kelpie/Network/Router.swift
git commit -m "feat(ios): add platform AI (Apple Intelligence) as default backend"
```

#### Cross-Provider Review

- Reviewer: Gemini CLI adversarial review on 2026-04-02.
- Adopted:
  - Keep backend transitions explicit on iOS. If Ollama is configured but unavailable, `ai-infer` fails with an Ollama error instead of silently falling back to platform AI mid-request.
  - Persist iOS backend state so `ai-status`, `ai-load`, and `ai-unload` stay coherent across launches.
  - Report iOS platform AI as text-only in `ai-status`.
- Rejected for Task 12:
  - Replacing the `iOS 26` availability proxy now. The task is explicitly stubbed until the Foundation Models SDK is available in-tree, so the version check remains a temporary placeholder.
  - Pulling the full macOS inference harness into iOS. Task 12 is only backend selection and transport plumbing.

---

### Task 13: Android — Platform AI Handler

**Files:**
- Create: `apps/android/app/src/main/java/com/kelpie/browser/ai/AIState.kt`
- Create: `apps/android/app/src/main/java/com/kelpie/browser/ai/PlatformAIEngine.kt`
- Create: `apps/android/app/src/main/java/com/kelpie/browser/ai/AIHandler.kt`
- Modify: `apps/android/app/src/main/java/com/kelpie/browser/network/Router.kt` — register AI routes

**Step 1: Add AI Edge SDK dependency**

In `apps/android/app/build.gradle.kts`:
```kotlin
implementation("com.google.ai.edge:generative-ai:0.x.x")
```

**Step 2: Implement PlatformAIEngine**

```kotlin
class PlatformAIEngine(private val context: Context) {
    companion object {
        fun isAvailable(context: Context): Boolean {
            // Check if Gemini Nano is available via GenerativeModel.isAvailable()
        }
    }

    suspend fun infer(prompt: String): String {
        val model = GenerativeModel("gemini-nano")
        val response = model.generateContent(prompt)
        return response.text ?: ""
    }
}
```

**Step 3: Implement AIHandler**

Same HTTP endpoints as iOS, same backend priority (platform default, Ollama optional).

**Step 4: Build and verify**

Build Android app, verify AI endpoints respond.

**Step 5: Commit**

```bash
git add apps/android/
git commit -m "feat(android): add platform AI (Gemini Nano) as default backend"
```

---

### Task 14: Integration Testing — End-to-End

**Files:**
- Create: `packages/cli/tests/ai/integration.test.ts`

**Step 1: Write integration tests**

Test the full CLI flow:
1. `kelpie ai list` — shows approved models, none downloaded
2. Model store operations — register, remove (unit-level but with real filesystem)
3. MCP tool schemas — verify all AI tools are registered with correct schemas

```ts
import { describe, it, expect } from "vitest";
import { getApprovedModels, findModel } from "../../src/ai/models.js";
import { buildDownloadUrl } from "../../src/ai/download.js";

describe("AI integration", () => {
  it("all approved models have valid HuggingFace URLs", () => {
    for (const model of getApprovedModels()) {
      const url = buildDownloadUrl(model.huggingFaceRepo, model.huggingFaceFile);
      expect(url).toMatch(/^https:\/\/huggingface\.co\//);
      expect(url).toMatch(/\.gguf$/);
    }
  });

  it("all approved models have required fields", () => {
    for (const model of getApprovedModels()) {
      expect(model.id).toBeTruthy();
      expect(model.capabilities.length).toBeGreaterThan(0);
      expect(model.platforms.length).toBeGreaterThan(0);
      expect(model.minRamGB).toBeGreaterThan(0);
    }
  });
});
```

**Step 2: Run tests**

Run: `cd packages/cli && pnpm build && pnpm test`
Expected: All pass

**Step 3: Commit**

```bash
git add packages/cli/tests/ai/integration.test.ts
git commit -m "test(cli): add AI model registry integration tests"
```

---

### Task 15: Documentation

**Files:**
- Modify: `docs/api/README.md` — add AI section link
- Create: `docs/api/ai.md` — full AI API reference
- Modify: `docs/cli.md` — add `ai` subcommands
- Modify: `docs/functionality.md` — add local inference feature

**Step 1: Write `docs/api/ai.md`**

Document all five HTTP endpoints (`ai-load`, `ai-unload`, `ai-status`, `ai-infer`, `ai-record`) with request/response examples. Document the three backends: native (macOS), ollama (all platforms), platform (iOS/Android).

**Step 2: Update CLI docs**

Add the `ai` subcommand group to `docs/cli.md`.

**Step 3: Update functionality docs**

Add "Local AI Inference" feature to `docs/functionality.md`.

**Step 4: Commit**

```bash
git add docs/
git commit -m "docs: add local inference API reference, CLI commands, and feature description"
```

---

## Mobile — Platform AI as Default (Phase 1)

**Mobile always has AI.** On iOS and Android, platform intelligence (Apple Intelligence / Gemini Nano) is the default backend. No download, no configuration, no Ollama — the brain pill works out of the box on supported hardware. Capabilities: `["text"]` only — no vision, no audio input processing.

### Platform AI Backend

**iOS — Apple Intelligence:**
- Uses Foundation Models framework (`FoundationModels.SystemLanguageModel`)
- Available on iPhone 15 Pro+ / iPad with M-series (devices with Apple Intelligence enabled)
- On older iPhones without Apple Intelligence, AI is hidden unless Ollama is configured
- No download — managed by the OS, runs on the Neural Engine
- `ai-infer` routes to `SystemLanguageModel.default.generateResponse()` when `backend == "platform"`

**Android — Gemini Nano:**
- Uses Google AI Edge SDK (`com.google.ai.edge:generative-ai`)
- Available on Pixel 8+ and Samsung Galaxy S24+ (devices with on-device Gemini)
- On unsupported devices, AI is hidden unless Ollama is configured
- No download — pre-installed or silently managed by Google Play Services
- `ai-infer` routes to `GenerativeModel.generateContent()` when `backend == "platform"`

**Backend priority on mobile:**
1. If an Ollama backend is configured and reachable → use Ollama proxy
2. **Otherwise → use platform AI (always available on supported hardware)**

The `ai-config.json` on mobile defaults to `backend: "platform"`. Configuring Ollama changes it to `"ollama"`. If Ollama becomes unreachable, the app falls back to platform AI silently.

### Mobile Ollama Proxy

Mobile devices can also use a remote Ollama instance over the local network. This adds vision capability and access to larger models, but requires configuration.

**Settings UI (both iOS and Android):**
- "Ollama Endpoint" text field — user enters `http://192.168.1.50:11434` (their Mac's LAN IP)
- "Test Connection" button — calls `/api/tags`, shows green/red indicator
- "Model" picker — populated from the Ollama `/api/tags` response after successful connection
- Saved to UserDefaults (iOS) / SharedPreferences (Android)

**Implementation:**
- `ai-load` with an `ollama:` prefixed model stores the endpoint + model name
- `ai-infer` gathers context locally (page text, DOM — these already work), then sends the prompt + data to the remote Ollama endpoint
- Same HTTP API surface as macOS, so CLI and MCP tools work identically

### On-Device GGUF (Future — Phase 2)

On-device GGUF model loading via llama.cpp is deferred:

**iOS:**
- Ship curated model list, download to `Documents/models/`
- Use llama.cpp compiled as C library via SPM (same package, iOS target)
- Settings screen shows downloaded models and loaded status

**Android:**
- Ship curated model list, download via DownloadManager
- Use llama.cpp via JNI (android.llm or llama.android bindings)

### Platform Parity Note

The HTTP API surface is identical across all backends — native, Ollama, platform — so CLI/MCP tools work without knowing which backend is active. Mobile ships with platform AI on day one. On-device GGUF models are a future upgrade path.

**macOS does NOT use platform AI.** Apple Intelligence lacks the Foundation Models API on macOS. The macOS app uses native llama.cpp or Ollama only.
