import { InvalidArgumentError, Option, type Command } from "commander";
import { tapMarkerSchema } from "@unlikeotherai/kelpie-shared";
import { deviceCommand } from "./helpers.js";

export function registerInteraction(program: Command): void {
  program
    .command("click <selector>")
    .description("Click an element by selector")
    .option("--click-timeout <ms>", "Wait for element timeout")
    .action(async (selector: string, opts: { clickTimeout?: string }) => {
      const body: Record<string, unknown> = { selector };
      if (opts.clickTimeout) body.timeout = Number(opts.clickTimeout);
      await deviceCommand(program, "click", body);
    });

  program
    .command("tap <x> <y>")
    .description("Tap at specific coordinates (last resort)")
    .addOption(new Option("--marker-style <style>", "Tap marker style (default: circle)")
      .choices(tapMarkerSchema.shape.style.unwrap().options))
    .option("--marker-duration <ms>", "Milliseconds before the tap marker fades (default: 550)", (value) => {
      const parsed = tapMarkerSchema.shape.durationMs.safeParse(value.trim() ? Number(value) : NaN);
      if (!parsed.success) {
        throw new InvalidArgumentError("Expected an integer from 0 to 2147483647.");
      }
      return parsed.data;
    })
    .action(async (x: string, y: string, opts: { markerStyle?: string; markerDuration?: number }) => {
      const body: Record<string, unknown> = { x: Number(x), y: Number(y) };
      if (opts.markerStyle !== undefined || opts.markerDuration !== undefined) {
        body.marker = { style: opts.markerStyle, durationMs: opts.markerDuration };
      }
      await deviceCommand(program, "tap", body);
    });

  program
    .command("fill <selector> <value>")
    .description("Fill a form field with text")
    .option("--fill-timeout <ms>", "Wait for element timeout")
    .action(async (selector: string, value: string, opts: { fillTimeout?: string }) => {
      const body: Record<string, unknown> = { selector, value };
      if (opts.fillTimeout) body.timeout = Number(opts.fillTimeout);
      await deviceCommand(program, "fill", body);
    });

  program
    .command("type <text>")
    .description("Type text character by character")
    .option("--selector <sel>", "Focus element first")
    .option("--delay <ms>", "Delay between keystrokes")
    .action(async (text: string, opts: { selector?: string; delay?: string }) => {
      const body: Record<string, unknown> = { text };
      if (opts.selector) body.selector = opts.selector;
      if (opts.delay) body.delay = Number(opts.delay);
      await deviceCommand(program, "type", body);
    });

  program
    .command("select <selector> <value>")
    .description("Select an option from a <select> element")
    .action(async (selector: string, value: string) => {
      await deviceCommand(program, "selectOption", { selector, value });
    });

  program
    .command("check <selector>")
    .description("Check a checkbox or radio button")
    .action(async (selector: string) => {
      await deviceCommand(program, "check", { selector });
    });

  program
    .command("uncheck <selector>")
    .description("Uncheck a checkbox")
    .action(async (selector: string) => {
      await deviceCommand(program, "uncheck", { selector });
    });
}
