import { scriptV1Schema, type ScriptV1 } from "./script-workflow.js";

/** Binds declared inputs once before admission. Does not execute a second workflow runtime. */
export function bindScriptInputs(
  raw: unknown,
  values: Record<string, unknown> = {},
  resolveSecret?: (reference: string) => string | undefined,
): ScriptV1 {
  const script = scriptV1Schema.parse(raw);
  const declarations = script.inputs ?? {};
  const outputNames = new Set<string>();
  for (const step of script.actions) {
    if (step.action !== "output" && step.action !== "extract") continue;
    if (outputNames.has(step.name)) throw new Error("Duplicate workflow output name");
    outputNames.add(step.name);
  }
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
  const hasCapture = script.capture !== undefined || script.actions.some(action => action.action === "screenshot");
  if (hasCapture && script.actions.some(action => "sensitive" in action && action.sensitive)) throw new Error("Capture is unavailable for secret-bearing workflows");
  const actions = script.actions.map(step => {
    if (!("text" in step) || typeof step.text === "string") return step;
    let text: string;
    let sensitive = "sensitive" in step ? step.sensitive : undefined;
    if ("input" in step.text) {
      const key = step.text.input;
      if (!Object.hasOwn(declarations, key) || values[key] === undefined) throw new Error("Workflow input unavailable");
      const value = values[key];
      if (typeof value !== "string" && typeof value !== "number" && typeof value !== "boolean") throw new Error("Workflow input type mismatch");
      text = String(value);
    } else {
      // Media and on-screen typing could disclose secrets. No implicit recording opt-in.
      if (hasCapture) throw new Error("Capture is unavailable for secret-bearing workflows");
      let value: string | undefined;
      try { value = resolveSecret?.(step.text.secret); } catch { throw new Error("Workflow secret unavailable"); }
      if (value === undefined) throw new Error("Workflow secret unavailable");
      text = value;
      sensitive = true;
    }
    if (text.length > 16_000) throw new Error("Workflow value exceeds limit");
    return { ...step, text, ...(sensitive ? { sensitive: true } : {}) };
  });
  return { ...script, inputs: undefined, actions };
}
