import type { Command } from "commander";
import { deviceCommand } from "./helpers.js";

export function registerWait(program: Command): void {
  program
    .command("wait <selector>")
    .description("Wait for an element to appear in the DOM")
    .option("--wait-timeout <ms>", "Timeout in milliseconds", "5000")
    .option("--state <state>", "Target state: attached, visible, hidden", "visible")
    .action(async (selector: string, opts: { waitTimeout: string; state: string }) => {
      await deviceCommand(program, "waitForElement", {
        selector,
        timeout: Number(opts.waitTimeout),
        state: opts.state,
      });
    });

  program
    .command("wait-nav")
    .description("Wait for a navigation event to complete")
    .option("--wait-timeout <ms>", "Timeout in milliseconds", "10000")
    .action(async (opts: { waitTimeout: string }) => {
      await deviceCommand(program, "waitForNavigation", {
        timeout: Number(opts.waitTimeout),
      });
    });
}
