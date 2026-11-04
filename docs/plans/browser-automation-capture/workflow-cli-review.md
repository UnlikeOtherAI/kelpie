# Workflow CLI and presentation draft review

Reviewed tree: 833c5d9f5d1e291708e3bd8d5e29728bcbcc3f47.
Base: cf1c1a09b78700b7f00aff4f67b07fdd8ac891b0.
This is a staged source draft. No test, browser, encoder or Computer Use session
was started by acceptance. The existing other-task Kelpie process was preserved.

## Findings sent to owner

| ID | Source | Required correction |
|---|---|---|
| CLI-01 | commands/script.ts status/abort still call deviceCommand even with runId. That uses sendCommand, whose 401 handling can pair again or change to another approved address | Use pinned transport for run-owned CLI status/abort, matching the MCP branch. Test 401, changed grant and changed device address with no retry/pair/fallback |
| CLI-02 | downloadScriptArtifact sets verified=true before awaiting file.close. If close throws, the finally branch skips unlink and leaves its partial file | A failed close must keep the transfer unsuccessful and clean only its owned temporary file. Add a fault-injected close case, preserving an unrelated destination/partial |
| CLI-03 | rawFetch catches JSON.parse and returns error.message. A malformed response can put a response excerpt into the model-facing error | Pinned workflow operations need fixed safe transport/parse error text. Test malformed response containing a canary without relying on known bound-secret redaction |

Malformed local script/input JSON is already caught with a fixed safe error.
That test does not cover malformed HTTP response JSON. Host-known secret values
are retained in a WeakMap and redacted in playback results, including short
strings and object keys, but that is not a substitute for safe transport errors.

## Source assessment

createPinnedCommandTransport copies the selected device/socket and token once.
It refuses redirects and performs no pairing, address fallback or grant rotation.
Local readiness files are checked against launch ID, device ID, port and exact
token. The admitted playback and automatic downloads share this closure.
Authorization setup is an existing read-only capability request before playback.

downloadScriptArtifact validates strict manifests and chunks, canonical base64,
run/artifact IDs, offset progress, total size, MIME, hash and EOF agreement.
Downloads request 256 KiB chunks and hash incrementally; transport response
streams are bounded before JSON parsing. Remote identifiers never become local
path components. The chosen parent resolves once, an unpredictable partial file
uses exclusive creation, and hard-link promotion refuses an existing destination
or symlink. Failure tests preserve unrelated files. CLI-02 remains the close-error
hole in this otherwise coherent path.

The reusable extract action uses BrowserExtractionOptionsSchema rather than a
second extraction schema. Duplicate output names are refused before binding.
Explicit sensitive actions and secret references both reject capture or screenshot
steps. Bound values have length/type checks and host environment mapping is removed
before the native request. Version 1 performs strict body validation; the legacy
route retains its separate shape.

The target name walker now counts all traversed nodes, and aria-labelledby with
more than 32 references refuses an incomplete name instead of silently matching
a prefix. These resolve the two remaining bounded-name findings from the earlier
source audit. The final real DOM/native target corpus is still required.

## Numeric presentation parity

script_presentation.cpp mirrors the TypeScript cubic C/S curve, smoothstep timing
and wobble/fade functions. Zero/non-positive duration finishes immediately;
NaN is normalized to the initial state. Native C ABI structs contain only numeric
state, avoiding a per-frame JavaScript/JSON execution dependency.

generate-script-presentation.mjs produces test-only vectors from the built shared
functions. Native tests compare the vectors with 1e-9 tolerance and cover NaN/
infinity cases. CMake enables assertions for this test even in release builds,
orders vector generation as a CTest fixture, and rejects stale shared dist by
mtime. This proves the intended numeric correspondence when run; it does not prove
native displayed/exported pixel timing or human-like motion.

## Evidence scope

The owner reports lint/build, shared 126 tests and CLI 649 tests passed; the CLI
suite used a documented 30-second SATA I/O allowance after default timeout
failures. The native helper compiled; CTest and the last malformed-local-JSON
check were pending when this tree was supplied.

Durable files: packages/cli/tests/client/pinned-command.test.ts,
packages/cli/tests/commands/script-artifacts.test.ts, script-parse.test.ts,
packages/shared/tests/script-target.test.ts, script-workflow.test.ts and
native/core-automation/tests/test_script_presentation.cpp.

Actual CLI/MCP script execution, native extraction order, remote chunk retrieval,
secret handling, cancellation/recovery and decoded/displayed media remain pending.
Canonical WFL-03, ART-01..04, SEC-01 and PTR-01/02 are not closed by source tests.
