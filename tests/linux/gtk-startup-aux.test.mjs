import test from "node:test";
import assert from "node:assert/strict";
import { parseGtkStartupTrace } from "./gtk-startup-trace.mjs";
import { parseGtkStartupAux } from "./gtk-startup-aux.mjs";
const names = ["GTK_INIT_ENTER", "GTK_INIT_RETURN", "SHOW_ENTER", "CANVAS_REALIZE", "ATTACH_ENTER",
  "START_ENTER", "ENGINE_ENTER", "CEF_INIT_ENTER", "CEF_INIT_OK", "FIRST_BROWSER_ENTER"];
const core = names.map((name, index) => "KELPIE_GTK_STARTUP " + name + " " + (100 + index));
test("auxiliary callbacks can interleave independently and correlate to browser entry", () => {
  const lines = [...core.slice(0, 8), "KELPIE_GTK_AUX CONTEXT_INITIALIZED 107",
    "KELPIE_GTK_AUX SCHEDULE_FIRST 104", ...core.slice(8),
    "KELPIE_GTK_AUX GTK_PUMP_FIRST 110"];
  const text = lines.join("\n"), startup = parseGtkStartupTrace(text);
  assert.equal(startup.state, "valid-prefix");
  const aux = parseGtkStartupAux(text, startup, false);
  assert.equal(aux.state, "observed");
  assert.deepEqual(aux.events.map(event => event.relativeToFirstBrowserNs), ["-2", "-5", "1"]);
});
test("missing anchor or absent auxiliary markers do not infer callback absence", () => {
  const text = core.slice(0, 5).join("\n") + "\nKELPIE_GTK_AUX SCHEDULE_FIRST 104";
  const aux = parseGtkStartupAux(text, parseGtkStartupTrace(text), false);
  assert.equal(aux.events[0].relativeToFirstBrowserNs, null);
  assert.equal(parseGtkStartupAux(core.join("\n"), parseGtkStartupTrace(core.join("\n")), false).state, "not-observed");
});
test("duplicates, unknown and malformed markers fail closed; truncation stays incomplete", () => {
  const startup = parseGtkStartupTrace(core.join("\n"));
  assert.equal(parseGtkStartupAux("KELPIE_GTK_AUX SCHEDULE_FIRST 1\nKELPIE_GTK_AUX SCHEDULE_FIRST 2", startup, false).state, "invalid");
  assert.equal(parseGtkStartupAux("KELPIE_GTK_AUX UNKNOWN 1", startup, false).state, "invalid");
  assert.equal(parseGtkStartupAux("KELPIE_GTK_AUX CONTEXT_INITIALIZED secret", startup, false).state, "invalid");
  assert.equal(parseGtkStartupAux(core.join("\n"), startup, true).state, "incomplete");
  assert.equal(parseGtkStartupAux("KELPIE_GTK_AUX SCHEDULE_FIRST 1", startup, true).state, "incomplete");
  assert.equal(parseGtkStartupAux("KELPIE_GTK_AUX SCHEDULE_FIRST 1", { state: "invalid" }, false).state, "incomplete");
  assert.equal(parseGtkStartupAux("", startup).state, "invalid");
});
