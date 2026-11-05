# Shared visual viewport target correction

G07/TGT-03 source baseline234c0d1ac511f1849a12e5448e81699cc0567e88.
The resolver used layout0..innerWidth/innerHeight for eligibility,center clipping
and coordinate bounds,and fenced tokens only on layout size. Actual pinch/page
scale can change visual bounds without changing those layout dimensions.

## Actual supported-interface baseline

Maxis existing sandbox-enabled Chromium151.0.7922.34,one owned headless browser,
CDP Emulation.setPageScaleFactor:2,no CSS zoom/staged transform/no OS input.
Layout remained800x600; actual visualViewport became400x300 at origin0,scale2.

The old resolver accepted a scale1 token after scale2. A button at layout
x350..550 resolved center450,width200,outside the visible0..400 region.
A fully offscreen button600..700 still resolved center650. This proves the
shared invariant defect rather than inferring it from mobile source.

The first attempt aborted before loading the fixture because a Chromium GPU
leaf reset inherited affinity to all CPUs/AboveNormal. Its empty samples report
is retained as a policy failure,not functional proof. The corrected launcher
uses a Windows JobObject: suspended assignment before child code,affinity1,
Normal priority,no breakaway and kill-on-close. A harmless descendant attempted
to widen affinity/raise priority and remained constrained. All observed actual
browser leaves,including GPU/conhost,were1/Normal. Baseline job took13.605s,
free14,475,360KiB; fixed job5.636s,free16,330,500KiB. No other job was stopped.

## Minimal shared fix and outcome

The fixed helper intersects element/ancestor overflow bounds with
visualViewport.offsetLeft/offsetTop/width/height,retaining layout CSS client
coordinates. It captures all five visual fields,including scale,in the internal
token and checks them before input and after synchronous dispatch/focus.
Missing visualViewport falls back to layout bounds. Invalid/nonfinite viewport
metrics refuse safely. Public result viewportWidth/Height stay layout dimensions;
the six-argument generated-reader ABI is unchanged.

The same actual Chromium case now resolves center375,width50,refuses the
offscreen target and rejects the old token as VIEWPORT_CHANGED. Focused11-node
regressions include offset/size/scale changes,ancestor clipping and dispatch
uncertainty. Actual visual panning/nonzero offsets and native iPhone/iPad
pinch/overlay mapping remain separate gates; mock coverage is not native proof.
iOS owner prepared3aaa8d58 XCUI pinch/edge-marker/token-race fixture for the next
authorized hosted run.

## Reproduction and confinement

Permanent source:
tests/capture/target-visual-viewport.mjs;
scripts/testing/windows-confined-process.mjs/.cs;
tests/capture/windows-job-regression.mjs.

The JobObject wrapper accepts fresh report/log paths,timeout100..1800000ms,
absolute executable and argument array. Use30000ms for the browser proof.
The parent flow must remain alive through supported app stop/cleanup when used
for a native alias run; wrapping only a short launch command would close the
job and kill its descendant app. It never owns SSH or unrelated processes.
The job enforces2GiB total committed memory; tool compilation/launcher run at
affinity1/Normal too. No global policy or browser sandbox flags are changed.

Evidence remains ignored at
D:/BuildArtifacts/kelpie/capture-observations-20261104/g07/:
baseline.json (initial denied policy),baseline-job.json,both job policy/log files,
fixed-job.json,fixed-job-policy.json,fixed-job.log,and job-regression-2/.
Baseline source copy is tmp/script-target-before-g07.ts. KELPIE_TARGET_MODULE
selects that copy; KELPIE_TARGET_DIAGNOSTIC=1 records old outcomes without
pretending they satisfy fixed assertions. The fixed run imports current source.
No generated source/assets/evidence are committed.

## Required checks before checkpoint

At this focused draft,Maxis hard JobObject mask1/Normal and2GiB total memory:
pnpm --workspace-concurrency=1 -r lint passed48.042s;
pnpm --workspace-concurrency=1 -r build passed21.516s;
pnpm --workspace-concurrency=1 -r test --maxWorkers=1 --minWorkers=1 passed65.719s.
Shared143 tests passed; CLI697 passed and one existing test skipped.
NODE_OPTIONS=--max-old-space-size=2048 and task D: TEMP/TMP were used.
Fresh available memory was14,558,528KiB; no native compiler/emulator/browser
was launched by this portable check. Whole job136.280s,exit0.
Policy/phases/log remain portable-policy.json,portable-phases.jsonl,portable.log.

Baseline report SHA-256:
bce30455db460957da57e13e28346d7f07cd80a02c3510d6c196b5da7fe47edf.
Fixed report:
9c2a5b63c5c822e4c0efd586f70535d4e5f13541f570dfcd483bdecf9f9b323b.
Windows JobObject source:
6e6ab05eeb629125263ad570c29f638835ed4535dc82b68c0ec0c1dbb29e81e2.
Native assets must be regenerated from the checked shared build by each owner;
no generated file is committed. No native acceptance is claimed here.
