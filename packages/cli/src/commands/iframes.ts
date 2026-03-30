import type { Command } from "commander";
import { deviceCommand } from "./helpers.js";

export function registerIframes(program: Command): void {
  program
    .command("iframes")
    .description("List all iframes on the page")
    .action(async () => { await deviceCommand(program, "getIframes"); });

  const iframe = program
    .command("iframe")
    .description("Manage iframe context");

  iframe
    .command("enter <idOrSelector>")
    .description("Switch command context into an iframe")
    .action(async (idOrSelector: string) => {
      const body: Record<string, unknown> = {};
      if (/^\d+$/.test(idOrSelector)) {
        body.iframeId = Number(idOrSelector);
      } else {
        body.selector = idOrSelector;
      }
      await deviceCommand(program, "switchToIframe", body);
    });

  iframe
    .command("exit")
    .description("Switch back to the main page context")
    .action(async () => { await deviceCommand(program, "switchToMain"); });

  iframe
    .command("context")
    .description("Check current command context")
    .action(async () => { await deviceCommand(program, "getIframeContext"); });
}
