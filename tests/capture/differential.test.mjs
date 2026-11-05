import test from "node:test";
import assert from "node:assert/strict";
import { assertDifferentialBundles, assertDifferentialObservations, SECRET_CANARIES } from "./assertions.mjs";
const fixture = (origin, documentId) => ({ origin, documentId });
function bundle(origin, documentId, ref) {
  const name = "document:" + documentId.slice(0, 8);
  return {
    snapshot: { url: origin + "/fixture?q=1", title: "Fixture", truncated: false,
      text: "url: " + origin + "/fixture?q=1\ntitle: Fixture\n[" + ref + "] p " + JSON.stringify(name),
      elements: [{ ref, role: "p", name }] },
    extraction: { url: origin + "/fixture?q=1", documentRevision: { availability: "unavailable" },
      fields: [{ name: "link", status: "ok", values: [origin + "/product#one"],
        provenance: { source: "href", selector: ".product", matches: 1, matchesLimited: false } }],
      metadata: [{ key: "url", value: origin + "/article", selector: "meta", attribute: "content",
        authority: "publisher-claim", provenanceComplete: true, index: 2 }], truncated: false },
    readiness: { ready: false, requestedState: "complete", documentState: "interactive", selector: "#task",
      matches: 1, visible: true, incomplete: false },
    status: { url: origin + "/fixture?q=1", network: { availability: "unavailable" }, errors: { availability: "unavailable" } },
    scope: "#products", inputGuarantee: "synthetic-coordinate",
  };
}
const options = { leftFixture: fixture("http://127.0.0.1:1234", "abc12345-left"),
  rightFixture: fixture("http://127.0.0.1:5678", "def12345-right") };
const pair = () => [bundle(options.leftFixture.origin, options.leftFixture.documentId, "opaque-a"),
  bundle(options.rightFixture.origin, options.rightFixture.documentId, "opaque-b")];
test("only declared fixture identities and typed URL slots normalize", () => {
  const [left, right] = pair();
  assertDifferentialBundles(left, right, options);
  assertDifferentialObservations(left.snapshot, right.snapshot, options);
  right.extraction.fields[0].values = ["http://127.0.0.1.evil:5678/product"];
  assert.throws(() => assertDifferentialBundles(left, right, options));
});
test("missing, ambiguity, scope, limits, provenance and readiness differences remain failures", () => {
  const mutations = [
    r => { r.extraction.fields[0].status = "ambiguous"; },
    r => { r.extraction.fields[0].status = "missing"; },
    r => { r.extraction.fields[0].provenance.matchesLimited = true; },
    r => { r.extraction.metadata[0].index = 1; },
    r => { r.extraction.metadata[0].provenanceComplete = false; },
    r => { r.extraction.truncated = true; },
    r => { r.readiness.incomplete = true; },
    r => { r.readiness.ready = true; },
    r => { r.scope = "body"; },
    r => { r.status.network = { availability: "available", pending: 0 }; },
  ];
  for (const mutate of mutations) { const [left, right] = pair(); mutate(right); assert.throws(() => assertDifferentialBundles(left, right, options)); }
});
test("ordinary document-like names, text, external URLs and extra semantic fields stay exact", () => {
  for (const [key, value] of [["title", "document:not-an-id"], ["text", "A changed text"]]) {
    const [left, right] = pair(); right.snapshot[key] = value;
    assert.throws(() => assertDifferentialBundles(left, right, options));
  }
  const absent = pair();
  delete absent[0].snapshot.elements; absent[1].snapshot.elements = [];
  assert.throws(() => assertDifferentialBundles(...absent, options), "Missing element evidence stays distinct from empty");
  const [left, right] = pair();
  left.extraction.fields[0].provenance.source = right.extraction.fields[0].provenance.source = "text";
  assert.throws(() => assertDifferentialBundles(left, right, options), "Origins in page text are not fixture URL slots");
  right.snapshot.extraMeaning = true;
  assert.throws(() => assertDifferentialBundles(left, right, options));
});
test("private values fail before normalization; input guarantees require an explicit retained pair", () => {
  for (const secret of SECRET_CANARIES) {
    const [left, right] = pair(); right.extraction.metadata[0].value = secret;
    assert.throws(() => assertDifferentialBundles(left, right, options));
  }
  const [left, right] = pair(); right.inputGuarantee = "trusted-coordinate";
  assert.throws(() => assertDifferentialBundles(left, right, options));
  assert.deepEqual(assertDifferentialBundles(left, right, { ...options,
    inputGuarantees: ["synthetic-coordinate", "trusted-coordinate"] }).inputGuarantees,
  ["synthetic-coordinate", "trusted-coordinate"]);
  assert.throws(() => assertDifferentialBundles(left, right, { ...options,
    inputGuarantees: ["trusted-coordinate", "synthetic-coordinate"] }));
});
