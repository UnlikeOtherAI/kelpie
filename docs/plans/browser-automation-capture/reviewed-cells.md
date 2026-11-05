# Explicit requirement reviews

Reviewer: common acceptance owner (/observations), 2026-11-05 UTC.
These are human review decisions for frozen candidates, separate from automated
ingestion. Ingestion remains unreviewed by design. Acceptance below covers the
named requirement/runtime/source only; it does not certify a release, other
renderers, or a subsequent binary. Historical failed attempts remain evidence.

## Windows CEF, windowed, f188

Source: f188883fbbbf16703b3154d81ed609d187a4e4fa, private unsigned 0.1.15.
EXE SHA-256: 54c8be31e003853947182c9461755bf4e7be5f91a2c64fcfb97ed5da1a32d755.
DLL SHA-256: 421e4162fca5ab484ce2901b087800e435e9272a48fd6e161d9cffc5f9fdf60f.
CLI source: e71364364db94a6212f556aa7b5ca9efb09ac003, version 0.1.22.
Entry SHA-256: 831dd89b45aa3186efb8978d3da6ff7e9d8ec7f832ca7519bc152c0dc58e71dd.

Evidence root on Maxis:
D:/BuildArtifacts/kelpie/capture-observations-20261104/intake/windows-f188/.
The reviewer read raw responses and independently rehashed copied binaries,
reports and media. The supported entry points were authenticated HTTP, named MCP,
generic kelpie_extension and the public CLI alias; each row names its actual case.

| Evidence key | Relative file | SHA-256 |
|---|---|---|
| N | raw/native-report.json | 49a36b9a8621b2872c61b1442bbbab9d6a08f165fd4192ff8219eff6d219ec31 |
| O | raw/observations.json | 985c3a5b9365ff291a140b51c99e63a92c2a178616abf155d367d2cced6f2bec |
| P | raw/protocols-report.json | a207b859b848627270094dcdec3bed692441f8a82f196f3596fc5f8390ef6c80 |
| D | client/full-decode-report.json | 15df0302de55df6080578196a2cd1d593619f9e9a0f9e3169e7515628b968e8e |
| V | client/navigation-pixel-report.json | 82e5baf5fd7ee0764ebfec3a4e2e9039ca7c99a3d10147daca14f3bf6efff476 |

### Accepted cells

| Canonical ID | Actual case and observed outcome |
|---|---|
| OBS-01 | O OBS01: actual native snapshot excludes synthetic private form/editor canaries. |
| OBS-02 | O OBS02: catalogue scope excludes Confirm order; repeated observations preserve normalized order, headings and two Details controls. |
| EXT-01 | O EXT01: scalar text/href extraction distinguishes missing and ambiguous selectors; explicit first result returns Green product. |
| EXT-02 | O EXT02: two ordered articles retain nested name/price/href structure. |
| RDY-01 | O RDY01: DOM complete is reported separately from unavailable network/error diagnostics; it makes no task-completion claim. |
| WFL-01 | N strict malformed late actions and duplicate-output preflight: invalid workflows dispatch zero actions. |
| WFL-02 | N unresolved bindings and sensitive capture preflight; actual normal fill/type/key flow: bindings refuse early and resolved edits execute in order without executable interpolation. |
| WFL-03 | N ordered assert/ready/scroll/failure-stop: successful predicates proceed; failed assertion prevents following mutation. |
| TGT-01 | N continuous semantic center case plus Duplicate/Disabled/Hidden refusals: only the unique enabled visible control receives input. |
| TGT-02 | N Covered refusal and continuous case: trusted click at 119,137 hits unique within its visible rectangle. |
| TGT-04 | N moving target, focus navigation/read-only and child replacement cases: stale targets refuse; recovery run succeeds. |
| TGT-05 | N continuous click and native key flow record trusted events and the advertised trusted guarantee. |
| CAP-03 | D: every retrieved MP4 decodes fully with monotonic timestamps and reported dimensions/duration; V confirms source/destination frame attribution. |
| CAP-08 | N MCP abort, failed-status partials and duration/byte stops: partial artifacts remain downloadable and next run recovers. |
| ART-03 | N artifact identity/range cases plus P: malformed ranges/IDs refuse; bounded integer chunks reconstruct the same PNG. |
| ART-04 | N manifests and D/P: MIME, byte count, digest, partial and timing metadata agree with actual reconstructed bytes. |

These sixteen cells are accepted for this frozen runtime. They do not inherit
unexercised variants from portable unit tests.

### Accepted subcases, whole requirement still pending

- ART-01: P independently reconstructs the same 906882-byte PNG over HTTP,
  direct named MCP and generic MCP, four chunks each, SHA-256
  a48cdb6e274010318c4b55c45ee37c57da5631f3dcd565b663a3c21466943d0c.
  The common 37-file decode transfer was SCP of prior authenticated same-host
  downloads, not new cross-host ID retrieval. Final candidate cross-host proof
  remains required.
- SEC-01: N inferred-sensitive refusal scrubs earlier raw/encoded outputs,
  leaves input untouched and discards capture. Full logs and every redaction-
  failure/error-replacement branch are not certified by that single case.
- WEB-01: O proves native default-off/UNSUPPORTED only; positive native WebMCP
  is unavailable and is not a parity pass.
- CAP-01/CAP-02/CAP-04/CAP-05/VIS-01/VIS-02/PTR-01/PTR-02: 37 original artifacts
  fully decode; source red marker and clean destination were independently
  viewed. This does not prove every step, loop, animation timeline or resize.
- TGT-03/UI-01/VIS-01: root independently viewed actual native WGC attempt4
  (not exported annotation): CSS230,180 at DPR2 maps to visible pointer/circle
  center460,360 and radius48; transparent canvas remains uncomposited.
  Native Stop aborts, preserves four valid partials and permits recovery.
  Exact receipt on Maxis:
  D:/BuildArtifacts/kelpie/capture-windows-20261104/windows-native-ui-attempt4-receipt.json,
  SHA-256 f89278a0e0167ed73019cee01e43aa2808d1d44051145d77cc8f389a7e577d14,
  independently rehashed by this reviewer. Root image review is distinct from
  this reviewer's report inspection. PNG SHA-256
  1a74b88fada0e8941811bbab5a1a4081f66efff3b02805accff13ff9c2b09e98.
  Raw report SHA-256
  3f8b4c94000d9208871631331a20252cce126d6b196ffdb0f282be33dd09e139.
  This accepts only the spatial/Stop subcases, not native animation or G07.

All other Windows cells remain pending. In particular: native huge/deep bounds,
metadata/provenance adversaries, delayed/hidden readiness, legacy compatibility,
late-callback ownership/uncertainty stress, final visual-viewport reader relink
and native pinch, backpressure, auth revocation/restart, paired differential
semantics, final Before/After inventory and both release requirements.
First three WGC attempts and c852 missing-marker failure remain historical failures;
attempt4 does not rewrite them.

## Linux GTK frozen3001

CAP-08 and ART-04 are accepted for exact Linux GTK3001 Stop/partial/recovery and
manifest-byte evidence. See [Linux3001 review](linux-3001-reviewed-cells.md) for
source/binary/report/artifact hashes and strict separation from OSR and native UI
pixels. Dense timeline gaps remain in [G08 inventory](g08-final-inventory.md).

## Restricted Lightpanda worker (not a native runtime cell)

CLI source 9a30140514720ad34fe71e1a065b8de0209b5f00, version0.1.22;
fixture 0a6913f700f16080b47244f322a23ced23cebe65; Lightpanda1.0.2 binary
SHA-256 ae7d01d261efb9e480e18ce3424533332883863bcf70b12a4321b5733f37e19e.
Actual public stdio report copied and independently rehashed under common
intake/lightpanda-public-9a301405/report.json:
d7ca0d84efe7f232bb508443af655790cd0d6447b56a275e47f85261c7f63267.

LP-01 and LP-02 are accepted for the explicit restricted profile: seven public
CLI/SDK cases, 41 calls; exact eight-method navigation/lifecycle whitelist;
maxSessions1/maxTabs1, isolated-only admission; shared allocation refused before
backend creation; unsupported methods and foreign tab refuse; close/fresh storage,
TTL retirement and borrowed-endpoint-preserving shutdown pass.
The admitted methods are tabs.list, tabs.close, tab.goto, tab.url, tab.title,
tab.back, tab.forward and tab.reload. This is acceptance of the conservative
profile, not a claim that DOM/layout methods were proven.

OWN-01 multi-owner crossover remains pending beyond the tested unknown-tab,
single-session and fresh-storage cases. OBS/EXT/RDY, geometry, input, capture and
WebMCP are not admitted by this profile. Earlier diagnostic failures remain.
No native cell is accepted from worker evidence.

## Remaining runtime evidence

Android c71 phone/tablet native spatial overlays were independently viewed by
root (blue circle/pointer centered on Submit and visible Stop). Preserve that
subcase separately: phone Stop failed and overall runs were 17/22 and19/22.
It does not accept whole VIS/UI rows or the undownloaded CLI artifacts.
Mac/iOS hosted and Linux installed-package results need their own frozen intake.
Release and final integrated native relinks remain pending everywhere.
