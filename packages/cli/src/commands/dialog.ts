import type { Command } from "commander";
import { deviceCommand } from "./helpers.js";

export function registerDialog(program: Command): void {
  const dialog = program
    .command("dialog")
    .description("Manage JavaScript dialogs");

  dialog
    .command("check")
    .description("Check if a dialog is showing")
    .action(async () => { await deviceCommand(program, "getDialog"); });

  dialog
    .command("accept")
    .description("Accept the current dialog")
    .option("--prompt-text <text>", "Text for prompt dialogs")
    .action(async (opts: { promptText?: string }) => {
      const body: Record<string, unknown> = { action: "accept" };
      if (opts.promptText) body.promptText = opts.promptText;
      await deviceCommand(program, "handleDialog", body);
    });

  dialog
    .command("dismiss")
    .description("Dismiss the current dialog")
    .action(async () => {
      await deviceCommand(program, "handleDialog", { action: "dismiss" });
    });

  dialog
    .command("auto")
    .description("Configure automatic dialog handling")
    .option("--action <action>", "accept, dismiss, or queue")
    .option("--off", "Disable auto-handling")
    .action(async (opts: { action?: string; off?: boolean }) => {
      if (opts.off) {
        await deviceCommand(program, "setDialogAutoHandler", { enabled: false });
      } else {
        await deviceCommand(program, "setDialogAutoHandler", {
          enabled: true,
          defaultAction: opts.action ?? "accept",
        });
      }
    });
}
