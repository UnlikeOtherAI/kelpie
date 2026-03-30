import type { Command } from "commander";
import { deviceCommand } from "./helpers.js";

export function registerShadowDOM(program: Command): void {
  program
    .command("shadow-roots")
    .description("List all shadow DOM hosts on the page")
    .action(async () => { await deviceCommand(program, "getShadowRoots"); });

  program
    .command("shadow-query <host> <selector>")
    .description("Query elements inside a shadow root")
    .option("--pierce", "Recursively pierce nested shadow DOMs")
    .action(async (host: string, selector: string, opts: { pierce?: boolean }) => {
      await deviceCommand(program, "queryShadowDOM", {
        hostSelector: host,
        shadowSelector: selector,
        pierce: opts.pierce ?? false,
      });
    });
}
