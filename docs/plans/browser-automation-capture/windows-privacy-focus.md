# Post-focus sensitivity on Windows

The archived f188 candidate failed the synthetic post-focus diagnostic. A text field changed to autocomplete=current-password during focus, accepted text input, and returned earlier reflected raw/URI/form output and two capture artifacts. A text-to-password focus mutation refused input with TARGET_MOVED but still returned those reflections and captures. The diagnostic reports only booleans and hashes.

Raw evidence: D:/BuildArtifacts/kelpie/capture-windows-20261104/native-sensitive-focus-f188/privacy-focus.json and flow-report.json. These are security failures, not accepted functionality. Both next-run recovery and public process/socket/readiness cleanup passed.

The source correction consumes the canonical policy:{refuseSensitive:true} target result before target errors, latches capture discard and registers the current edit literal before terminal redaction. Unknown-completion edit inspection also takes this privacy path without changing the first error or waiting longer. Active/finalizing current-run status exposes no artifacts and authorized downloads return ARTIFACT_NOT_READY; older safe terminal runs remain available. Foreign artifact access continues to fail through the owner-bound store.

This checkpoint is source review only until the canonical generated contract, native build, real refusal/no-input/no-artifact/redaction regression and next-run replay pass.

The compiled 81ed1727 candidate (DLL SHA e450cc9623c62c67ac55930f19bb84f3b97f973a18da29958c32e897e1513081, DLL version0.1.16; pinned CEF bootstrap version152) passed both post-focus cases: SENSITIVE_CAPTURE_REFUSED, no edit events, no reflected raw/URI/form values, masked earlier output, zero result/status artifacts and next-run recovery. Raw: native-privacy-81ed/privacy-focus.json under the same artifact root. Public cleanup passed.

A separate diagnostic then proved four post-input failures on that candidate: autocomplete/type mutation in oninput, each with and without capture. One edit happened, sensitivity became true, earlier output leaked; capturing runs returned two artifacts. Raw: native-edit-diagnostic-81ed/post-edit.json. These failures remain preserved. The follow-up requires post-edit classification before terminal publication, with already-completed input reported honestly. Missing old-document classification uses the canonical private sensitivityKnown flag, rather than treating an unqualified false as proof.

The broader81ed replay passed33/36 native records, OBS10/10, alias4/4 and all three real artifact protocols. The three normal-edit assertions failed because the fixture's unwrapped event JSON introduced a horizontal scrollbar; this was an effective viewport fence, not a successful edit. The controlled wrapping experiment and permanent fixture correction are documented separately. Full corrected replay remains pending.
