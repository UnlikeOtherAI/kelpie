import type { Command } from "commander";
import { deviceCommand } from "./helpers.js";

export function registerMutations(program: Command): void {
  const mutations = program
    .command("mutations")
    .description("Watch and get DOM mutations");

  mutations
    .command("watch")
    .description("Start observing DOM mutations")
    .option("--selector <sel>", "Scope observation to selector")
    .action(async (opts: { selector?: string }) => {
      const body: Record<string, unknown> = {
        attributes: true,
        childList: true,
        subtree: true,
      };
      if (opts.selector) body.selector = opts.selector;
      await deviceCommand(program, "watchMutations", body);
    });

  mutations
    .command("get")
    .description("Get accumulated mutations")
    .option("--watch-id <id>", "Watch ID")
    .option("--clear", "Clear buffer after reading")
    .action(async (opts: { watchId?: string; clear?: boolean }) => {
      const body: Record<string, unknown> = {};
      if (opts.watchId) body.watchId = opts.watchId;
      if (opts.clear) body.clear = true;
      await deviceCommand(program, "getMutations", body);
    });

  mutations
    .command("stop")
    .description("Stop a mutation observer")
    .option("--watch-id <id>", "Watch ID")
    .action(async (opts: { watchId?: string }) => {
      const body: Record<string, unknown> = {};
      if (opts.watchId) body.watchId = opts.watchId;
      await deviceCommand(program, "stopWatching", body);
    });
}
