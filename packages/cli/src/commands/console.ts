import type { Command } from "commander";
import { deviceCommand } from "./helpers.js";

export function registerConsole(program: Command): void {
  program
    .command("console")
    .description("Get console messages from the page")
    .option("--level <level>", "Filter: log, warn, error, info, debug")
    .option("--limit <n>", "Max messages", "100")
    .action(async (opts: { level?: string; limit: string }) => {
      const body: Record<string, unknown> = { limit: Number(opts.limit) };
      if (opts.level) body.level = opts.level;
      await deviceCommand(program, "getConsoleMessages", body);
    });

  program
    .command("errors")
    .description("Get JavaScript errors")
    .action(async () => { await deviceCommand(program, "getJSErrors"); });

  program
    .command("clear-console")
    .description("Clear the console message buffer")
    .action(async () => { await deviceCommand(program, "clearConsole"); });
}
