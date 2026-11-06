import test from "node:test";
import assert from "node:assert/strict";
import { parseGtkStartupTrace } from "./gtk-startup-trace.mjs";
import { parseGtkStartupAux } from "./gtk-startup-aux.mjs";
const names = ["GTK_INIT_ENTER", "GTK_INIT_RETURN", "SHOW_ENTER", "CANVAS_REALIZE", "ATTACH_ENTER",
  "START_ENTER", "ENGINE_ENTER", "CEF_INIT_ENTER", "CEF_INIT_OK", "FIRST_BROWSER_ENTER"];
const core = names.map((name, index) => "KELPIE_GTK_STARTUP " + name + " " + (100 + index));
const parse = (text, truncated = false, pid = 42) =>
  parseGtkStartupAux(text, parseGtkStartupTrace(text), truncated, pid);
test("auxiliary callbacks interleave and bind to the pinned PID and browser entry", () => {
  const text = [...core.slice(0, 8), "KELPIE_GTK_AUX CONTEXT_INITIALIZED 42 107",
    "KELPIE_GTK_AUX SCHEDULE_FIRST 42 104", ...core.slice(8),
    "KELPIE_GTK_AUX GTK_PUMP_FIRST 42 110"].join("\n");
  const aux = parse(text);
  assert.equal(aux.state, "observed");
  assert.equal(aux.pid, 42);
  assert.deepEqual(aux.events.map(event => event.relativeToFirstBrowserNs), ["-2", "-5", "1"]);
});
test("first matching callback pair records actual UI-thread classification", () => {
  const text = core.join("\n") + "\nKELPIE_GTK_AUX AFTER_CREATED_ENTER_UI 42 110\nKELPIE_GTK_AUX AFTER_CREATED_RETURN_UI 42 115";
  const aux = parse(text);
  assert.equal(aux.state, "observed");
  assert.deepEqual(aux.events.map(event => event.name), ["AFTER_CREATED_ENTER_UI", "AFTER_CREATED_RETURN_UI"]);
  assert.deepEqual(aux.events.map(event => event.relativeToFirstBrowserNs), ["1", "6"]);
  const other = core.join("\n") + "\nKELPIE_GTK_AUX AFTER_CREATED_ENTER_OTHER 42 110";
  assert.equal(parse(other).events[0].name, "AFTER_CREATED_ENTER_OTHER");
});
test("missing anchor or auxiliary markers do not infer callback absence", () => {
  const text = core.slice(0, 5).join("\n") + "\nKELPIE_GTK_AUX SCHEDULE_FIRST 42 104";
  assert.equal(parse(text).events[0].relativeToFirstBrowserNs, null);
  assert.equal(parse(core.join("\n")).state, "not-observed");
});
test("wrong PID, duplicates, malformed or unpaired records fail closed", () => {
  const c = core.join("\n") + "\n";
  assert.equal(parse(c + "KELPIE_GTK_AUX SCHEDULE_FIRST 41 1").state, "invalid");
  assert.equal(parse(c + "KELPIE_GTK_AUX SCHEDULE_FIRST 42 1\nKELPIE_GTK_AUX SCHEDULE_FIRST 42 2").state, "invalid");
  assert.equal(parse(c + "KELPIE_GTK_AUX UNKNOWN 42 1").state, "invalid");
  assert.equal(parse(c + "KELPIE_GTK_AUX CONTEXT_INITIALIZED 42 secret").state, "invalid");
  assert.equal(parse(c + "KELPIE_GTK_AUX AFTER_CREATED_RETURN_UI 42 115").state, "invalid");
  assert.equal(parse(c + "KELPIE_GTK_AUX AFTER_CREATED_ENTER_UI 42 115\nKELPIE_GTK_AUX AFTER_CREATED_RETURN_UI 42 110").state, "invalid");
  assert.equal(parse(c + "KELPIE_GTK_AUX AFTER_CREATED_ENTER_UI 42 110\nKELPIE_GTK_AUX AFTER_CREATED_ENTER_OTHER 42 111").state, "invalid");
  assert.equal(parse(c, false, null).state, "invalid");
});
test("truncated or invalid core evidence is incomplete", () => {
  const text = core.join("\n") + "\nKELPIE_GTK_AUX SCHEDULE_FIRST 42 104";
  const startup = parseGtkStartupTrace(text);
  assert.equal(parseGtkStartupAux(text, startup, true, 42).state, "incomplete");
  assert.equal(parseGtkStartupAux(text, { state: "invalid" }, false, 42).state, "incomplete");
  assert.equal(parseGtkStartupAux(text, startup, undefined, 42).state, "invalid");
});
