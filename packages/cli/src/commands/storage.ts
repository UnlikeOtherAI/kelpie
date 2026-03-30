import type { Command } from "commander";
import { deviceCommand } from "./helpers.js";

export function registerStorage(program: Command): void {
  const storage = program
    .command("storage")
    .description("Manage localStorage/sessionStorage");

  storage
    .command("get")
    .description("Read storage")
    .option("--type <type>", "local or session", "local")
    .option("--key <key>", "Specific key")
    .action(async (opts: { type: string; key?: string }) => {
      const body: Record<string, unknown> = { type: opts.type };
      if (opts.key) body.key = opts.key;
      await deviceCommand(program, "getStorage", body);
    });

  storage
    .command("set <key> <value>")
    .description("Write to storage")
    .option("--type <type>", "local or session", "local")
    .action(async (key: string, value: string, opts: { type: string }) => {
      await deviceCommand(program, "setStorage", { type: opts.type, key, value });
    });

  storage
    .command("clear")
    .description("Clear storage")
    .option("--type <type>", "local, session, or both", "local")
    .action(async (opts: { type: string }) => {
      await deviceCommand(program, "clearStorage", { type: opts.type });
    });
}
