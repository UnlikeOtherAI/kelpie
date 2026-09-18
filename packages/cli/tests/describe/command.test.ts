import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Command } from "commander";

import { registerDescribe } from "../../src/commands/describe.js";

/**
 * The flags `docs/cli.md` publishes are part of the integrator contract, so a
 * flag named one way in the docs and another way in the source is a broken
 * command, not a typo: Commander rejects an unregistered option outright.
 */

const here = dirname(fileURLToPath(import.meta.url));
const docsPath = join(here, "..", "..", "..", "..", "docs", "cli.md");

function describeCommand(): Command {
  const program = new Command();
  registerDescribe(program);
  const command = program.commands.find((entry) => entry.name() === "describe");
  if (!command) throw new Error("registerDescribe did not register `describe`");
  return command;
}

/** Every `--flag` docs/cli.md shows on a `kelpie describe` example line. */
function documentedFlags(): string[] {
  const docs = readFileSync(docsPath, "utf8");
  const flags = new Set<string>();
  for (const line of docs.split("\n")) {
    if (!line.includes("kelpie describe")) continue;
    for (const match of line.matchAll(/--[a-z][a-z0-9-]*/g)) flags.add(match[0]);
  }
  return [...flags].sort();
}

describe("kelpie describe — command registration", () => {
  it("registers every flag docs/cli.md shows", () => {
    const registered = describeCommand().options.map((option) => option.long);
    const documented = documentedFlags();
    expect(documented.length).toBeGreaterThan(0);
    expect(registered).toEqual(expect.arrayContaining(documented));
  });

  it("accepts --include-tools, the flag the contract names", () => {
    const command = describeCommand();
    command.parseOptions(["--json", "--include-tools"]);
    expect(command.opts()).toMatchObject({ json: true, includeTools: true });
  });
});
