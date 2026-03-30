import type { Command } from "commander";
import { deviceCommand } from "./helpers.js";

export function registerScroll(program: Command): void {
  program
    .command("scroll")
    .description("Scroll by a fixed amount")
    .option("--x <px>", "Horizontal scroll", "0")
    .option("--y <px>", "Vertical scroll (positive = down)", "0")
    .action(async (opts: { x: string; y: string }) => {
      await deviceCommand(program, "scroll", {
        deltaX: Number(opts.x),
        deltaY: Number(opts.y),
      });
    });

  program
    .command("scroll2 <selector>")
    .description("Resolution-aware scroll to make element visible")
    .option("--position <pos>", "Target position: top, center, bottom", "center")
    .option("--max-scrolls <n>", "Safety limit", "10")
    .action(async (selector: string, opts: { position: string; maxScrolls: string }) => {
      await deviceCommand(program, "scroll2", {
        selector,
        position: opts.position,
        maxScrolls: Number(opts.maxScrolls),
      });
    });

  program
    .command("scroll-top")
    .description("Scroll to the top of the page")
    .action(async () => { await deviceCommand(program, "scrollToTop"); });

  program
    .command("scroll-bottom")
    .description("Scroll to the bottom of the page")
    .action(async () => { await deviceCommand(program, "scrollToBottom"); });
}
