# Independent pinned Lightpanda diagnostic review

Reviewer: common contracts/acceptance owner, 5 November 2026.
This is a read-only source/report audit. No Lightpanda process, profile change,
build, browser or desktop input was started by this reviewer.

## Immutable inputs

Diagnostic source:
`c774ac3ab080d76dc1f41f28b7d2f9601c96a7d8`,
`tests/linux/lightpanda-acceptance.mjs`.
Fixture facts come independently from its exact
`tests/capture/{fixture.html,fixture.js,fixture-server.mjs}`.
Fixed reader source was compiled from owner source90eb, including snapshot.ts,
dom-reader.ts and observation-source.ts; this is distinct from diagnostic SHA.

Owner reports are under
`D:/BuildArtifacts/kelpie/capture-desktop-20261104/lightpanda-actual/`.
The reviewer independently read and SHA-256 hashed each report:

| Prefix | Report SHA-256 |
|---|---|
|1a182318|3c26e858f86c98b6d4ca519574057cc8b3b2cee9a57874c7c8ec93d28596d192|
|754503ba|33f8d2effe656fd774454c1988ce397d4a484ec0cd4d3fc2b896a264ef4f2c24|
|8cfe75c5|d92b07475d8c13461823283d5d6ed633e52752a7c664c55bd29fef3d3f81a188|
|c774ac3a|34e0239a682ded2224efde52b6721264968a513a46eeaa3235d212ce38d052a0|

Pinned1.0.2 binary is76,408,136 bytes, SHA-256
`ae7d01d261efb9e480e18ce3424533332883863bcf70b12a4321b5733f37e19e`.
Reports show memory.max2147483648,CPU quota100000/period100000,pids.max64
and process exit. Egress/unit/teardown proof remains the owner's separate
boundary evidence; this review does not infer a firewall from a config string.

## Findings

The snapshot failure is inconclusive because its assertion is wrong for its
bounds. The frozen fixture plus injected adversaries has26 priority-zero
controls:16 buttons,3 links,5 inputs and2 textareas. Hidden button and hidden
input are excluded, leaving24 expected style-visible controls if the backend
implements the fixed box/style predicate. Covered,disabled,partially clipped
and below-fold controls are still snapshot candidates: this reader does not
promise target interactability or viewport-only snapshot output.

With prioritize:true,maxElements20,all admitted controls precede headings.
Therefore requiring h1 text is incorrect. The first ten actual names match
the independently enumerated source order, starting Confirm order and the
two Duplicate action controls,then Disabled/Covered/Remove/Moving/Start/Stop,
then Details. c774 reports20 controls,830 text characters and no private
canary. That is consistent with bounded prioritization; it is not a pass
for complete snapshot correctness.

The invocation also omitted required host-only prefix. Use
`fixedObservationExpression("snapshot",{prefix:"lp-audit-a-",maxChars:8000,maxElements:20,prioritize:true})`,
then read its snapshot property. The composer does not add a prefix; missing
it produces undefined1-style refs. A second read must use a fresh prefix.
Assert unique prefixed refs,truncated:true,expected control ordering and
private/hidden omission. Do not require headings in the20-control case.
A separate scoped #catalogue read should reach Available products,Green tea
and Black tea,its two Details links,the injected unnamed editable controls
with empty names,and public instructional text. Hidden/private descendant
text must remain absent. Use a larger whole-document limit for an h1 case.

Final extract/status/ready and hidden-selector readiness diagnostics passed.
Extraction returned exactly Green tea/Black tea despite hidden/editor/value
adversaries. These checks do not cover every missing/ambiguous/nested metadata,
bounds,opacity/collapse or provenance case. getClientRects/getComputedStyle
being functions does not establish browser-rendered geometry or pixels.
WebMCP was undefined.

Earlier failures remain evidence: first context conflict; trailing-slash
assertion; second page TargetAlreadyLoaded; concurrent-context refusal;
earlier reload state mismatch; shared managed allocation refusal. Final
sequential cookie/localStorage reset and one isolated managed session with
maxTabs1 passed. Public production stdio was never attempted in these runs.

## Restricted profile recommendation and final gate

After actual final public proof,eligible existing candidate methods are
tabs.list,tabs.close,tab.goto,tab.url,tab.title,tab.back,tab.forward,tab.reload.
Exclude tabs.new,shared/concurrent sessions,all visual/geometry/input methods,
workflow capture and WebMCP. Observation methods need their own corrected
canonical/public proof and an explicit catalogue change; diagnostic evaluation
alone must not advertise them. No method is enabled by this review.

The finite final production stdio corpus must use the exact rebuilt CLI identity,
a clean bounded LP process,empty owned HOME,operator origin allowlist,
maxSessions1,maxTabs1 and isolated allocation:

1. Initialize/version and exact capabilities; default-off unsupported methods.
2. Create isolated session; goto/title/url/history/reload through public tools.
3. Second concurrent session refuses before another context is created;
   tabs.new and foreign tab refuse without breaking the owned session.
4. Explicit shared allocation refuses safely under this restricted profile;
   do not preserve the old shared two-session public test.
5. Close,stale-session refusal,recreate isolated session and verify empty cookie/
   localStorage. Exercise TTL cleanup and subsequent fresh allocation.
6. Transport close retires owned resources while preserving borrowed LP endpoint;
   exact unit/process teardown follows. Clean stdout protocol and bounded errors.
7. Preserve all earlier reports and compare request counts,bytes,wall/CPU/RSS
   with explicit busy-host/one-CPU caveat; no unmeasured speed claim.

Corrected fixed-reader diagnostics should additionally cover scoped/full
snapshot privacy and refs,missing/ambiguous/nested extraction plus publisher
allowlist/provenance,hidden/opacity/collapse readiness and truthful unavailable
network/error status. These are finite required follow-ups,not current passes.
