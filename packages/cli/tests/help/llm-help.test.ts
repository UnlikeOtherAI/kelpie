import { describe, it, expect } from "vitest";
import { generateLlmHelp } from "../../src/help/llm-help.js";

describe("generateLlmHelp", () => {
  it("returns valid JSON for all commands", () => {
    const output = generateLlmHelp();
    const parsed = JSON.parse(output);
    expect(Array.isArray(parsed)).toBe(true);
    expect(parsed.length).toBe(133);
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
    expect(parsed.errors).toContain("ELEMENT_NOT_FOUND");
    expect(parsed.related).toContain("tap");
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
});
