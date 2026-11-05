# Strict workflow privacy/preflight error parity audit

Source-only common review at
`2e08956fa0f1a67bbf05b533efac5eb05b5ba0b7`.
This is a finite alignment list,not a request to unify all platform errors or
change legacy responses. No platform source was edited.

| Situation | Android current code | iOS/macOS code | Recommended strict-v1 mapping |
|---|---|---|---|
|Marked capture preflight or runtime sensitive target|SENSITIVE_CAPTURE|SENSITIVE_CAPTURE_REFUSED|SENSITIVE_CAPTURE_REFUSED|
|Unbound nonempty input declaration or unresolved edit reference|UNRESOLVED_SCRIPT_INPUT|UNRESOLVED_INPUT|UNRESOLVED_INPUT|
|Duplicate named output/extraction|DUPLICATE_SCRIPT_OUTPUT|DUPLICATE_OUTPUT|DUPLICATE_OUTPUT|
|Bounded redactor refusal/failure|SCRIPT_OUTPUT_REDACTION_FAILED|OUTPUT_REDACTION_FAILED|OUTPUT_REDACTION_FAILED|

The privacy code is now the documented common contract. The remaining mappings
were sent to root/mobile owners for scoped strict-v1 alignment. Desktop already
uses UNRESOLVED_INPUT and DUPLICATE_OUTPUT,but currently distinguishes
OUTPUT_REDACTION_COLLISION from OUTPUT_REDACTION_LIMIT. Those finer safe failure
enums describe different reasons; this audit does not flatten them without a
common decision. Every redaction failure must discard capture regardless of
the final public code.

SESSION_UNSUPPORTED and UNSUPPORTED_SCRIPT_ACTION already align. Missing native
session binding must refuse before actions; body-supplied IDs never grant access.
Unsupported trusted-key/input guarantees,renderer/codec availability and
uncertain completion are necessary runtime differences,not naming aliases.
Do not map INPUT_UNCERTAIN to a definite preflight refusal or remove
mayHaveCompleted:true. Generic gateway COMMAND_FAILED normalization is a
separate transport contract and must not broadly trust arbitrary native errors.

Regression scope: raw owner HTTP,direct/generic MCP and public CLI where
supported,with identical strict fixtures. Assert safe fixed code/message,
zero actions for preflight,privacy-discard latch and scrubbed earlier outputs
for runtime inference,then automatic next-run recovery. Native status remains
success:true for an authorized query,with terminal failure in runError and
no outputs. Source enum alignment and synthetic oracle tests are not actual
mobile runtime evidence.
