# Script workflows and artifact download

```sh
kelpie --device phone script run demo.json --inputs inputs.json --output ./walkthrough
kelpie --device phone script run signin.json --secret password=MY_PASSWORD
kelpie --device phone script status --run-id returned-run-id
kelpie --device phone script abort --run-id returned-run-id
kelpie --device phone script download returned-run-id artifact-id ./walkthrough.gif
```

Use version1 and an explicit tabId for typed workflows. `--inputs` reads a JSON object of declared values. Repeated `--secret reference=ENVIRONMENT_VARIABLE` maps a workflow secret reference to the CLI host environment; never put a secret value on the command line. Secret workflows cannot capture media or run screenshot steps.

`--output` creates a new directory per run, retrieves authenticated chunks through the same pinned device/socket, checks MIME/offset/size/SHA-256, then writes numbered GIF/MP4/PNG files and a JSON manifest. Existing files are never overwritten. An interrupted or invalid transfer removes only the exclusive temporary file it created. Existing files and symlinks are never overwritten. Failed or aborted runs can still contain valid partial media.

The MCP play-script tool accepts the same workflow fields plus host-only `values`. Before starting MCP, the operator configures `KELPIE_WORKFLOW_SECRET_REFS` as a JSON mapping such as `{"login":"LOGIN_PASSWORD"}`; the named ENV values must already exist in the protected launch environment. Mapping and values are captured for that launch. Models provide only `text:{secret:"login"}`, never ENV names. There is no HTTP/model setter. Explicit CLI `--secret reference=ENV` remains separate; authored script files cannot embed host bindings. `kelpie_get_script_artifact` reads bounded run-owned chunks; callers assemble actual bytes rather than interpreting a remote path.

See the [workflow API](../api/script-workflows.md) for targets, action support, markers, motion, capture bounds and integrity checks. Native support is determined by actual device capabilities and remains distinct from CLI schema support.

Status/abort with a run ID pin the exact current socket/grant. Without a run ID, the unchanged legacy path can auto-pair or try approved alternate sockets. After uncertain playback completion, use `script status --pinned` on the same explicit browser/device while its grant is available; `script abort --pinned` likewise avoids pairing/fallback. Do not start another run merely because its transport timed out.

Secret-result sanitization preserves trusted run/artifact IDs, MIME/size/hash, status/error enums and fixed protocol fields. Page/error text and dynamic output names are redacted, including common URL-encoded reflections. Canonical extraction keeps its structural fields and trusted provenance enums; page strings and unknown payload keys are scrubbed. This does not promise byte-level absence when a secret coincides with a protocol constant. A redaction collision or bound refusal returns OUTPUT_REDACTION_COLLISION/LIMIT with uncertain-completion metadata; it never retries actions.
Strict version 1 playback first reads `get-script-status` on the pinned authenticated socket and requires `success: true` with an explicit `supportedVersions: [1]`. Older browsers must be updated: missing, invalid, or refused support returns `UNSUPPORTED_SCRIPT_VERSION` before any playback, with no legacy fallback. Unversioned scripts retain legacy behavior.
