# Shared native workflow output redaction

Native bindings call `native/core-automation/include/kelpie/script_redaction.h`:

```c
char* kelpie_script_redact_outputs_json(const char* request_json);
void kelpie_script_redaction_free_string(char* value);
```

Pass UTF-8 JSON `{outputs:object,extractionNames:string[],secrets:string[]}`.
The secret list is private runtime provenance, never model authority. Project only
extraction action names rather than copying action bodies. Names follow the
workflow output-name contract `[A-Za-z][A-Za-z0-9_]{0,63}`; duplicate names refuse.
A missing extraction output is allowed when its action never completed.

Success is `{ok:true,outputs}`. Refusal is `{ok:false,error:{code}}`, where code is
`OUTPUT_REDACTION_INVALID`, `OUTPUT_REDACTION_LIMIT` or
`OUTPUT_REDACTION_COLLISION`. Errors contain no parser/page diagnostics.
A null pointer means allocation failure: fail closed and emit a fixed caller error.
Free every nonnull result exactly once using the dedicated free function;
`free(nullptr)` is supported. No C++ exception crosses this interface.

Only the supplied outputs are returned. Generic nested strings and dynamic keys
are recursively redacted, including when extractionNames is empty. Recognized
extraction protocol keys and typed enum/boolean/count metadata remain structural;
page-derived names, values, selectors, URLs and metadata are scrubbed. Renaming two
dynamic keys to the same redacted key refuses the whole output. Replacement is
one pass, so short secrets cannot recursively rewrite the replacement marker.

Raw secret matching is case-sensitive. URI and form encodings additionally match
upper/lower/mixed hex letters within percent triplets; ordinary characters retain
their case. A raw secret containing a literal percent triplet still matches that
raw literal case-sensitively. UTF-8 encoding uses bytes, not locale rules.

## Limits

The scanner bounds work before JSON materialization: at most5MiB input,
24 nesting levels,65536 lexical tokens and512KiB per string literal. The JSON
parser then validates syntax, escapes and UTF-8. Output traversal permits32768
nodes,24 levels and256KiB cumulative source strings/keys/node accounting;
serialized redacted outputs also cannot exceed256KiB. These are independent
budgets, and output expansion can refuse even when the source fits.

At most1000 extraction names and1000 secrets are accepted; each secret is at most
64KiB and aggregate secret bytes at most4MiB. Pattern attempts and character
comparisons share an8million-operation budget. Over-budget output is refused
atomically; callers must never fall back to raw content.

The C++ `RedactNamedScriptOutputs` wrapper shares the algorithm and validates
already-materialized caller-owned objects. Desktop `RedactScriptOutputs` retains
its existing signature and delegates after projecting extraction names.

## Verification

Maxis, MSVC14.44 Debug, CMake VS17 2022 x64, common checkpoint based on
cdf0a7fbdfed2afb94fb1f56222da725ef204a88. Built with desktop engines and inference
disabled, `cmake --build <native-build> --config Debug --target test_script_redaction -j1`;
`ctest --test-dir <native-build> -C Debug -R '^test_script_redaction$' --output-on-failure -j1`
passed1/1 in0.65s. After the final limit vectors, the same target plus the existing
no-CEF desktop delegation test passed2/2 in1.70s (0.98s ABI,0.70s desktop).
The stub engine required the equivalent C++17 `set.count(...)==0` action-membership
check; no playback behavior changed. Final build log:
`D:/BuildArtifacts/kelpie/capture-observations-20261104/redactor-final-build.log`.

The test directly calls the public C ABI and inspects parsed responses, including
independent allocations/free ownership, null input, malformed JSON, invalid UTF-8,
oversize/deep input, node/secret limits, duplicate/invalid names, dynamic-key
collision, short-secret expansion, mixed percent hex, raw-case preservation,
Unicode, typed extraction metadata and a valid512-field extraction.
This is machine-interface evidence, not native UI or installed-app evidence.
