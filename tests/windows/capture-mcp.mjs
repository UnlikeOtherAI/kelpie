import assert from "node:assert/strict";
import { scriptStatusV1Schema } from "../../packages/shared/dist/index.js";
export async function captureMcp(readiness, method, body = {}, generic = true) {
  const response = await fetch("http://127.0.0.1:" + readiness.port + "/mcp", {
    method: "POST", headers: { authorization: "Bearer " + readiness.token, "content-type": "application/json",
      accept: "application/json, text/event-stream" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/call",
      params: generic ? { name: "kelpie_extension", arguments: { name: method, arguments: body } } : {name:method,arguments:body} }),
    signal: AbortSignal.timeout(360000),
  });
  const envelope = await response.json();
  assert.equal(envelope.error, undefined);
  const wrapped = JSON.parse(envelope.result.content[0].text);
  const value=wrapped.ok ? wrapped.value : { success: false, error: wrapped.error };
  if(method==="kelpie_get_script_status" && value.success) scriptStatusV1Schema.parse(value);
  return value;
}
