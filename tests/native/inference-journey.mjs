import assert from "node:assert/strict";
import { createServer } from "node:http";

/** Existing Windows one-shot inference must reach the common reader and cancellation. */
export async function runInferenceJourney(client) {
  const rich = async (name, argumentsValue = {}) => client.callTool({ name: "kelpie_extension", arguments: { name, arguments: argumentsValue } });
  const value = result => JSON.parse(result.content.find(block => block.type === "text").text).value;
  let hold = false;
  let observed;
  const observedRequest = new Promise(resolve => { observed = resolve; });
  const server = createServer(async (request, response) => {
    if (request.url === "/v1/models") {
      response.end(JSON.stringify({ data: [{ id: "fixture-model" }] }));
      return;
    }
    assert.equal(request.url, "/v1/chat/completions");
    const chunks = [];
    for await (const chunk of request) chunks.push(chunk);
    const body = JSON.parse(Buffer.concat(chunks).toString("utf8"));
    assert.ok(body.messages.some(message => message.content.includes("Untrusted page content")));
    assert.ok(!JSON.stringify(body).includes("AI_INPUT_SECRET"));
    if (hold) { observed(); return; }
    response.end(JSON.stringify({ choices: [{ message: { role: "assistant", content: "fixture-answer" }, finish_reason: "stop" }] }));
  });
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  try {
    console.log("Native inference fixture: configuring owned endpoint");
    const saved = value(await rich("kelpie_ai_endpoint_save", { name: "owned-native-fixture", baseURL: `http://127.0.0.1:${server.address().port}/v1`, model: "fixture-model" }));
    assert.equal(saved.success, true);
    assert.equal((await rich("kelpie_ai_load", { backend: "openai", endpoint: "owned-native-fixture" })).isError, false);
    assert.equal((await rich("kelpie_evaluate", { expression: 'document.body.insertAdjacentHTML("beforeend",\'<input value="AI_INPUT_SECRET">\');true' })).isError, false);
    const args = { prompt: "Read fixture", context: "dom", agent: false };
    console.log("Native inference fixture: common context read");
    const answer = await rich("kelpie_ai_ask", args);
    assert.equal(answer.isError, false);
    assert.equal(value(answer).response, "fixture-answer");
    hold = true;
    console.log("Native inference fixture: pending provider cancellation");
    const inference = rich("kelpie_ai_ask", args);
    await Promise.race([observedRequest, new Promise((_, reject) => { const timeout = setTimeout(() => reject(new Error("Inference provider was not reached")), 5000); timeout.unref(); })]);
    const read = await client.callTool({ name: "kelpie_browser_control", arguments: { request: { version: 1, method: "documentation" } } });
    assert.equal(read.isError, false);
    assert.equal((await rich("kelpie_ai_cancel")).isError, false);
    assert.equal((await inference).isError, true);
    console.log("Native nested common inference read and cancellation passed");
  } finally {
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  }
}
