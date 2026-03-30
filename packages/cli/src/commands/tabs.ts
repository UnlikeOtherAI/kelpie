import type { Command } from "commander";
import { deviceCommand } from "./helpers.js";

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
    .action(async (url?: string) => {
      const body: Record<string, unknown> = {};
      if (url) body.url = url;
      await deviceCommand(program, "newTab", body);
    });

  tab
    .command("switch <id>")
    .description("Switch to a tab by ID")
    .action(async (id: string) => {
      await deviceCommand(program, "switchTab", { tabId: Number(id) });
    });

  tab
    .command("close <id>")
    .description("Close a tab by ID")
    .action(async (id: string) => {
      await deviceCommand(program, "closeTab", { tabId: Number(id) });
    });
}
