import assert from "node:assert/strict";

function fixtureURL(value, fixture) {
  if (!fixture.origin || typeof value !== "string") return value;
  try {
    const origin = new URL(fixture.origin);
    assert.equal(origin.href, origin.origin + "/", "Fixture origin must be exact");
    const url = new URL(value);
    return url.origin === origin.origin ? "<fixture-origin>" + url.pathname + url.search + url.hash : value;
  } catch { return value; }
}
const markerName = (name, fixture) => fixture.documentId &&
  name === "document:" + fixture.documentId.slice(0, 8) ? "document:<fixture-generation>" : name;
export function normalizeSnapshot(snapshot, fixture = {}) {
  const refs = new Map();
  const elements = (snapshot.elements ?? []).map((item, index) => {
    assert.equal(typeof item.ref, "string", "Snapshot needs actual refs");
    assert.ok(!refs.has(item.ref), "Duplicate snapshot ref");
    const ref = "element:" + (index + 1);
    refs.set(item.ref, { ref, item });
    return { ...item, ref, name: markerName(item.name, fixture) };
  });
  const text = snapshot.text.split("\n").map((line, index) => {
    if (index === 0 && line === "url: " + snapshot.url) return "url: " + fixtureURL(snapshot.url, fixture);
    const close = line.indexOf("] ");
    if (!line.startsWith("[") || close < 0) return line;
    const match = refs.get(line.slice(1, close));
    if (!match) return line;
    const { item, ref } = match;
    const exact = "[" + item.ref + "] " + item.role + " " + JSON.stringify(item.name);
    return line === exact ? "[" + ref + "] " + item.role + " " + JSON.stringify(markerName(item.name, fixture))
      : "[" + ref + "] " + line.slice(close + 2);
  }).join("\n");
  return { ...snapshot, url: fixtureURL(snapshot.url, fixture), text,
    ...(snapshot.elements === undefined ? {} : { elements }) };
}
function field(value, fixture, depth = 0) {
  assert.ok(depth <= 3, "Extraction nesting exceeds canonical bound");
  const result = { ...value };
  if (["href", "src"].includes(value.provenance?.source))
    result.values = value.values.map(item => fixtureURL(item, fixture));
  if (value.records) result.records = value.records.map(record => record.map(item => field(item, fixture, depth + 1)));
  return result;
}
export function normalizeObservationBundle(bundle, fixture = {}) {
  const result = { ...bundle };
  if (bundle.snapshot) result.snapshot = normalizeSnapshot(bundle.snapshot, fixture);
  if (bundle.extraction) result.extraction = {
    ...bundle.extraction, url: fixtureURL(bundle.extraction.url, fixture),
    fields: bundle.extraction.fields.map(item => field(item, fixture)),
    metadata: bundle.extraction.metadata.map(item => ["url", "image", "logo", "sameAs"].includes(item.key)
      ? { ...item, value: fixtureURL(item.value, fixture) } : item),
  };
  if (bundle.status) result.status = { ...bundle.status, url: fixtureURL(bundle.status.url, fixture) };
  // Readiness, scopes, provenance, errors/network availability and extra fields
  // remain exact. Layout differences require a documented separate fixture case.
  return result;
}
