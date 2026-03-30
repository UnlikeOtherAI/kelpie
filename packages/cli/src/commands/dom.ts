import type { Command } from "commander";
import { deviceCommand } from "./helpers.js";

export function registerDOM(program: Command): void {
  program
    .command("dom")
    .description("Get the DOM tree")
    .option("--selector <sel>", "Root element selector")
    .option("--depth <n>", "Max depth")
    .action(async (opts: { selector?: string; depth?: string }) => {
      const body: Record<string, unknown> = {};
      if (opts.selector) body.selector = opts.selector;
      if (opts.depth) body.depth = Number(opts.depth);
      await deviceCommand(program, "getDOM", body);
    });

  program
    .command("query <selector>")
    .description("Query for elements by CSS selector")
    .option("--all", "Return all matching elements")
    .action(async (selector: string, opts: { all?: boolean }) => {
      const method = opts.all ? "querySelectorAll" : "querySelector";
      await deviceCommand(program, method, { selector });
    });

  program
    .command("text <selector>")
    .description("Get the text content of an element")
    .action(async (selector: string) => {
      await deviceCommand(program, "getElementText", { selector });
    });

  program
    .command("attributes <selector>")
    .description("Get all attributes of an element")
    .action(async (selector: string) => {
      await deviceCommand(program, "getAttributes", { selector });
    });
}
