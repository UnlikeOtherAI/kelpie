import { scriptV1Schema, type ScriptV1 } from "./script-workflow.js";

/** Binds declared inputs once before admission. Does not execute a second workflow runtime. */
export function bindScriptInputs(
  raw: unknown,
  values: Record<string, unknown> = {},
  resolveSecret?: (reference: string) => string | undefined,
): ScriptV1 {
  const script = scriptV1Schema.parse(raw);
  const declarations = script.inputs ?? {};
  for (const key of Object.keys(values)) {
    if (!Object.hasOwn(declarations, key)) throw new Error("Undeclared workflow input");
  }
  for (const [key, spec] of Object.entries(declarations)) {
    const value = values[key];
    if (value === undefined) {
      if (spec.required) throw new Error("Required workflow input missing");
    } else if (typeof value !== spec.type || (typeof value === "number" && !Number.isFinite(value))) {
      throw new Error("Workflow input type mismatch");
    }
  }
  const actions = script.actions.map(step => {
    if (!("text" in step) || typeof step.text === "string") return step;
    let text: string;
    if ("input" in step.text) {
      const key = step.text.input;
      if (!Object.hasOwn(declarations, key) || values[key] === undefined) throw new Error("Workflow input unavailable");
      const value = values[key];
      if (typeof value !== "string" && typeof value !== "number" && typeof value !== "boolean") throw new Error("Workflow input type mismatch");
      text = String(value);
    } else {
      // Media and on-screen typing could disclose secrets. No implicit recording opt-in.
      if (script.capture) throw new Error("Capture is unavailable for secret-bearing workflows");
      const value = resolveSecret?.(step.text.secret);
      if (value === undefined) throw new Error("Workflow secret unavailable");
      text = value;
    }
    if (text.length > 16_000) throw new Error("Workflow value exceeds limit");
    return { ...step, text };
  });
  return { ...script, inputs: undefined, actions };
}
