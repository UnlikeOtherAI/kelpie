#pragma once
#ifdef __cplusplus
extern "C" {
#endif
// UTF-8 JSON: {outputs:object, extractionNames:string[], secrets:string[]}.
// Names use [A-Za-z][A-Za-z0-9_]{0,63}; duplicates are refused.
// Wire <=5MiB, nesting <=24, lexical tokens <=65536, string literal <=512KiB.
// Output tree <=32768 nodes, serialized outputs <=256KiB; at most1000 names
// and secrets, each secret <=64KiB, aggregate secrets <=4MiB.
// Returns caller-owned UTF-8 {ok:true,outputs} or fixed {ok:false,error:{code}}.
// nullptr means allocation failure. Never expose the input when handling errors.
// Free every nonnull return with kelpie_script_redaction_free_string.
char* kelpie_script_redact_outputs_json(const char* request_json);
void kelpie_script_redaction_free_string(char* value);
#ifdef __cplusplus
}
#endif
