# Android — AI Sheet

The AI sheet opens from the browser shell's AI entry (and `show-panel {panel: "ai"}`) as a
Material 3 `ModalBottomSheet`. It scrolls vertically and has three parts.

## Status

Rows for **Backend** (`Platform`, `Ollama` or `OpenAI-compatible`), **Availability**,
**Active Model**, **Capabilities**, the Ollama endpoint when one is configured, and the
active **Endpoint** name when the OpenAI-compatible backend is selected.

## OpenAI-compatible endpoints

Help text under the heading: *"localhost means this phone. To use a server on your
computer, enter its LAN or .local address and make sure that server listens on the
network."*

Each saved endpoint is a row showing:

- Name, `• In use` when it is the active backend, and a health badge — a coloured dot
  with the state (`ready` green, `busy` blue, `loading` / `no model` / `model missing`
  amber, `unreachable` / `auth failed` red, `unknown` grey; results older than 90 s
  read as `unknown`).
- The normalised base URL, `localhost = this phone` for loopback hosts, and the selected
  model ID exactly as the server reports it.
- Actions: **Refresh models** (model discovery), **Test** (probe, a tiny generation and
  a tool-calling check), **Use** (selects the endpoint as the AI backend; refused while
  it is unreachable or rejecting the key), **Edit** and **Remove** (confirmation dialog;
  deletes the saved key and unloads AI if it was active).

A status line under the list reports the running action and its outcome. **Add
endpoint** opens the editor.

Saving never connects. Only Refresh models, Test, Use and health polling contact the
server. Health polling runs only for the selected endpoint, only while the sheet is
open or the OpenAI-compatible backend is active (30 s while healthy, 5→10→20→40→60 s
while failing), and re-checks immediately when the network changes.

## Endpoint editor

An `AlertDialog` with:

- **Name** and **Base URL** (`http://` or `https://`; pasted `/chat/completions` or
  `/models` suffixes are stripped and `/v1` is added when no path is given). Invalid
  URLs show the validation message inline.
- **API key (optional)** — masked. When a key is saved the field reads
  `Saved — type to replace` and shows **Clear**; the key itself is never displayed.
  Keys are stored in the Keystore-backed `SecretStore`.
- **Model ID** — free text, with **Pick** listing models from the last discovery.
- **Context window (tokens)** — blank means unknown.
- **Vision** and **Tool calling** — `Unknown` / `Yes` / `No` chips. Explicit values
  override server metadata and test results; `Unknown` clears the override.

The agent mode of `ai-infer` requires tool calling to be `Yes` or verified by **Test**.
