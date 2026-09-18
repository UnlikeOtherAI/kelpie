import type { Command } from "commander";
import { deviceCommand } from "./helpers.js";
import {
  partitionFlagError,
  partitionTabBody,
  printValidationError,
  type PartitionTabOptions,
} from "./partition-options.js";

export function registerTabs(program: Command): void {
  program
    .command("tabs")
    .description("List all open tabs")
    .action(async () => { await deviceCommand(program, "getTabs"); });

  const tab = program
    .command("tab")
    .description("Manage tabs");

  tab
    .command("new [url]")
    .description("Open a new tab")
    .option("--name <label>", "Display label for the tab (max 200 characters)")
    .option("--partition <id>", "Storage partition to isolate the tab's cookies and local storage")
    .option("--ephemeral", "Keep the partition's storage in memory only (requires --partition)")
    .option("--non-persistent", "Alias for --ephemeral")
    .action(async (url: string | undefined, opts: PartitionTabOptions) => {
      const invalid = partitionFlagError(opts);
      if (invalid) {
        printValidationError(program, invalid);
        return;
      }
      const body = partitionTabBody(opts);
      if (url) body.url = url;
      await deviceCommand(program, "newTab", body);
    });

  tab
    .command("switch <id>")
    .description("Switch to a tab by ID")
    .action(async (id: string) => {
      await deviceCommand(program, "switchTab", { tabId: id });
    });

  tab
    .command("close <id>")
    .description("Close a tab by ID")
    .action(async (id: string) => {
      await deviceCommand(program, "closeTab", { tabId: id });
    });
}
