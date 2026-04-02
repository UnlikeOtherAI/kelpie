import { describe, expect, it } from "vitest";
import { Command } from "commander";
import { registerAllCommands } from "../../src/commands/index.js";

describe("browser command registration", () => {
  it("registers the browser command tree with help descriptions", () => {
    const program = new Command();
    registerAllCommands(program);

    const browser = program.commands.find((command) => command.name() === "browser");
    expect(browser).toBeDefined();
    expect(browser?.description()).toContain("browser");

    const subcommands = browser?.commands.map((command) => command.name()).sort();
    expect(subcommands).toEqual(["inspect", "launch", "list", "register", "remove"]);
    expect(browser?.helpInformation()).toContain("launch");
    expect(browser?.helpInformation()).toContain("register");
  });
});
