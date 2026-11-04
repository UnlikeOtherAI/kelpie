import { describe, expect, it } from "vitest";
import { scriptV1Schema, scriptArtifactRequestSchema, scriptTargetRequestSchema } from "../src/script-workflow.js";
import { bindScriptInputs } from "../src/script-bindings.js";
import { scriptPointerPosition, scriptTapPresentation } from "../src/script-presentation.js";

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
    expect(bindScriptInputs(raw, {}, () => "private").actions[0]).toMatchObject({ text: "private" });
    expect(() => bindScriptInputs({ ...raw, capture: { formats: ["video"] } }, {}, () => "private")).toThrow("Capture is unavailable");
  });
  it("bounds artifact reads and requires explicit identity for preflight", () => {
    expect(scriptArtifactRequestSchema.parse({ runId: "run", artifactId: "gif" })).toMatchObject({ offset: 0, length: 262144 });
    for (const length of [0, -1, 1.5, 1048577]) expect(scriptArtifactRequestSchema.safeParse({ runId: "r", artifactId: "a", length }).success).toBe(false);
    expect(scriptTargetRequestSchema.safeParse({ target: { x: 5, y: 10 }, key: "private", dispatch: true, edit: { action: "fill", text: "x" } }).success).toBe(false);
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
  it("wobbles then fades to zero on the common numeric timeline", () => {
    expect(scriptTapPresentation(0)).toEqual({ scale: 1, alpha: 1 });
    expect(scriptTapPresentation(1)).toEqual({ scale: 1, alpha: 0 });
    expect(scriptTapPresentation(0.1).scale).not.toBe(1);
    expect(scriptTapPresentation(0.5, false, false)).toEqual({ scale: 1, alpha: 1 });
  });
});
