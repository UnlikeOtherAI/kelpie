# Post-focus sensitivity on Windows

The archived f188 candidate failed the synthetic post-focus diagnostic. A text field changed to autocomplete=current-password during focus, accepted text input, and returned earlier reflected raw/URI/form output and two capture artifacts. A text-to-password focus mutation refused input with TARGET_MOVED but still returned those reflections and captures. The diagnostic reports only booleans and hashes.

Raw evidence: D:/BuildArtifacts/kelpie/capture-windows-20261104/native-sensitive-focus-f188/privacy-focus.json and flow-report.json. These are security failures, not accepted functionality. Both next-run recovery and public process/socket/readiness cleanup passed.

The source correction consumes the canonical policy:{refuseSensitive:true} target result before target errors, latches capture discard and registers the current edit literal before terminal redaction. Unknown-completion edit inspection also takes this privacy path without changing the first error or waiting longer. Active/finalizing current-run status exposes no artifacts and authorized downloads return ARTIFACT_NOT_READY; older safe terminal runs remain available. Foreign artifact access continues to fail through the owner-bound store.

This checkpoint is source review only until the canonical generated contract, native build, real refusal/no-input/no-artifact/redaction regression and next-run replay pass.
