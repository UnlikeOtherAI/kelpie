import { describe, it, expect } from "vitest";
import { explainCommand } from "../../src/help/explain.js";

describe("explainCommand", () => {
  it("explains navigate", () => {
    const output = explainCommand("navigate");
    expect(output).toContain("navigate");
    expect(output).toContain("URL");
    expect(output).toContain("Related:");
  });

  it("explains scroll2 in detail", () => {
    const output = explainCommand("scroll2");
    expect(output).toContain("scroll2");
    expect(output).toContain("viewport");
    expect(output).toContain("scroll distance");
  });

  it("explains click with related commands", () => {
    const output = explainCommand("click");
    expect(output).toContain("Platforms:");
    expect(output).toContain("Related:");
    expect(output).toContain("tap");
  });

  it("returns error message for unknown command", () => {
    const output = explainCommand("nonexistent");
    expect(output).toContain("Unknown command");
  });

  it("explains get-form-state", () => {
    const output = explainCommand("get-form-state");
    expect(output).toContain("form");
    expect(output).toContain("fields");
  });

  it("explains browser launch", () => {
    const output = explainCommand("browser launch");
    expect(output).toContain("browser launch");
    expect(output).toContain("Platforms: macos");
    expect(output).toContain("opens Kelpie without requesting another instance");
    expect(output).toContain("Only one standalone app may run on this computer");
  });
});
