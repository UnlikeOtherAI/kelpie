import type { Command } from "commander";
import { deviceCommand } from "./helpers.js";

export function registerFormState(program: Command): void {
  program
    .command("form-state")
    .description("Get the state of all forms on the page")
    .option("--selector <sel>", "Scope to specific form")
    .action(async (opts: { selector?: string }) => {
      const body: Record<string, unknown> = {};
      if (opts.selector) body.selector = opts.selector;
      await deviceCommand(program, "getFormState", body);
    });
}
