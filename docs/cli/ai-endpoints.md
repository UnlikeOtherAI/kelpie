# AI Endpoints (OpenAI-compatible)

`kelpie ai endpoint` manages named OpenAI-compatible inference endpoints on a
Kelpie device: llama.cpp `llama-server`, LM Studio, vLLM, Ollama's `/v1`,
Strata and anything else that serves `GET /models` and
`POST /chat/completions`. The selected endpoint and model become the device's
active AI backend (`backend: "openai"`) and drive both plain inference and
Kelpie's built-in browser agent.

Supported on macOS, iOS and Android. The device does the talking: every probe,
model listing and generation is made **from the device running Kelpie**, not
from the computer running the CLI. Contract:
[docs/api/ai-endpoints.md](../api/ai-endpoints.md).

Ground rules:

- **`localhost` is the Kelpie device.** `localhost`, `127.0.0.1` and `[::1]`
  resolve on the Mac running Kelpie, or on the phone itself — never on the
  machine where you type `kelpie`. The CLI prints a note when you save a
  loopback URL, and every endpoint reports `loopback: true`.
- **Saving does not connect.** Only `test`, `models`, `health --refresh` and
  `use` contact the server.
- **No silent fallback.** If the selected endpoint fails, the request fails
  with a specific error. Kelpie never switches endpoint, model or backend on
  its own and never routes to a cloud provider.
- **API keys never touch argv.** Pass them with `--api-key-env <VAR>` or pipe
  them with `--api-key-stdin`. A literal `--api-key` is refused. Keys are stored
  in the device's encrypted secret store and are never printed, returned or
  logged; CLI output is redacted defensively as well.
- **Text-only means text-only.** Screenshots and images are never sent to a
  model unless its `vision` capability is `true`.

`<endpoint>` is an endpoint id or its name (exact, or a unique
case-insensitive match).

---

### `kelpie ai endpoint list`
List saved endpoints with their capabilities (each with a `source`: `server`,
`user`, `test`, or `null` when unknown), cached health, the active endpoint
and model, and `executionHost` — what loopback means on that device.

```bash
kelpie ai endpoint list --device mac
```

### `kelpie ai endpoint add`
Save a new endpoint. The base URL must be `http://` or `https://` with a host
and optional port (1–65535); user info (`user:pass@`), query strings and
fragments are rejected. Pasted operation suffixes (`/chat/completions`,
`/completions`, `/models`, `/embeddings`) are stripped, duplicate slashes are
collapsed, and an empty path becomes `/v1`. The CLI checks this before
contacting the device; the device re-validates and is authoritative.

| Flag | Description |
|---|---|
| `--name <name>` | Display name (required) |
| `--base-url <url>` | Base URL, e.g. `http://192.168.1.20:1234/v1` (required) |
| `--model <id>` | Model ID exactly as the server lists it |
| `--context-window <n\|unset>` | Declare the context window in tokens; `unset` clears your override |
| `--vision <yes\|no\|unknown>` | Declare image input; `unknown` clears your override |
| `--tool-calling <yes\|no\|unknown>` | Declare tool calling; `unknown` clears your override |
| `--json-schema <yes\|no\|unknown>` | Declare JSON-schema output; `unknown` clears your override |
| `--api-key-env <VAR>` | Read the API key from this environment variable |
| `--api-key-stdin` | Read the API key from stdin |

```bash
kelpie ai endpoint add --device mac --name "LM Studio" --base-url http://studio.local:1234
STRATA_KEY=… kelpie ai endpoint add --device iphone --name Strata \
  --base-url http://192.168.1.20:18880/v1/chat/completions --api-key-env STRATA_KEY
op read op://dev/strata/key | kelpie ai endpoint add --device pixel --name Strata \
  --base-url https://strata.example.com/openai/v1 --api-key-stdin
```

Declared capabilities override what the server reports. Leave them unset
unless the server's metadata is missing or wrong.

### `kelpie ai endpoint edit <endpoint>`
Change a saved endpoint. Takes the same flags as `add` plus `--clear-api-key`.
Omitted flags keep their saved values.

```bash
kelpie ai endpoint edit Strata --device mac --model qwen3-8b --tool-calling yes
kelpie ai endpoint edit Strata --device mac --clear-api-key
```

### `kelpie ai endpoint remove <endpoint>`
Delete an endpoint and its stored API key. Removing the active endpoint
unloads the `openai` backend.

### `kelpie ai endpoint models <endpoint>`
Have the device fetch `GET {base}/models`. Model IDs are shown exactly as the
server returns them, with context window, vision and load status when the
server publishes them. An empty list succeeds with a warning;
`MODEL_DISCOVERY_UNSUPPORTED` means the server has no listing, so pass the
model ID with `--model`.

### `kelpie ai endpoint test <endpoint>`
Check reachability, list models and run a short generation.

| Flag | Description |
|---|---|
| `--model <id>` | Test this model instead of the endpoint's selected model |
| `--no-generate` | Only probe reachability and model discovery |
| `--tools` | Also verify tool calling; the result is recorded as `toolCalling` with source `test` |

```bash
kelpie ai endpoint test Strata --device mac --tools
```

### `kelpie ai endpoint health [endpoint]`
Show the cached health of an endpoint (default: the active one). `--refresh`
probes now. States: `unknown`, `unreachable`, `auth_failed`, `loading`,
`no_model`, `model_missing`, `ready`, `busy`. A plain HTTP 200 never means
`ready`: the selected model must be listed (or, when the server has no model
listing, a generation test must have passed). Results older than 90 seconds
read `unknown` with `stale: true`.

### `kelpie ai endpoint use <endpoint>`
Make the endpoint the active AI backend, optionally with `--model <id>`. Sends
`ai-load {backend: "openai", endpoint, model}`. If the endpoint is unreachable
or rejects the key, the command fails and the previous backend stays active.

```bash
kelpie ai endpoint use Strata --device mac --model qwen3-8b
kelpie ai status --device mac
```

---

## Agent runs

With an OpenAI-compatible backend, `kelpie ai ask "<task>"` (no `--context`)
runs Kelpie's agent loop on the device. The tab is pinned when the run starts.
The model gets read-only tools — current URL, page text, visible elements,
find element, form state, accessibility tree, wait for element — and, only with
`--allow-actions`, click, fill, select option, check and uncheck in that pinned
tab. Navigation, script evaluation, cookies, storage, screenshots and tab or
window management are never offered. Page content is treated as untrusted data.

- `--max-steps <n>` caps tool steps (default 12, maximum 25 →
  `AGENT_STEP_LIMIT`).
- `--no-agent` forces plain inference.
- The agent needs tool calling. If the capability is unknown the run fails with
  `TOOLS_UNVERIFIED`.
- Answers come back with `steps`, `finishReason`, `endpointId` and `model`;
  reasoning text, when the server streams it, is returned separately and never
  shown as the answer.
- `kelpie ai cancel` stops in-flight runs.

## MCP tools

`kelpie_ai_endpoints`, `kelpie_ai_endpoint_save`, `kelpie_ai_endpoint_remove`,
`kelpie_ai_endpoint_models`, `kelpie_ai_endpoint_test`,
`kelpie_ai_endpoint_health` and `kelpie_ai_cancel`. `kelpie_ai_load` accepts
`backend: "openai"` with `endpoint` (id or name) and optional `model`;
`kelpie_ai_ask` accepts `agent`, `allowActions` and `maxSteps`.
`kelpie_ai_endpoint_save` has no raw key field: `apiKeyEnv` names an environment
variable read by the process running the MCP server, and `clearApiKey` removes
the stored key.

## Troubleshooting

Start with `kelpie ai endpoint test <endpoint> --device <device>`; the error code
says which layer failed.

| Symptom | Meaning | What to do |
|---|---|---|
| `ENDPOINT_UNREACHABLE` / health `unreachable` | The **device** could not connect. | Check the address from the device's point of view (below). Confirm the server is running and the port is right. |
| `ENDPOINT_AUTH_FAILED` / `auth_failed` | The server answered 401/403. | Re-save the key with `edit --api-key-env` or `--api-key-stdin`; clear it with `--clear-api-key` if the server needs none. |
| `ENDPOINT_LOADING` / `loading` | Reachable, but the server or model is still loading (503, or the model reports `loading`/`unloaded`). | Wait for the server to finish loading, then `health --refresh`. |
| `model_missing` or `MODEL_NOT_AVAILABLE` | Reachable, but the selected model is not in the server's list. | Run `models`, then `use <endpoint> --model <id>` with an ID exactly as listed. |
| `no_model` / `NO_MODEL_SELECTED` | No model selected. | `use <endpoint> --model <id>`. |
| `MODEL_DISCOVERY_UNSUPPORTED` | The server has no `/models`. | Type the model ID with `--model`; `test` then proves it works. |
| `ENDPOINT_MALFORMED_RESPONSE` | Not OpenAI-shaped JSON at that base URL. | Check the base path (often `/v1`, sometimes `/openai/v1` or `/api/v1`). |
| `ENDPOINT_REDIRECT_REFUSED` | The server redirected to another origin. | Save the final URL directly; keys are never forwarded to another origin. |
| `TOOLS_UNVERIFIED` | The agent needs tool calling and it is unknown. | Run `kelpie ai endpoint test <name> --tools`, or declare `--tool-calling yes` if you know it works. |
| `TOOLS_NOT_SUPPORTED` | The endpoint cannot call tools. | Use `--no-agent` or a `--context` mode. |
| CLI times out but the device keeps working | The CLI stopped waiting. | `kelpie ai cancel`, or pass a larger `--timeout`. |

**Whose localhost?** `localhost`, `127.0.0.1` and `[::1]` are the device
running Kelpie. On a Mac running both the server and Kelpie, `localhost` works.
On a phone, `localhost` is the phone: use the server's LAN address (for example
`http://192.168.1.20:1234/v1`) — and make the server listen on the network, not
only on `127.0.0.1` (llama-server `--host 0.0.0.0`, LM Studio "Serve on local
network", vLLM `--host 0.0.0.0`, Ollama `OLLAMA_HOST=0.0.0.0`). Check that the
host firewall allows the port.

**No fallback.** A failing endpoint is reported, never worked around. If you
want another backend, select it yourself with `kelpie ai load` or
`kelpie ai endpoint use`.

**Protocol fixture.** `tests/fixtures/openai-compatible/server.mjs` is a
scripted protocol fixture (not an inference server) for checking a device's
endpoint handling; see its README.
