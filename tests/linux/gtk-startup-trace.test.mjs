import test from "node:test";
import assert from "node:assert/strict";
import { parseGtkStartupTrace } from "./gtk-startup-trace.mjs";
const lines = names => names.map((name, index) => "KELPIE_GTK_STARTUP " + name + " " + (100 + index)).join("\n");
const prefix = ["GTK_INIT_ENTER", "GTK_INIT_RETURN", "SHOW_ENTER", "CANVAS_REALIZE", "ATTACH_ENTER", "START_ENTER"];
test("successful startup reports bounded ordered offsets without unrelated stderr", () => {
  const value = parseGtkStartupTrace("private diagnostic\n" + lines([...prefix, "START_OK", "PUBLISH_ENTER", "PUBLISH_RETURNED", "ATTACH_OK", "SHOW_RETURN"]));
  assert.equal(value.state, "valid-prefix");
  assert.equal(value.events.at(-1).elapsedNs, "10");
  assert.equal(JSON.stringify(value).includes("private diagnostic"), false);
});
test("prefix and startup failure remain distinct", () => {
  assert.equal(parseGtkStartupTrace(lines(prefix)).events.at(-1).name, "START_ENTER");
  assert.equal(parseGtkStartupTrace(lines([...prefix.slice(0, 5), "ATTACH_FAIL", "SHOW_RETURN"])).state, "valid-prefix");
  assert.equal(parseGtkStartupTrace(lines([...prefix, "START_OK", "PUBLISH_ENTER"])).events.at(-1).name, "PUBLISH_ENTER");
  assert.equal(parseGtkStartupTrace(lines([...prefix, "START_FAIL", "ATTACH_FAIL", "SHOW_RETURN"])).state, "valid-prefix");
  assert.equal(parseGtkStartupTrace(lines(["GTK_INIT_ENTER", "GTK_INIT_RETURN", "SHOW_ENTER", "SHOW_RETURN"])).state, "valid-prefix");
  assert.equal(parseGtkStartupTrace(lines(["GTK_INIT_ENTER", "GTK_INIT_RETURN", "SHOW_ENTER", "SHOW_RETURN", "CANVAS_REALIZE", "ATTACH_ENTER", "START_ENTER"])).state, "valid-prefix");
  assert.equal(parseGtkStartupTrace("nothing").state, "not-observed");
});
test("bad order, malformed markers and time reversal fail closed", () => {
  assert.equal(parseGtkStartupTrace(lines(["GTK_INIT_ENTER", "START_OK"])).state, "invalid");
  assert.equal(parseGtkStartupTrace("KELPIE_GTK_STARTUP GTK_INIT_ENTER 10\nKELPIE_GTK_STARTUP GTK_INIT_RETURN 9").state, "invalid");
  assert.equal(parseGtkStartupTrace("KELPIE_GTK_STARTUP GTK_INIT_ENTER secret").state, "invalid");
  assert.equal(parseGtkStartupTrace(lines(Array(33).fill("GTK_INIT_ENTER"))).state, "invalid");
});

test("engine and optional service stages remain ordered for either mDNS path", () => {
  const engine = [...prefix, "ENGINE_ENTER", "CEF_INIT_ENTER", "CEF_INIT_OK",
    "FIRST_BROWSER_ENTER", "FIRST_BROWSER_OK", "ENGINE_OK", "HANDLERS_ENTER",
    "HANDLERS_RETURN", "LISTENER_ENTER", "LISTENER_OK"];
  for (const mdns of [["MDNS_SKIPPED"], ["MDNS_ENTER", "MDNS_RETURN"]]) {
    const events = [...engine, ...mdns, "START_OK", "PUBLISH_ENTER", "PUBLISH_RETURNED", "ATTACH_OK", "SHOW_RETURN"];
    assert.ok(events.length <= 32);
    assert.equal(parseGtkStartupTrace(lines(events)).state, "valid-prefix");
  }
});
test("substage failure and interrupted cleanup remain honest prefixes", () => {
  const base = [...prefix, "ENGINE_ENTER", "CEF_INIT_ENTER"];
  assert.equal(parseGtkStartupTrace(lines(base)).events.at(-1).name, "CEF_INIT_ENTER");
  assert.equal(parseGtkStartupTrace(lines([...base, "CEF_INIT_FAIL", "ENGINE_FAIL", "START_FAIL", "ATTACH_FAIL", "SHOW_RETURN"])).state, "valid-prefix");
  const listener = [...base, "CEF_INIT_OK", "FIRST_BROWSER_ENTER", "FIRST_BROWSER_OK", "ENGINE_OK",
    "HANDLERS_ENTER", "HANDLERS_RETURN", "LISTENER_ENTER", "LISTENER_FAIL"];
  assert.equal(parseGtkStartupTrace(lines(listener)).events.at(-1).name, "LISTENER_FAIL");
  assert.equal(parseGtkStartupTrace(lines([...listener, "START_FAIL", "ATTACH_FAIL"])).state, "valid-prefix");
  assert.equal(parseGtkStartupTrace(lines([...base, "FIRST_BROWSER_OK"])).state, "invalid");
});

test("headless mode accepts only its engine-first startup sequence", () => {
  const headless = ["START_ENTER", "ENGINE_ENTER", "CEF_INIT_ENTER", "CEF_INIT_OK",
    "FIRST_BROWSER_ENTER", "FIRST_BROWSER_OK", "ENGINE_OK", "HANDLERS_ENTER",
    "HANDLERS_RETURN", "LISTENER_ENTER", "LISTENER_OK", "MDNS_SKIPPED",
    "START_OK", "PUBLISH_ENTER", "PUBLISH_RETURNED"];
  assert.equal(parseGtkStartupTrace(lines(headless), "headless").state, "valid-prefix");
  assert.equal(parseGtkStartupTrace(lines(headless.slice(0, 5)), "headless").events.at(-1).name, "FIRST_BROWSER_ENTER");
  assert.equal(parseGtkStartupTrace(lines(headless), "windowed").state, "invalid");
  assert.equal(parseGtkStartupTrace(lines(["START_ENTER", "ATTACH_ENTER"]), "headless").state, "invalid");
  assert.equal(parseGtkStartupTrace(lines(["START_ENTER", "START_OK"]), "headless").state, "invalid");
  assert.equal(parseGtkStartupTrace(lines(headless), "other").state, "invalid");
});
