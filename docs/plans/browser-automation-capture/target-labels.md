# Value-free semantic form labels

TGT-01/TGT-05/SEC-01 source follow-up. Windows actual053 label-fill flow found
TARGET_NOT_FOUND for a label containing textarea default text. The shared
boundedText reader included the control's default text in its label name.

The fixed six-argument resolveScriptTarget now excludes entire input,textarea,
select and contenteditable/textbox subtrees from text-derived names, including
external aria-labelledby roots. It counts each private boundary before skipping
descendants; sibling/ancestor navigation is bounded by the existing256-visit name
budget. Text length is checked before substringData copies it. The independent
5000-node whole-document uniqueness search remains unchanged and can still refuse
a very large document with TARGET_QUERY_LIMIT.

Real Chromium regressions cover implicit textarea labels, external labels with
textarea/select/editor descendants, select labels, private aria-labelledby,
normal fill then type, private-canary exclusion and a1000-node private subtree.
A first10000-node test correctly hit the separate global uniqueness limit; its
name-budget fixture was reduced rather than weakening that limit.

Focused target14 plus real-browser30 tests passed44 total on Maxis,
Chromium151.0.7922.34. Final integrated lint/build passed; shared142 tests and CLI694 tests passed
(1 CLI skip). Real Chromium corpus30/30 passed. Regenerated native contracts and
Debug gateway/extension CTest2/2 passed1.62s. Durable capture/target evals13/13 passed.

The built fixed reader was also manually exercised in headless Chromium151:
Draft message resolved; fill produced written; type appended -more; final textarea
value was written-more, with no private canary in reader results. This was the
fixed machine interface, not a native app flow.

Commands: sequential pnpm recursive lint/build/test with workspace-concurrency1
and Vitest maxWorkers/minWorkers1; shared test:browser with one worker; CMake
Debug targets test_browser_gateway/test_native_extensions -j1; CTest matching
those targets -j1; node --test --test-concurrency=1 tests/capture/{target-regressions,harness}.test.mjs.
Logs common11-integrated-{lint,build,test,browser}.log,
common11-label-native-build.log,common11-capture-evals.log and inspected
common11-manual-label.json are under
D:/BuildArtifacts/kelpie/capture-observations-20261104. Tested source is the
label follow-up over merged620d4ed1 (root ad60 plus prior scoped common commits).
No protocol or native asset is hand-edited; the native build regenerates from
this freshly built shared source. No Windows wrapper or
selector fallback was changed. Every native platform must rebuild assets from
this source and replay actual label fill/type before claiming native acceptance.
Computer Use remains OFF; these checks do not establish native UI behavior.
