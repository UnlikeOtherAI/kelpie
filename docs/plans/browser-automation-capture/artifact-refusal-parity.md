# Artifact refusal parity

Source base b927cb999509e25e3c85f3012620713b736dc73a.
Root approved only trusted extension execute responses for get-script-artifact:
ARTIFACT_NOT_READY and ARTIFACT_NOT_FOUND survive MCP formatting with fixed safe
messages. Native error text/data are discarded. Top/nested uncertainty remains;
unrelated method or error-code spoofing still produces COMMAND_FAILED.

The owner store's native HTTP response is used as the reference in compiled
test_native_extensions ArtifactRefusalParity. Direct named MCP and generic
kelpie_extension receive the same code for both approved refusals, including
top/nested uncertainty. PRIVATE_NATIVE_MESSAGE/PRIVATE_BYTES are excluded.
A spoof on get-script-status and a TIMEOUT are not normalized.
These are real shared-gateway tests with injected native replies, not an HTTP
server or shipping application run. Actual HTTP/direct/generic early-download
and foreign-owner parity remains a platform runtime gate.

## Check result

Maxis existing VS17 Release noCEF/noLLM stub build:
cmake --build D:/BuildArtifacts/kelpie/capture-observations-20261104/native
--config Release --target test_native_extensions test_browser_gateway -- /m:1,
then both core-mcp/tests/Release executables passed (catalog/forwarding parity
and gateway contracts). Hard JobObject affinity1/Normal/2GiB,free25939176KiB,
63.522s,exit0. Cached authoritative configure rebuilt shared generator input;
no new CEF/LLM bootstrap or application build. Existing MSVC DNDEBUG/UNDEBUG
test-assert override warning remains. No owned job remains.

## Authoritative native validation include

Desktop callers can include kelpie/browser_schema.h and
kelpie/native_extension_schema.h, then call
ValidateBrowserJson(NativeExtensionInputSchema("get-script-artifact"), &body)
on a mutable copy BEFORE phase availability checks. Validation applies generated
defaults. The public header owns the existing declaration; src/browser_schema.h
only forwards to it. No validator/schema copy or wire/C ABI was introduced.
The native extension test now includes only the public validator path.

Maxis existing stub test_native_extensions rebuilt and passed under hardJob1CPU/
Normal/2GiB,free29341256KiB,32.946s. NoCEF/noLLM/no app; existing MSVC test-assert
override warning only. This verifies public include/link and generated schema
semantics; actual desktop caller/runtime remains platform-owned.

## Independent consumer review

- iOS8964d68e: missing-result callback covers every initial/recheck/dispatch stage
  including click/tap; editing text is optional while capture discard is shared.
  Evaluation-start tracking and explicit false classification preserve the
  distinction between rejected work, known nonsensitive and missing result.
  b5a2a4ec adopts shared validation before active artifact refusal. Actual
  deadline callback retirement/terminal liveness and privacy replay remain open.
- Android8a6a7d4e: started callback occurs after guard before WebView invocation;
  result metadata is consumed before ticket completion, including canceled
  continuation. Found initial click/recheck unknown classification excluded by
  editing-or-dispatch condition; reported to owner for the narrow capture-discard
  fix. Literal registration remains editing-only. Independent follow-up inspection
  of277d522fe5783f317a3debdb5ecd9626f4482499 confirms unknown callback/catch
  handling now covers all target stages; consumeSensitivity still registers
  literals only for fill/type. This closes the source finding, not runtime proof.
- Desktop81ed1727: actual focus privacy replay passed, but post-Input.insertText
  classification is absent. Root/owner are probing oninput type/autocomplete
  transitions; no claim from focus-only coverage. The actual diagnostic now proves
  all four capture/no-capture by autocomplete/type cases leaked earlier raw/URI/
  form outputs after one edit; capture cases retained two artifacts. Raw Maxis
  native-edit-diagnostic-81ed/post-edit.json SHA-256
  043723b80cdc9637076b9c115cab6e92ced76a5f6c6f13365bee402175094843.
  The diagnostic exit zero is not a security pass. Missing click classification
  also needs capture discard. Target metadata preservation and structured
  unknown-result detection were reviewed; earlier027 draft lost metadata.
- Mac current integration has startup/shared-store changes; its new sensitivity
  adapter was still uncommitted at this review. No positive adapter acceptance
  is inferred from shared policy or source compatibility.

All first-error/uncertainty and before-ticket-completion callbacks must precede
final redaction/disposal/publication. No callback result means no observable DOM
classification: protect the current attempted edit literal even without capture,
discard capture if requested, preserve actual uncertainty, and await existing
retirement safely. Do not release/replay an unresolved mutation to make tests end.
