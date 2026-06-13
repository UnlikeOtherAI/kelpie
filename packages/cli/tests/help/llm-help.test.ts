import { describe, it, expect } from "vitest";
import { generateLlmHelp } from "../../src/help/llm-help.js";

describe("generateLlmHelp", () => {
  it("returns valid JSON for all commands", () => {
    const output = generateLlmHelp();
    const parsed = JSON.parse(output);
    expect(Array.isArray(parsed)).toBe(true);
    expect(parsed.length).toBe(151);
  });

  it("each command entry has required fields", () => {
    const parsed = JSON.parse(generateLlmHelp());
    for (const entry of parsed) {
      expect(entry).toHaveProperty("command");
      expect(entry).toHaveProperty("purpose");
      expect(entry).toHaveProperty("params");
      expect(typeof entry.command).toBe("string");
      expect(typeof entry.purpose).toBe("string");
      expect(Array.isArray(entry.params)).toBe(true);
    }
  });

  it("returns help for a specific command", () => {
    const output = generateLlmHelp("navigate");
    const parsed = JSON.parse(output);
    expect(parsed.command).toBe("navigate");
    expect(parsed.purpose).toContain("Navigate");
    expect(parsed.params.some((p: { name: string }) => p.name === "url")).toBe(true);
    expect(parsed.params.some((p: { name: string }) => p.name === "device")).toBe(true);
  });

  it("returns help for click with errors and related", () => {
    const output = generateLlmHelp("click");
    const parsed = JSON.parse(output);
    expect(parsed.command).toBe("click");
    expect(parsed.errors).toContainEqual(
      expect.objectContaining({
        code: "ELEMENT_NOT_FOUND",
      }),
    );
    expect(parsed.related).toContain("tap");
  });

  it("includes platform, defaults, enum values, and response metadata", () => {
    const output = generateLlmHelp("screenshot");
    const parsed = JSON.parse(output);
    expect(parsed.platforms).toContain("ios");
    const resolutionParam = parsed.params.find((p: { name: string }) => p.name === "resolution");
    expect(resolutionParam?.values).toEqual(["native", "viewport"]);
    expect(resolutionParam?.default).toBe("viewport");
    expect(parsed.response).toContainEqual(
      expect.objectContaining({
        name: "devicePixelRatio",
      }),
    );
  });

  it("describes nested request shapes for complex commands", () => {
    const output = generateLlmHelp("set-request-interception");
    const parsed = JSON.parse(output);
    const rulesParam = parsed.params.find((p: { name: string }) => p.name === "rules");
    expect(rulesParam?.type).toBe("array");
    expect(rulesParam?.items?.type).toBe("object");
    expect(rulesParam?.items?.fields).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ name: "pattern", type: "string" }),
        expect.objectContaining({ name: "action", type: "enum" }),
      ]),
    );
  });

  it("returns help for report-issue with structured diagnostics", () => {
    const output = generateLlmHelp("report-issue");
    const parsed = JSON.parse(output);
    expect(parsed.command).toBe("report-issue");
    const diagnosticsParam = parsed.params.find((p: { name: string }) => p.name === "diagnostics");
    expect(diagnosticsParam?.type).toBe("record");
    expect(parsed.response).toContainEqual(
      expect.objectContaining({
        name: "reportId",
      }),
    );
  });

  it("describes new-tab returning a reusable tabId", () => {
    const output = generateLlmHelp("tab new");
    const parsed = JSON.parse(output);
    expect(parsed.command).toBe("tab new");
    expect(parsed.explanation).toContain("tabId");
    expect(parsed.response).toContainEqual(
      expect.objectContaining({
        name: "tabId",
      }),
    );
  });

  it("marks tap as a last-resort command", () => {
    const output = generateLlmHelp("tap");
    const parsed = JSON.parse(output);
    expect(parsed.when.toLowerCase()).toContain("last-resort");
    expect(parsed.explanation).toContain("Prefer click");
  });

  it("presents accessibility tree as the preferred semantic starting point", () => {
    const output = generateLlmHelp("get-accessibility-tree");
    const parsed = JSON.parse(output);
    expect(parsed.explanation).toContain("best first step");
    expect(parsed.related).toContain("find-element");
  });

  it("tells models they can highlight before taking a screenshot", () => {
    const output = generateLlmHelp("highlight show");
    const parsed = JSON.parse(output);
    expect(parsed.explanation).toContain("capture a screenshot");
    expect(parsed.related).toContain("screenshot-annotated");
  });

  it("returns error for unknown command", () => {
    const output = generateLlmHelp("nonexistent");
    const parsed = JSON.parse(output);
    expect(parsed.error).toContain("Unknown command");
  });

  it("returns group commands when filtering by group", () => {
    const output = generateLlmHelp("group");
    const parsed = JSON.parse(output);
    expect(Array.isArray(parsed)).toBe(true);
    expect(parsed.length).toBeGreaterThan(0);
    expect(parsed.every((e: { command: string }) => e.command.startsWith("group "))).toBe(true);
  });

  it("params have name, type, required fields", () => {
    const parsed = JSON.parse(generateLlmHelp("fill"));
    for (const param of parsed.params) {
      expect(param).toHaveProperty("name");
      expect(param).toHaveProperty("type");
      expect(param).toHaveProperty("required");
    }
    const selectorParam = parsed.params.find((p: { name: string }) => p.name === "selector");
    expect(selectorParam?.required).toBe(true);
  });

  it("returns help for browser launch", () => {
    const output = generateLlmHelp("browser launch");
    const parsed = JSON.parse(output);
    expect(parsed.command).toBe("browser launch");
    expect(parsed.params.some((p: { name: string }) => p.name === "port")).toBe(true);
  });

  it("resolves grouped CLI aliases like renderer get", () => {
    const output = generateLlmHelp("renderer get");
    const parsed = JSON.parse(output);
    expect(parsed.command).toBe("renderer get");
    expect(parsed.purpose).toContain("renderer");
  });

  it("resolves platform utility aliases like debug-overlay set", () => {
    const output = generateLlmHelp("debug-overlay set");
    const parsed = JSON.parse(output);
    expect(parsed.command).toBe("debug-overlay set");
    expect(parsed.purpose).toContain("debug overlay");
  });

  it("includes authentication and reporting guidance in the full help output", () => {
    const parsed = JSON.parse(generateLlmHelp());
    expect(parsed[0].command).toBe("authentication");
    expect(parsed[0].explanation).toContain("httpOnly");
    expect(parsed[1].command).toBe("reporting");
    expect(parsed[1].explanation).toContain("github.com/UnlikeOtherAI/kelpie/issues");
  });
});
