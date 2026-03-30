import type { Command } from "commander";
import { deviceCommand } from "./helpers.js";

export function registerNavigate(program: Command): void {
  program
    .command("navigate <url>")
    .description("Navigate to a URL")
    .action(async (url: string) => {
      await deviceCommand(program, "navigate", { url });
    });

  program
    .command("back")
    .description("Go back in browser history")
    .action(async () => { await deviceCommand(program, "back"); });

  program
    .command("forward")
    .description("Go forward in browser history")
    .action(async () => { await deviceCommand(program, "forward"); });

  program
    .command("reload")
    .description("Reload the current page")
    .action(async () => { await deviceCommand(program, "reload"); });

  program
    .command("url")
    .description("Get the current page URL and title")
    .action(async () => { await deviceCommand(program, "getCurrentUrl"); });
}
