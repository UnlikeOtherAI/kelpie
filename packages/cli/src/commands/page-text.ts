import type { Command } from "commander";
import { deviceCommand } from "./helpers.js";

export function registerPageText(program: Command): void {
  program
    .command("page-text")
    .description("Extract readable text from the page")
    .option("--mode <mode>", "readable, full, or markdown", "readable")
    .option("--selector <sel>", "Extract from specific element")
    .action(async (opts: { mode: string; selector?: string }) => {
      const body: Record<string, unknown> = { mode: opts.mode };
      if (opts.selector) body.selector = opts.selector;
      await deviceCommand(program, "getPageText", body);
    });
}
