import type { Command } from "commander";
import { deviceCommand } from "./helpers.js";

export function registerEval(program: Command): void {
  program
    .command("eval <expression>")
    .description("Evaluate a JavaScript expression in the browser")
    .action(async (expression: string) => {
      await deviceCommand(program, "evaluate", { expression });
    });
}
