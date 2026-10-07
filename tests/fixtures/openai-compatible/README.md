# OpenAI-compatible protocol fixture

**This is a PROTOCOL FIXTURE, not an inference server.** It runs no model and
understands no prompt. It answers with scripted, deterministic replies so that
Kelpie's OpenAI-compatible endpoint client (macOS, iOS, Android, CLI tests) can
be verified against the awkward parts of the wire protocol without a GPU or a
real llama-server / LM Studio / vLLM.

Contract: [docs/plans/2026-10-07-openai-compatible-endpoints.md](../../../docs/plans/2026-10-07-openai-compatible-endpoints.md).

Dependency-free; Node 18 or newer.

```bash
node tests/fixtures/openai-compatible/server.mjs \
  [--port 18990] [--base /openai/v1] [--host 127.0.0.1] \
  [--api-key KEY] [--chunk-max 7] [--chunk-delay-ms 1] \
  [--newline lf|crlf|cr] [--seed 1]
```

When ready it prints one line: `fixture listening on http://127.0.0.1:18990/openai/v1`.
Save that URL as the endpoint base URL.

| Flag | Default | Meaning |
|---|---|---|
| `--port` | `18990` | Listen port; `0` picks a free one (read it from the ready line) |
| `--base` | `/openai/v1` | Base path; the API lives at `{base}/models` and `{base}/chat/completions` |
| `--host` | `127.0.0.1` | Bind address. Loopback by default — it never binds `0.0.0.0` unless told to |
| `--api-key` | none | When set, every API route requires `Authorization: Bearer <key>` (401 otherwise). A test-only value; never a real key |
| `--chunk-max` | `7` | Maximum bytes per written chunk |
| `--chunk-delay-ms` | `1` | Pause between chunks so they reach the client as separate reads; `0` only yields to the event loop (faster, but the client may see some pieces merged) |
| `--newline` | `lf` | SSE line ending: `lf`, `crlf` or `cr` |
| `--seed` | `1` | Seed for the reproducible chunk boundaries |

## Testing a phone or another machine

`localhost` in a Kelpie endpoint means the device running Kelpie. To point a
phone at this fixture, bind it to the LAN explicitly, for example
`--host 0.0.0.0`, and save `http://<this-computer's-LAN-IP>:18990/openai/v1`.
Only do this on a trusted network.

## API routes

- `GET {base}/models` — one model, `fixture-protocol-1`, with
  `meta.n_ctx: 32768`, `architecture.input_modalities: ["text"]` (text-only, so
  `vision: false`) and `status.value: "loaded"`.
- `POST {base}/chat/completions` — `stream: true` gives SSE, otherwise one JSON
  completion (also written in tiny chunks). A `model` other than
  `fixture-protocol-1` gets `404 model_not_found`.

Scripted chat behaviour:

| Request | Reply |
|---|---|
| `tools` present and the last message is from the user | One tool call (`id: call_fixture_1`, `finish_reason: tool_calls`) to the first tool found in the order `get_page_text`, `get_current_url`, `get_visible_elements`, `find_element`, `get_accessibility_tree`, `get_form_state`, `wait_for_element` (else the first tool offered). Arguments follow the contract (`get_page_text` → `{"selector":"body"}`, `get_current_url` → `{}`, …) and are streamed two characters per event |
| last message has `role: "tool"` | `reasoning_content` deltas, then the answer `Fixture answer: "<first 80 chars of the last tool result>" — Příliš žluťoučký kůň úpěl ďábelské ódy 🦭`, `finish_reason: stop` |
| anything else (no tools) | `reasoning_content` deltas, then exactly `fixture-ok` |

Every stream starts with a `: keep-alive` comment and a role-only delta,
interleaves more `: keep-alive` comments, ends the choice with a
`finish_reason` chunk, sends a `usage` frame with `choices: []`, then
`data: [DONE]`. Chunk boundaries are random (seeded) up to `--chunk-max` bytes
and are forced inside every `data:` field name and inside every multibyte UTF-8
character, so per-chunk decoding or per-chunk line matching fails visibly.

## Control API (no auth; loopback only by default)

| Route | Effect |
|---|---|
| `GET /__fixture/state` | `{state, states}` |
| `POST /__fixture/state` `{"state": "<state>"}` | Switch state at runtime |
| `GET /__fixture/requests` | Recorded API requests: `method`, `path`, `headers` (with `authorization` reduced to `"present"` / `"absent"`), parsed JSON `body` |
| `DELETE /__fixture/requests` | Clear the recording |

States (they apply to every API route; auth is checked first when `--api-key` is set):

| State | Behaviour | Kelpie should report |
|---|---|---|
| `ready` | Normal | `ready` |
| `loading` | `503` `Loading model` | `ENDPOINT_LOADING` / health `loading` |
| `auth` | `401` even with the right key | `ENDPOINT_AUTH_FAILED` / `auth_failed` |
| `busy` | `429` with `Retry-After: 1` | health `busy` |
| `malformed` | `200` `text/html` body | `ENDPOINT_MALFORMED_RESPONSE` |
| `empty` | `/models` returns `data: []`; chat still answers | success with the "no models" warning |
| `nodiscovery` | `/models` is `404`; chat still answers | `MODEL_DISCOVERY_UNSUPPORTED` |
| `hang` | Accepts the request and never answers | `ENDPOINT_TIMEOUT` |

```bash
curl -X POST -d '{"state":"loading"}' http://127.0.0.1:18990/__fixture/state
```

The CLI's conformance test (`packages/cli/tests/fixtures/openai-compatible-fixture.test.ts`)
starts this fixture on a free port and checks all of the above.
