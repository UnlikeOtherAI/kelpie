# CLI Browser Launch Design

## Goal

Add CLI-managed macOS browser instance management so parallel local agent sessions can:

- register a named browser alias
- launch a new Kelpie macOS app instance for that alias
- inspect and list registered aliases and current runtime state

This is CLI-local state, not part of network discovery. Persistent state lives under `~/.kelpie`.

## Constraints

- Keep discovery as live network truth. Do not mix persistent aliases into mDNS/device discovery.
- If `Kelpie.app` is not installed, fail with a clear CLI error.
- `browser launch` must support an explicit `--port` but also auto-assign a free port when omitted.
- Help must exist at each command level: root CLI, `browser`, and `browser` subcommands.
- Keep complexity low. The CLI owns alias persistence; the macOS app only needs launch-time configuration.

## Proposed CLI Surface

```bash
kelpie browser register <name> [--app <path>]
kelpie browser launch <name> [--port <port>] [--wait]
kelpie browser list
kelpie browser inspect <name>
kelpie browser remove <name>
```

### Semantics

- `register`
  - Creates or updates a named macOS browser alias.
  - Stores only stable configuration: alias name, platform, app path.
  - If `--app` is omitted, launch resolution uses the default installed app lookup.

- `launch`
  - Resolves the app path from the alias or default install lookup.
  - Verifies the app exists.
  - Chooses a port:
    - `--port` if provided
    - otherwise the first free port starting at the default server port
  - Launches a new macOS app instance with `open -n`.
  - Passes launch arguments so the app binds to the chosen port.
  - Stores runtime state for that alias: current port and last launch time.
  - `--wait` polls discovery/HTTP until the launched instance is reachable.

- `list`
  - Shows all registered aliases.
  - Includes current runtime state if present.
  - Includes live status when the alias port is currently reachable.

- `inspect`
  - Shows the full alias definition and runtime state for one alias.

- `remove`
  - Deletes the alias and any saved runtime state.
  - Does not kill running app processes.

## Persistence

Single file:

- `~/.kelpie/browsers.json`

Proposed shape:

```json
{
  "version": 1,
  "browsers": {
    "claude-a": {
      "platform": "macos",
      "appPath": "/Applications/Kelpie.app"
    }
  },
  "running": {
    "claude-a": {
      "port": 8427,
      "lastLaunchedAt": "2026-04-01T09:00:00.000Z"
    }
  }
}
```

Rationale:

- Stable alias config and ephemeral runtime state are separate concerns.
- One file keeps the implementation minimal.

## App Resolution

Resolution order:

1. Alias `appPath` if configured
2. `/Applications/Kelpie.app`
3. `~/Applications/Kelpie.app`

If none exist, return:

```json
{
  "success": false,
  "error": {
    "code": "APP_NOT_INSTALLED",
    "message": "Kelpie.app was not found in /Applications, ~/Applications, or the registered app path."
  }
}
```

## Port Allocation

CLI allocates ports before launch.

Rules:

- If `--port` is set, require that it is currently bindable.
- If omitted, scan from `8420` upward and use the first free port.
- Avoid ports already recorded in CLI runtime state if they are still live.
- Skip ports reserved by the app itself, especially `8421` in debug builds where AppReveal uses that port.

This keeps the macOS app simple. It receives a concrete port instead of performing alias-aware coordination itself.

## macOS App Changes

Add launch argument parsing at app start:

- `--port <number>`

Behavior:

- The app creates `ServerState(port: parsedPort)` for the launched instance.
- Existing fallback logic in `ServerState` still applies if the requested port becomes unavailable before bind.
- `open -n -a /Applications/Kelpie.app --args --port 8427` launches a distinct process and window.
- No new `/v1/*` browser routes are required for this feature, so there is no HTTP route-surface clash to manage.

No persistent app-side alias storage is needed.

## Help Requirements

Add or improve:

- root CLI `--help` to include the `browser` command
- `kelpie browser --help`
- `kelpie browser register --help`
- `kelpie browser launch --help`
- `kelpie browser list --help`
- `kelpie browser inspect --help`
- `kelpie browser remove --help`

Also update:

- LLM help metadata
- explain/help metadata where applicable
- docs/cli.md
- docs/functionality.md

## Testing

CLI tests:

- registry read/write and alias removal
- launch command app-missing failure
- launch command auto-port selection
- launch command explicit port validation
- command registration/help smoke coverage

macOS app:

- build verification after adding launch-argument parsing

## Cross-Provider Review

The ideal process here is a true different-provider review. That provider was not available in this execution environment, so an adversarial Codex review was used as a fallback to pressure-test the design before implementation.

Accepted findings:

- Discovery alone is not sufficient for this feature because the CLI's live registry is discovery-oriented and not designed to be the stable source of truth for named local browser aliases.
- Port allocation must explicitly avoid `8421` because that port is already used by AppReveal in debug builds and by CLI MCP by convention.
- App startup must not blindly start AppReveal on every process because multiple local app instances would otherwise contend for the same debug port.
- Launch-time port assignment should stay CLI-owned and the app should only consume a concrete `--port` argument.

Rejected findings:

- Adding new browser HTTP routes was rejected as unnecessary complexity. This feature is local-process launch orchestration, not browser API expansion.
- Moving alias persistence into the app was rejected because it would mix local CLI coordination concerns into the macOS app without improving the user workflow.
