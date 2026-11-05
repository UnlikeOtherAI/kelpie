# Native artifact protocol acceptance helper

ART-01/02/03/04 and DIF-01 evidence must distinguish HTTP,direct named MCP and
generic kelpie_extension chunk calls. Discovery/status proof does not establish
generic artifact retrieval. The helper launches no app and reads no readiness,
credential file or endpoint environment variable.

## Owner invocation at a real runtime slot

Import startArtifactProtocolFixture from
tests/capture/artifact-protocol-fixture.mjs and verifyArtifactProtocols from
tests/capture/artifact-protocol.mjs. The owner supplies already-authenticated,
exact-socket-pinned request functions and the same owned run/artifact manifest.

1. Start the ephemeral loopback fixture; navigate the owned native tab through
   its public API. Wait for the image to load. Use an unobscured renderer with
   at least512x512 image pixels visible; take a native workflow PNG artifact.
   The512x512 RGB noise uses a fixed synthetic seed and no private page data.
2. Require actual native manifest image/png byteLength>268288 (262KiB). A smaller output
   fails this case; do not relax the bound to accommodate blank/truncated pixels.
   Native screenshot encoding may differ from the fixture PNG encoding.
3. Call the helper with runId,artifact,http,mcp. http(method,body,{signal}) posts
   to the caller's pinned /v1/ endpoint. mcp(name,args,{signal}) sends tools/call
   to the caller's pinned /mcp endpoint. Honor AbortSignal and retain owner/grant
   validation. Callbacks may return canonical native JSON,gateway ok/value,
   MCP content or a JSON-RPC result envelope.
4. The helper explicitly invokes HTTP get-script-artifact,direct named
   kelpie_get_script_artifact,and generic kelpie_extension with
   {name:kelpie_get_script_artifact,arguments:chunkRequest}. Never implement
   both MCP callbacks by silently rewriting them to HTTP.
5. Save returned bytes under the owner's ignored evidence root and decode the
   actual PNG. Attach the returned credential-free report to exact source,
   binary/version,protocol and grant lifecycle evidence. Close the fixture in
   finally. Report only report,not private callback closures/readiness.

The default262144-byte chunk forces multiple requests. Every chunk must echo
run/artifact identity,offset,full size,hash and MIME; decoded bytes must advance
nextOffset exactly,EOF must coincide with manifest size,and canonical base64
must fit the requested range. Reassembled bytes/hash/size and PNG signature
must agree across all three paths.

Work is bounded: default artifact budget16MiB,maximum32MiB,chunk4096..1048576,
8192 maximum chunks,10s per request and120s total deadline. Caller may lower
deadlines; a noncooperative callback is not awaited past the bounded race.
The caller must still honor its abort signal to retire actual transport work.
The helper has no mutation retry and never logs credentials.

## Separate negative cases

Malformed offset/length,offset beyond EOF,wrong run/artifact identity,foreign
owner,revoked/stale grant and changed socket must be exercised separately.
They are not failures of the positive byte-comparison helper and cannot be
claimed from a synthetic test. A declined chunk must not expose data or
metadata. Owner status and subsequent authorized recovery remain separate.

## Current evidence

Maxis Node24 focused script tests passed4/4 with one test process: deterministic
large PNG inflate/bytes,three-path reconstruction; truncation/hash/offset/EOF/
MIME/base64 rejection; timeout+abort; and actual ephemeral HTTP fixture fetch.
The fixture PNG is hand-generated from a fixed algorithm and stored only in
memory/ignored evidence. These are helper/unit/HTTP-fixture outcomes,not native
MCP acceptance. Windows and Linux owners were asked to invoke at their next
authorized runtime slots; mobile can reuse the transport-neutral callbacks.
No app/CEF/build/desktop input/Computer Use ran for this tranche.
