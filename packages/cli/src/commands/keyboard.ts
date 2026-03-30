import type { Command } from "commander";
import { deviceCommand } from "./helpers.js";

export function registerKeyboard(program: Command): void {
  const kb = program
    .command("keyboard")
    .description("Manage soft keyboard");

  kb
    .command("show")
    .description("Show the soft keyboard")
    .option("--selector <sel>", "Focus element first")
    .option("--type <type>", "Keyboard type: default, email, number, phone, url")
    .action(async (opts: { selector?: string; type?: string }) => {
      const body: Record<string, unknown> = {};
      if (opts.selector) body.selector = opts.selector;
      if (opts.type) body.keyboardType = opts.type;
      await deviceCommand(program, "showKeyboard", body);
    });

  kb
    .command("hide")
    .description("Dismiss the soft keyboard")
    .action(async () => { await deviceCommand(program, "hideKeyboard"); });

  kb
    .command("state")
    .description("Check keyboard visibility and viewport impact")
    .action(async () => { await deviceCommand(program, "getKeyboardState"); });

  program
    .command("resize <width> <height>")
    .description("Simulate a reduced viewport size")
    .action(async (width: string, height: string) => {
      await deviceCommand(program, "resizeViewport", {
        width: Number(width),
        height: Number(height),
      });
    });

  program
    .command("resize-reset")
    .description("Restore full-screen viewport")
    .action(async () => { await deviceCommand(program, "resetViewport"); });

  program
    .command("obscured <selector>")
    .description("Check if an element is obscured by keyboard or out of viewport")
    .action(async (selector: string) => {
      await deviceCommand(program, "isElementObscured", { selector });
    });
}
