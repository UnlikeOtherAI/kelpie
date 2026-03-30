import type { Command } from "commander";
import { deviceCommand } from "./helpers.js";

export function registerVisible(program: Command): void {
  program
    .command("visible")
    .description("Get elements currently visible in the viewport")
    .option("--interactable-only", "Only return interactive elements")
    .action(async (opts: { interactableOnly?: boolean }) => {
      const body: Record<string, unknown> = {};
      if (opts.interactableOnly) body.interactableOnly = true;
      await deviceCommand(program, "getVisibleElements", body);
    });
}
