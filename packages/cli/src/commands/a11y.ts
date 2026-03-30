import type { Command } from "commander";
import { deviceCommand } from "./helpers.js";

export function registerA11y(program: Command): void {
  program
    .command("a11y")
    .description("Get the accessibility tree (LLM-optimized)")
    .option("--interactable-only", "Only return interactive elements")
    .option("--selector <sel>", "Scope to a specific element")
    .option("--max-depth <n>", "Limit tree depth")
    .action(async (opts: { interactableOnly?: boolean; selector?: string; maxDepth?: string }) => {
      const body: Record<string, unknown> = {};
      if (opts.interactableOnly) body.interactableOnly = true;
      if (opts.selector) body.root = opts.selector;
      if (opts.maxDepth) body.maxDepth = Number(opts.maxDepth);
      await deviceCommand(program, "getAccessibilityTree", body);
    });
}
