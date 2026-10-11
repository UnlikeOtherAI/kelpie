import assert from "node:assert/strict";
import { bearerHeaders, control, rawRequest, resultValue } from "./http.mjs";

/** Shared HTTP fixture also runs against Linux CEF; only private renderer/native routes can satisfy it. */
export async function runCanonicalAcceptance(readiness, fixtureUrl) {
  const call = async (method, params = {}, tabId) => {
    const response = await rawRequest({ port: readiness.port, path: "/v1/browser-control", headers: bearerHeaders(readiness.token), body: JSON.stringify({ version: 1, method, params, ...(tabId ? { tabId } : {}) }) });
    assert.equal(response.status, 200);
    assert.equal(response.json.version, 1);
    return response.json;
  };
  const caps = await call("capabilities");
  assert.ok(caps.value.methods.includes("tab.snapshot"));
  const created = await call("tabs.new", { url: fixtureUrl });
  assert.equal(created.ok, true);
  const tab = created.value.id;
  const evaluate = async (expression) => resultValue(await control(readiness, "evaluate", { tabId: tab, expression }));
  await evaluate('document.querySelector("#text-input").value="INITIAL_SECRET"; document.body.insertAdjacentHTML("beforeend", \'<input type="password" value="PASSWORD_SECRET"><textarea>TEXTAREA_SECRET</textarea><div contenteditable="true"><p>EDITOR_SECRET</p></div>\'); true');
  const snapshot = await call("tab.snapshot", { maxChars: 12000 }, tab);
  assert.equal(snapshot.ok, true);
  for (const secret of ["INITIAL_SECRET", "PASSWORD_SECRET", "TEXTAREA_SECRET", "EDITOR_SECRET"]) assert.ok(!JSON.stringify(snapshot.value).includes(secret));
  // Observe first, then prove a page-world expression cannot enumerate the live registry.
  assert.equal(await evaluate('Object.getOwnPropertyNames(window).some(key=>key.startsWith("__kelpie_"))'), false);
  const refreshed = await call("tab.snapshot", {}, tab);
  const input = refreshed.value.elements.find(el => el.name === "Fixture text");
  assert.ok(input);
  const typed = await call("tab.type", { ref: input.ref, text: "!" }, tab);
  assert.equal(typed.ok, true);
  assert.equal(await evaluate('document.querySelector("#text-input").value'), "INITIAL_SECRET!");
  assert.equal((await call("tab.type", { ref: input.ref, text: "DUPLICATE" }, tab)).error.code, "STALE_REFERENCE");
  await evaluate('setTimeout(()=>{const node=document.querySelector("#trusted-button");node.replaceWith(node.cloneNode(true));},1000);true');
  const fresh = await call("tab.snapshot", {}, tab);
  const button = fresh.value.elements.find(el => el.name === "Trusted action");
  assert.ok(button);
  // A replacement before dispatch refuses; actions no longer re-query a copied selector.
  await new Promise(resolve => setTimeout(resolve, 1200));
  assert.equal((await call("tab.click", { ref: button.ref }, tab)).error.code, "STALE_REFERENCE");
  assert.equal((await call("tab.screenshot", { fullPage: true }, tab)).error.code, "UNSUPPORTED");
  const final = await call("tab.snapshot", { maxChars: 256 }, tab);
  assert.ok(final.value.text.length <= 256);
  const image = await call("tab.screenshot", {}, tab);
  assert.equal(image.value.type, "image");
  const measured = { snapshotBytes: Buffer.byteLength(JSON.stringify(snapshot.value)), referenceChars: input.ref.length };
  console.log("Canonical native browser fixture passed", measured);
  assert.equal((await call("tabs.close", {}, tab)).ok, true);
  return measured;
}
