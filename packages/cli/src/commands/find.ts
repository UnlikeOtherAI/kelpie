import type { Command } from "commander";
import { deviceCommand } from "./helpers.js";

export function registerFind(program: Command): void {
  program
    .command("find-element <text>")
    .description("Search for an element by visible text")
    .option("--role <role>", "ARIA role filter")
    .action(async (text: string, opts: { role?: string }) => {
      const body: Record<string, unknown> = { text };
      if (opts.role) body.role = opts.role;
      await deviceCommand(program, "findElement", body);
    });

  program
    .command("find-button <text>")
    .description("Find a button by text")
    .action(async (text: string) => {
      await deviceCommand(program, "findButton", { text });
    });

  program
    .command("find-link <text>")
    .description("Find a link by text")
    .action(async (text: string) => {
      await deviceCommand(program, "findLink", { text });
    });

  program
    .command("find-input <label>")
    .description("Find an input by label, placeholder, or name")
    .option("--placeholder <text>", "Search by placeholder")
    .option("--name <name>", "Search by name attribute")
    .action(async (label: string, opts: { placeholder?: string; name?: string }) => {
      const body: Record<string, unknown> = { label };
      if (opts.placeholder) body.placeholder = opts.placeholder;
      if (opts.name) body.name = opts.name;
      await deviceCommand(program, "findInput", body);
    });
}
