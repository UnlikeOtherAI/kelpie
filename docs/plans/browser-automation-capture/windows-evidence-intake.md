# Windows 9333 evidence intake

This is evidence intake for manual review, not whole-platform acceptance.
The product source is `9333ff507ec91d06d86e338b1d2d9378daca2ac5`;
the archived private candidate DLL is 8,007,168 bytes, version0.1.15, SHA-256
`27a474291206310a64e17cce27f6f9c50836af55b997b275d5f31e0fc71bca8c`.
The intake independently rehashed that binary.

## Preserved reports and outcomes

Owner artifacts under
`D:/BuildArtifacts/kelpie/capture-windows-20261104` remain immutable.
The common reviewer copied approved reports/media into the separate ignored root
`D:/BuildArtifacts/kelpie/capture-observations-20261104/intake/windows-9333`.
The copy manifest retains original paths, byte counts and source/copy hashes.

- Native flow:29 passed checks,30 original downloaded artifacts.
- Observation corpus:10 passed checks. WEB-01 is default-off/API-probe refusal,
  not a positive native WebMCP authorization claim.
- Public browser-alias flow:4 checks,6 artifacts.
- Security flow:3 checks,3 artifacts.
- Separate ordered-actions and malformed-preflight reports remain available.
- Separate standard UIA Stop source
  `4ec1496e0ad5b4305c2575a72b41072f1e499665` invoked exactly the owned native
  Button once in Session1, observed aborted partial status, recovered and cleaned
  up the owned process/task. This is native accessibility evidence. It does not
  prove screenshots, foreground/modal states or arbitrary desktop input.
- The three UIA partial media files were transferred from existing authenticated
  same-host downloads by SCP, not cross-host API retrieval.

The original39 media files were copied with independently checked source/copy
hashes. Client decode reports retain full single-thread GIF/MP4/PNG decoding.
Newer geometry/UIA/resize artifacts are separate evidence sets; they are not
silently added to the original39. Earlier c852 missing-marker pixels and failed
alias attempts remain historical failures.

## Protocol and visual scope

The permanent Windows corpus uses actual direct and generic native MCP calls.
Direct play/status/artifact chunks and failed-run recovery have explicit calls.
Generic play/abort/status are exercised. Generic artifact chunk coverage must
not be inferred from direct chunks or public CLI stdio calls. CLI alias evidence
is classified as CLI even when it forwards HTTP.

The common reviewer inspected exported old-document frame0002 and destination
frame0004 for movie-only FPS1 navigation. The source frame has a red marker
centered on Next document; the destination has none. Root independently inspected
the same pair and C/S contact sheets, three samples each. These bounded exported
image reviews remain separate from machine all-frame pixel assertions and native
window/UI evidence.

## Reproducible intake

At harness revision `e0cbe05d`, run:

```text
node tests/capture/native-coverage.mjs <intake>/curated-evidence.json <intake>
```

The actual run produced22 curated records,432 runtime/requirement rows,
10 independently verified report files,zero unclassified records and
**zero accepted rows**. All rows remain unreviewed. Curated JSON SHA-256:
`02c447ccc2f5645e581b3c89e9f70720bab2308993fd6b4f6727d803c9594479`.
The raw coverage output was redirected by Windows PowerShell as UTF-16LE;
its byte-preserving SHA-256 is
`c0f862cc8c790dc497b21958cb3bad0cc71d78b2122928b197a2a87c4f01ba52`.
Raw identity/task JSON with UTF-16 BOM was preserved and decoded explicitly,
rather than rewritten. Reports/artifacts are ignored outputs, not committed
generated files. No app launch, browser build, CUA or desktop input was used
during intake.
