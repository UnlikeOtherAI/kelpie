import { describe, expect, it } from "vitest";
import { Command } from "commander";
import { registerAllCommands } from "../../src/commands/index.js";

describe("platform utility command registration", () => {
  it("registers toast and debug overlay commands", () => {
    const program = new Command();
    registerAllCommands(program);

    expect(program.commands.find((command) => command.name() === "toast")).toBeDefined();
    expect(program.commands.find((command) => command.name() === "safari-auth")).toBeUndefined();

    const debugOverlay = program.commands.find((command) => command.name() === "debug-overlay");
    expect(debugOverlay).toBeDefined();
    expect(debugOverlay?.commands.map((command) => command.name()).sort()).toEqual(["get", "set"]);
  });
});
