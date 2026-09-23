import { describe, expect, it } from "vitest";
import { Command } from "commander";
import { registerAllCommands } from "../../src/commands/index.js";
import { requestedLaunchPort } from "../../src/commands/browser.js";

describe("browser command registration", () => {
  it("registers the browser command tree with help descriptions", () => {
    const program = new Command();
    registerAllCommands(program);

    const browser = program.commands.find((command) => command.name() === "browser");
    expect(browser).toBeDefined();
    expect(browser?.description()).toContain("browser");

    const subcommands = browser?.commands.map((command) => command.name()).sort();
    expect(subcommands).toEqual(["inspect", "launch", "list", "register", "remove", "stop"]);
    expect(browser?.helpInformation()).toContain("launch");
    expect(browser?.helpInformation()).toContain("register");
  });

  it("passes browser launch --port through, although the program also owns --port", async () => {
    // The real program declares --port with a default; Commander gives the
    // value to it, not to the launch subcommand.
    const requested = async (argv: string[]) => {
      const program = new Command().option("--port <port>", "Override default port", "8420");
      let seen: string | undefined = "unset";
      program.command("browser").command("launch <name>").option("--port <port>")
        .action((_name: string, opts: { port?: string }) => { seen = requestedLaunchPort(program, opts.port); });
      await program.parseAsync(["node", "kelpie", ...argv]);
      return seen;
    };
    expect(await requested(["browser", "launch", "win", "--port", "8450"])).toBe("8450");
    expect(await requested(["--port", "8451", "browser", "launch", "win"])).toBe("8451");
    // No --port at all: the program default is not a request.
    expect(await requested(["browser", "launch", "win"])).toBeUndefined();
  });
});
