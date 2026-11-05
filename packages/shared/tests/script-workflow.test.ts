import { readFile } from "node:fs/promises";
import { describe, expect, it } from "vitest";
import { scriptV1Schema, scriptArtifactRequestSchema, scriptTargetRequestSchema } from "../src/script-workflow.js";
import { bindScriptInputs } from "../src/script-bindings.js";
import { scriptPointerPosition, scriptTapPresentation, scriptTimelineProgress } from "../src/script-presentation.js";

const script = { version: 1, tabId: "owned-tab", actions: [{ action: "click", target: { role: "button", name: "Submit" } }] };
describe("strict authored workflows", () => {
  it("validates semantic targets and bounded capture without admitting arbitrary evaluation", () => {
    expect(scriptV1Schema.parse(script).actions[0]).toEqual({ action: "click", target: { role: "button", name: "Submit", exact: true } });
    expect(scriptV1Schema.safeParse({ ...script, actions: [{ action: "evaluate", expression: "secret()" }] }).success).toBe(false);
    expect(scriptV1Schema.safeParse({ ...script, actions: [{ action: "click", target: { role: "button", name: "Submit", selector: "*" } }] }).success).toBe(false);
    expect(scriptV1Schema.safeParse({ ...script, continueOnError: true }).success).toBe(false);
    expect(scriptV1Schema.safeParse({ ...script, capture: { formats: ["gif"], fps: 31 } }).success).toBe(false);
    expect(scriptV1Schema.safeParse({ ...script, capture: { formats: ["gif", "gif"] } }).success).toBe(false);
  });
  it("admits only bounded opt-in paced timing on fill and type", () => {
    for (const action of ["fill", "type"]) {
      const step = { action, target: { selector: "#edit" }, text: "A😀é", typingDelayMs: 50 };
      expect(scriptV1Schema.safeParse({ ...script, actions: [step] }).success).toBe(true);
      for (const invalid of [0, 1001, 1.5]) {
        expect(scriptV1Schema.safeParse({ ...script, actions: [{ ...step, typingDelayMs: invalid }] }).success).toBe(false);
      }
    }
    expect(scriptV1Schema.safeParse({ ...script, actions: [{ action: "click", target: { selector: "#edit" }, typingDelayMs: 50 }] }).success).toBe(false);
  });
  it("uses a faster pointer default while preserving explicit durations", () => {
    const pointer = scriptV1Schema.parse({ ...script, pointer: { enabled: true } }).pointer!;
    expect(pointer).toEqual({ enabled: true, curve: "s", durationMs: 350, easing: "ease-in-out" });
    for (const durationMs of [0, 500, 2400]) {
      expect(scriptV1Schema.parse({ ...script, pointer: { enabled: true, curve: "c", durationMs } }).pointer)
        .toMatchObject({ curve: "c", durationMs });
    }
    const motion = { from: { x: 0, y: 0 }, to: { x: 300, y: 0 }, curve: pointer.curve };
    expect(scriptPointerPosition(motion, scriptTimelineProgress(0, pointer.durationMs))).toEqual(motion.from);
    expect(scriptPointerPosition(motion, scriptTimelineProgress(350, pointer.durationMs))).toEqual(motion.to);
    expect(scriptPointerPosition(motion, scriptTimelineProgress(175, pointer.durationMs)).x).toBeCloseTo(150);
  });
  it("binds declared values once and rejects missing, undeclared and incorrectly typed inputs", () => {
    const raw = { ...script, inputs: { user: { type: "string" } }, actions: [{ action: "fill", target: { label: "Name" }, text: { input: "user" } }] };
    expect(bindScriptInputs(raw, { user: "Ada" }).actions[0]).toMatchObject({ text: "Ada" });
    expect(() => bindScriptInputs(raw)).toThrow("Required workflow input missing");
    expect(() => bindScriptInputs(raw, { user: 42 })).toThrow("Workflow input type mismatch");
    expect(() => bindScriptInputs(raw, { user: "Ada", extra: 1 })).toThrow("Undeclared workflow input");
  });
  it("resolves secrets only through the host callback and refuses secret capture", () => {
    const raw = { ...script, actions: [{ action: "fill", target: { label: "Password" }, text: { secret: "account-password" } }] };
    expect(() => bindScriptInputs(raw)).toThrow("Workflow secret unavailable");
    expect(() => bindScriptInputs(raw, {}, () => { throw new Error("private provider diagnostic"); })).toThrow("Workflow secret unavailable");
    expect(bindScriptInputs(raw, {}, () => "private").actions[0]).toMatchObject({ text: "private" });
    expect(() => bindScriptInputs({ ...raw, capture: { formats: ["video"] } }, {}, () => "private")).toThrow("Capture is unavailable");
    expect(() => bindScriptInputs({ ...raw, actions: [...raw.actions, { action: "screenshot" }] }, {}, () => "private")).toThrow("Capture is unavailable");
  });
  it("bounds artifact reads and requires explicit identity for preflight", () => {
    expect(scriptArtifactRequestSchema.parse({ runId: "run", artifactId: "gif" })).toMatchObject({ offset: 0, length: 262144 });
    for (const length of [0, -1, 1.5, 1048577]) expect(scriptArtifactRequestSchema.safeParse({ runId: "r", artifactId: "a", length }).success).toBe(false);
    expect(scriptTargetRequestSchema.safeParse({ target: { x: 5, y: 10 }, key: "private", dispatch: true, edit: { action: "fill", text: "x" } }).success).toBe(false);
    const post = { target: { selector: "#edit" }, key: "private", token: "t1", postMutation: true };
    expect(scriptTargetRequestSchema.safeParse(post).success).toBe(true);
    expect(scriptTargetRequestSchema.safeParse({ ...post, token: undefined }).success).toBe(false);
    const brand = { target: { selector: "#link" }, key: "private", token: "t1", proveNonInput: true };
    expect(scriptTargetRequestSchema.safeParse(brand).success).toBe(true);
    expect(scriptTargetRequestSchema.safeParse({ ...brand, token: undefined }).success).toBe(false);
    expect(scriptTargetRequestSchema.safeParse({ ...brand, dispatch: true }).success).toBe(false);
    expect(scriptTargetRequestSchema.safeParse({ ...post, dispatch: true }).success).toBe(false);
    expect(scriptTargetRequestSchema.safeParse({ ...post, observe: true }).success).toBe(false);
    expect(scriptTargetRequestSchema.safeParse({ ...post, edit: { action: "fill", text: "x" } }).success).toBe(false);
  });
});
describe("deterministic presentation", () => {
  it("preserves endpoints, distinct C/S curvature and eased endpoint velocity", () => {
    const motion = { from: { x: 0, y: 0 }, to: { x: 300, y: 0 }, curve: "c" as const };
    expect(scriptPointerPosition(motion, 0)).toEqual(motion.from);
    expect(scriptPointerPosition(motion, 1)).toEqual(motion.to);
    expect(scriptPointerPosition(motion, 0.5).y).toBeGreaterThan(0);
    expect(scriptPointerPosition({ ...motion, curve: "s" }, 0.5).y).toBeCloseTo(0);
    expect(scriptPointerPosition(motion, 0.001).x).toBeLessThan(0.01);
    expect(scriptPointerPosition(motion, -1)).toEqual(motion.from);
  });
  it("handles zero-duration and invalid timeline progress safely", () => {
    expect(scriptTimelineProgress(0, 0)).toBe(1);
    expect(scriptTimelineProgress(-10, 100)).toBe(0);
    expect(scriptTimelineProgress(50, 100)).toBe(0.5);
    expect(scriptTimelineProgress(200, 100)).toBe(1);
    expect(scriptTimelineProgress(Number.NaN, 100)).toBe(0);
    expect(scriptTimelineProgress(1, Number.NaN)).toBe(0);
    expect(scriptTapPresentation(Number.NaN)).toEqual({ scale: 1, alpha: 1 });
  });
  it("accepts extraction through the canonical bounded schema", () => {
    expect(scriptV1Schema.parse({ ...script, actions: [{ action: "extract", name: "cards", params: { fields: [{ name: "title", selector: "h2", source: "text" }], metadata: true } }] }).actions[0]).toMatchObject({ action: "extract", name: "cards" });
    expect(scriptV1Schema.safeParse({ ...script, actions: [{ action: "extract", name: "bad", params: { fields: [{ name: "value", selector: "input", source: "value" }] } }] }).success).toBe(false);
  });
  it("wobbles then fades to zero on the common numeric timeline", () => {
    expect(scriptTapPresentation(0)).toEqual({ scale: 1, alpha: 1 });
    expect(scriptTapPresentation(1)).toEqual({ scale: 1, alpha: 0 });
    expect(scriptTapPresentation(0.1).scale).not.toBe(1);
    expect(scriptTapPresentation(0.5, false, false)).toEqual({ scale: 1, alpha: 1 });
  });
});

describe("reusable workflow authoring", () => {
  it("refuses duplicate named outputs before executing any actions", () => {
    expect(() => bindScriptInputs({ ...script, actions: [
      { action: "output", name: "same", source: "url" },
      { action: "extract", name: "same", params: { fields: [{ name: "title", selector: "h1", source: "text" }] } },
    ] })).toThrow("Duplicate workflow output name");
  });
  it("validates the shipped walkthrough and nested-extraction recipes", async () => {
    for (const name of ["submit-walkthrough", "extract-products", "paced-fill"]) {
      const raw: unknown = JSON.parse(await readFile(new URL("../../../docs/examples/workflows/" + name + ".json", import.meta.url), "utf8"));
      const parsed = scriptV1Schema.parse(raw);
      expect(bindScriptInputs(parsed, parsed.inputs ? { name: "Ada" } : {}).version).toBe(1);
    }
  });
});