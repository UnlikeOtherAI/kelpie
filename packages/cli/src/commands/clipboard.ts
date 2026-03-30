import type { Command } from "commander";
import { deviceCommand } from "./helpers.js";

export function registerClipboard(program: Command): void {
  const clip = program
    .command("clipboard")
    .description("Manage clipboard");

  clip
    .command("get")
    .description("Read clipboard contents")
    .action(async () => { await deviceCommand(program, "getClipboard"); });

  clip
    .command("set <text>")
    .description("Write to clipboard")
    .action(async (text: string) => {
      await deviceCommand(program, "setClipboard", { text });
    });
}
