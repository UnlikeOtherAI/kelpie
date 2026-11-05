import { describe, expect, it } from "vitest";
import { scriptStatusV1Schema } from "../src/script-status.js";
describe("native v1 status contract", () => {
  const base = { success: true, supportedVersions: [1], playing: false };
  it("distinguishes query success from failed terminal runs and preserves partial artifacts", () => {
    const terminal = { ...base, state: "failed", runId: "r", runSuccess: false,
      runError: { code: "SCRIPT_STOPPED", message: "Script stopped before confirmed completion" },
      artifacts: [{ id: "a", mimeType: "image/png", byteLength: 10, sha256: "a".repeat(64),
        partial: true, width: 10, height: 10 }] };
    expect(scriptStatusV1Schema.parse(terminal)).toEqual(terminal);
    expect(scriptStatusV1Schema.safeParse({ ...terminal, error: terminal.runError }).success).toBe(false);
    expect(scriptStatusV1Schema.safeParse({ ...terminal, outputs: { private: "value" } }).success).toBe(false);
  });
  it("allows bounded forward compatible unique versions including one", () => {
    expect(scriptStatusV1Schema.safeParse({ ...base, state: "idle", supportedVersions: [1, 2] }).success).toBe(true);
    for (const supportedVersions of [[2], [1, 1], [0, 1], Array.from({ length: 17 }, (_, n) => n + 1)])
      expect(scriptStatusV1Schema.safeParse({ ...base, state: "idle", supportedVersions }).success).toBe(false);
  });
  it("requires run identity and consistent playing/state/terminal success", () => {
    for (const state of ["running", "finalizing"])
      expect(scriptStatusV1Schema.safeParse({ ...base, state, playing: true, runId: "r" }).success).toBe(true);
    for (const state of ["completed", "failed", "aborted"]) {
      const valid = { ...base, state, runId: "r", runSuccess: state === "completed" };
      expect(scriptStatusV1Schema.safeParse(valid).success).toBe(true);
      expect(scriptStatusV1Schema.safeParse({ ...valid, playing: true }).success).toBe(false);
      expect(scriptStatusV1Schema.safeParse({ ...valid, runId: undefined }).success).toBe(false);
      expect(scriptStatusV1Schema.safeParse({ ...valid, runSuccess: undefined }).success).toBe(false);
    }
    expect(scriptStatusV1Schema.safeParse({ ...base, state: "running", playing: true }).success).toBe(false);
    expect(scriptStatusV1Schema.safeParse({ ...base, state: "idle", playing: true }).success).toBe(false);
  });
});
