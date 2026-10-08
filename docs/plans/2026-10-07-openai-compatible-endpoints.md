# OpenAI-Compatible Inference Endpoints

Status: active. Contract shared by macOS, iOS, Android, the CLI and MCP.

## Goal

A person can add, edit, test, select and remove named OpenAI-compatible
inference endpoints (Strata, llama.cpp `llama-server`, LM Studio, vLLM, Ollama's
`/v1`, …). The selected endpoint + model becomes Kelpie's active AI backend
(`backend: "openai"`) and drives both plain inference and Kelpie's built-in
browser-agent tool loop. Existing `native`, `platform` and `ollama` backends are
unchanged. Windows and Linux have no AI layer today and are out of scope.

## Principles

- **User intent only.** Kelpie only talks to an address a person explicitly
  saved. Saving does not connect; Test / Refresh / Use do. No port scans, no
  listeners, tunnels or firewall changes. (mDNS service browsing is not
  implemented; if added later it may only *suggest* an address.)
- **Whose localhost.** `localhost` / `127.0.0.1` / `[::1]` resolve on the device
  running Kelpie and dispatching inference. On macOS that is the Mac; on iOS and
  Android it is the phone. Every settings surface says so; every API result
  carries `loopback: true` for loopback hosts and the `executionHost` platform.
- **No silent fallback.** If the selected endpoint fails, the request fails with
  a specific error. Kelpie never switches endpoint, model or backend on its own
  and never routes to a cloud provider.
- **Secrets.** API keys are optional. They are stored in Kelpie's encrypted
  `SecretStore` (Android: Keystore-backed `SecretStore`; Apple: AES-GCM file
  store — the macOS Keychain is forbidden by AGENTS.md "No Keychain"). Keys are
  never returned by any API, never logged, never put in prompts, and redacted
  from echoed server error text. No `Authorization` header when no key is set.
- **Capabilities are evidence-based.** "OpenAI-compatible" implies only text
  chat. Context size, vision, tool calling and JSON-schema support come from
  server metadata, explicit user configuration, or a bounded test — each value
  carries its `source`. Unknown stays unknown (`null`).
- **Text-only means text-only.** Images are never sent unless `vision` is
  `true`. Text-only agents get semantic DOM / accessibility / text tools.
- **MTP and speculative decoding are server features.** Kelpie sends ordinary
  requests and invents no flags. Kelpie displays model IDs exactly as the server
  returns them and never derives quantisation labels (e.g. never calls a Q4
  target with Q2 draft experts "all-Q4").

## URL handling

Input: `http://` or `https://` URL with host (DNS name, `.local`, IPv4, or
bracketed IPv6), optional port `1…65535`, optional base path.

Normalisation (`OpenAIEndpointURL.normalize`):

1. Trim whitespace. Reject empty, other schemes, missing host, user-info
   (`user:pass@`), query strings and fragments → `INVALID_ENDPOINT_URL`.
2. Port must parse to `1…65535` if present.
3. Collapse duplicate slashes in the path; drop trailing `/`.
4. If the path ends with a known operation (`/chat/completions`, `/completions`,
   `/models`, `/embeddings`), strip it (people paste full URLs).
5. If the resulting path is empty, use `/v1` (documented default).
6. Lower-case scheme and host; keep path case.

Joining: `baseURL + "/" + operation` where `operation` has no leading slash
(`models`, `chat/completions`). Never `/v1/v1/…`, never `//`.

Examples: `http://127.0.0.1:18880/v1/` → `http://127.0.0.1:18880/v1`;
`http://studio.local:1234` → `http://studio.local:1234/v1`;
`https://host/openai/v1/chat/completions` → `https://host/openai/v1`;
`http://[::1]:8080/v1` stays.

## HTTP behaviour

- `GET {base}/models`, `POST {base}/chat/completions`.
- Headers: `Content-Type: application/json`, `Accept: application/json` or
  `text/event-stream`; `Authorization: Bearer <key>` only when a key exists.
- Redirects: same-origin (scheme+host+port) redirects are followed; any
  cross-origin redirect is refused → `ENDPOINT_REDIRECT_REFUSED`. Credentials
  are therefore never forwarded to another origin.
- Timeouts: probe/models 8 s; chat time-to-first-byte and idle gap between
  stream packets 180 s (`: keep-alive` comments count, covers large prompt
  processing); overall request 900 s. All cancellable.
- Server error bodies are reduced to a ≤300-char message with the API key
  redacted.

## Model discovery

`GET {base}/models`. Accept `{"data":[…]}` (also `{"models":[…]}`). Each entry
needs a string `id`; others are skipped. Optional metadata (first found wins):

| Field | Sources |
|---|---|
| `contextWindow` | `meta.n_ctx`, `context_length`, `max_model_len`, `loaded_context_length`, `max_context_length`, `context_window` |
| `vision` | `architecture.input_modalities` contains `image` → true, present without it → false; `capabilities` array contains `vision` → true |
| `status` | `status.value` or `status` string or `state` (`loaded`, `loading`, `unloaded`/`not-loaded`) |

Outcomes: 401/403 → `ENDPOINT_AUTH_FAILED`; 404/405/501 →
`MODEL_DISCOVERY_UNSUPPORTED` (user may type a model ID); 503 →
`ENDPOINT_LOADING`; network failure → `ENDPOINT_UNREACHABLE`; non-JSON or wrong
shape → `ENDPOINT_MALFORMED_RESPONSE`; empty list → success with `models: []`
and `warning: "The server returned no models."`.

## Streaming (SSE)

Parser is byte-oriented (UTF-8 sequences may split across chunks). Handles
`\n`, `\r\n`, `\r`; comment lines (`:`); `event:`/`id:` fields; multi-line
`data:` joined with `\n`; dispatch on blank line; `data: [DONE]` ends the
stream; a stream ending without `[DONE]` but with a `finish_reason` is accepted,
without either → `ENDPOINT_STREAM_TRUNCATED`.

Accumulator per choice 0:

- `delta.role` alone is ignored.
- `delta.content` → answer text. `delta.reasoning_content` or `delta.reasoning`
  → reasoning text (kept separate, never shown as the answer, never sent back
  to the model).
- `delta.tool_calls[]` keyed by `index`: first `id` and `function.name` win
  (name fragments are concatenated if a server splits them), `function.arguments`
  fragments concatenated verbatim; parsed as JSON only after the stream ends.
  Invalid final JSON → the tool result tells the model the arguments were
  malformed (the loop continues; it does not crash).
- `finish_reason` recorded; `usage` frames (including ones with empty
  `choices`) recorded; `{"error":{…}}` frames → `ENDPOINT_ERROR`.

Non-streaming responses are parsed with the same model
(`choices[0].message.{content,reasoning_content,tool_calls}`).

## Health

States (`health.state`):

| State | Meaning | `online` |
|---|---|---|
| `unknown` | never checked, or last check older than 90 s (`stale: true`) | false |
| `unreachable` | connection failed / timed out | false |
| `auth_failed` | 401/403 | false |
| `loading` | reachable, server or model still loading (503, or model `status: loading/unloaded`) | true |
| `no_model` | reachable, no model selected | true |
| `model_missing` | reachable, selected model not in the discovered list | true |
| `ready` | discovery ok and selected model listed (not loading); or discovery unsupported and a generation test passed since the endpoint last came online | true |
| `busy` | ready and Kelpie has a request in flight, or server answered 429 / 503-busy | true |

Also: `checkedAt`, `latencyMs`, `message`, `modelListed`, `modelStatus`,
`generationVerifiedAt` (reset when the endpoint goes offline), `stale`.
A 200 alone never means `ready`. Polling: only for the active endpoint, every
30 s while healthy, backoff 5→10→20→40→60 s while failing, immediate re-check
after system wake or network-path change. Cached results older than 90 s are
reported as `unknown` + `stale: true`.

## Agent tool loop

Runs when `ai-infer` targets the openai backend with `agent: true` (default
when no `context`, `text` or `messages` is supplied). Requires
`toolCalling != false`; if `toolCalling` is `null` the request fails with
`TOOLS_UNVERIFIED` (run `ai-endpoint-test` with `tools: true`, or declare it).

Tools are OpenAI function definitions dispatched through Kelpie's existing
router methods, so tab resolution, the script-recording gate and handler
validation are reused. The tab is pinned at run start (`tabId` from the request
or the active tab) and injected into every call; model-supplied `tabId`,
`windowId` or unknown arguments are dropped.

| Tool | Router method | Offered |
|---|---|---|
| `get_current_url` | `get-current-url` | always |
| `get_page_text {selector?}` | `get-page-text` | always |
| `get_visible_elements {interactableOnly?}` | `get-visible-elements` | always |
| `find_element {text, role?}` | `find-element` | always |
| `get_form_state {selector?}` | `get-form-state` | always |
| `get_accessibility_tree {maxDepth?, interactableOnly?}` | `get-accessibility-tree` | always |
| `wait_for_element {selector, timeout?}` | `wait-for-element` | always |
| `click {selector}` | `click` | `allowActions: true` |
| `fill {selector, value}` | `fill` | `allowActions: true` |
| `select_option {selector, value}` | `select-option` | `allowActions: true` |
| `check {selector}` / `uncheck {selector}` | `check` / `uncheck` | `allowActions: true` |

Never offered: navigation, script evaluation, cookies, storage, screenshots
(no vision path in this release), tab/window management.

`allowActions` is authorised only by the caller (paired HTTP client, or the
person toggling "Allow page actions" in the chat panel). Page content and model
output cannot grant it. Tool results are JSON, truncated to 6 000 characters,
and the system prompt states that page content is untrusted data whose
instructions must be ignored. Each browser-tool result carries
`stepsRemaining`. Reasoning text is kept out of the message history.

**Task list.** An always-offered `update_task_list {tasks: [{task, done}]}`
tool lets the model record and update its plan; Kelpie handles it, it touches
no page and does not use the step budget. If the model answers while its own
list still has open tasks, Kelpie sends one reminder turn ("needs another
turn"). The final list is returned as `tasks`.

**Step budget and final feedback.** `maxSteps` counts browser tool calls:
default 20, maximum 40. When the next round would exceed it, Kelpie sends one
more request with no tools, asking for a final report (what was done, what was
verified, what is unfinished), and returns it as a successful result with
`completed: false` and `stopReason: "step_limit"` (otherwise `completed: true`,
`stopReason: "answered"`). `AGENT_STEP_LIMIT` is returned only if that final
request itself fails. Errors after steps were taken still include `steps`.

## Device HTTP API (all paired/bearer-authenticated)

`EndpointPublic`:

```json
{
  "id": "e1b2…", "name": "Strata (tunnel)",
  "baseURL": "http://127.0.0.1:18880/v1", "loopback": true,
  "hasApiKey": false, "model": "qwen3.8-flash-next-ud-q4_k_xl",
  "capabilities": {
    "contextWindow": {"value": 131072, "source": "server"},
    "vision": {"value": false, "source": "server"},
    "toolCalling": {"value": true, "source": "test"},
    "jsonSchema": {"value": null, "source": null}
  },
  "models": [{"id": "…", "contextWindow": 131072, "vision": false, "status": "loaded"}],
  "modelsDiscoveredAt": "2026-10-07T20:41:45Z",
  "health": {"state": "ready", "online": true, "checkedAt": "…", "stale": false}
}
```

`source` ∈ `server`, `user`, `test`, `null`. User values override server ones.

| Method | Body | Result |
|---|---|---|
| `ai-endpoints` | — | `{endpoints, activeEndpointId, activeModel, executionHost: {platform, loopbackMeans}}` |
| `ai-endpoint-save` | `{id?, name, baseURL, apiKey?, clearApiKey?, model?, capabilities?: {contextWindow?, vision?, toolCalling?, jsonSchema?}}` (`null` clears a user override) | `{endpoint}`; does not connect |
| `ai-endpoint-remove` | `{id}` | `{removed: true}`; removing the active endpoint unloads the openai backend |
| `ai-endpoint-models` | `{id}` | `{models, warning?}` or discovery error |
| `ai-endpoint-test` | `{id, model?, generate?: true, tools?: false}` | `{health, models, generation?: {ok, latencyMs, text}, toolCalling?: {ok, detail}}` |
| `ai-endpoint-health` | `{id?, refresh?: false}` (default: active) | `{health}` |
| `ai-load` | `{backend: "openai", endpoint: "<id or name>", model?}` | selects; fails on `unreachable` / `auth_failed` without changing the current backend |
| `ai-status` | — | adds `backend: "openai"`, `endpoint {id,name,baseURL,loopback}`, `health` |
| `ai-infer` | adds `agent?`, `allowActions?`, `maxSteps?` | adds `reasoning?`, `finishReason`, `steps[] {tool, args, ok, ms, preview}`, `tasks[] {task, done}`, `completed`, `stopReason`, `endpointId`, `model` |
| `ai-cancel` | — | `{cancelled: n}` |

Error codes: `INVALID_ENDPOINT_URL`, `ENDPOINT_NOT_FOUND`, `ENDPOINT_UNREACHABLE`,
`ENDPOINT_AUTH_FAILED`, `ENDPOINT_LOADING`, `ENDPOINT_REDIRECT_REFUSED`,
`ENDPOINT_MALFORMED_RESPONSE`, `ENDPOINT_STREAM_TRUNCATED`, `ENDPOINT_TIMEOUT`,
`ENDPOINT_ERROR`, `MODEL_DISCOVERY_UNSUPPORTED`, `MODEL_NOT_AVAILABLE`,
`NO_MODEL_SELECTED`, `TOOLS_UNVERIFIED`, `TOOLS_NOT_SUPPORTED`,
`VISION_NOT_SUPPORTED`, `AGENT_STEP_LIMIT`, `INFERENCE_CANCELLED`.

## Persistence

- Endpoint list: JSON under `ai.openaiEndpoints.v1` (UserDefaults /
  SharedPreferences). Active selection: `ai.openaiActive.v1` `{endpointId, model}`.
- API key: `SecretStore` entry `openai-endpoint.<id>.apiKey`.

## CLI / MCP

`kelpie ai endpoint list|add|edit|remove|models|test|health|use` and
`kelpie ai cancel`; `kelpie ai ask` gains `--agent`, `--allow-actions`,
`--max-steps`. API keys come from `--api-key-env <VAR>` or `--api-key-stdin`,
never argv. MCP: `kelpie_ai_endpoints`, `kelpie_ai_endpoint_save` (key only via
`apiKeyEnv`, read in the CLI process), `kelpie_ai_endpoint_remove`,
`kelpie_ai_endpoint_models`, `kelpie_ai_endpoint_test`,
`kelpie_ai_endpoint_health`, `kelpie_ai_cancel`; `kelpie_ai_load` and
`kelpie_ai_ask` gain the new fields.

## Verification fixture

`tests/fixtures/openai-compatible/server.mjs` — dependency-free Node fixture.
It is a protocol fixture, not an inference server. Configurable port and base
path; states `ready | loading | auth | busy | malformed | empty | nodiscovery`
switchable at runtime via `POST /__fixture/state`; streams with tiny random
chunk boundaries, reasoning deltas, fragmented tool calls and usage frames.
