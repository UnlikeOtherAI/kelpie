import type { Command } from "commander";
import { deviceCommand } from "./helpers.js";

export function registerNetwork(program: Command): void {
  program
    .command("network")
    .description("Get the network activity log")
    .option("--type <type>", "Filter: document, script, stylesheet, image, font, xhr, fetch, websocket")
    .option("--status <status>", "Filter: success, error, pending")
    .option("--limit <n>", "Max entries", "200")
    .action(async (opts: { type?: string; status?: string; limit: string }) => {
      const body: Record<string, unknown> = { limit: Number(opts.limit) };
      if (opts.type) body.type = opts.type;
      if (opts.status) body.status = opts.status;
      await deviceCommand(program, "getNetworkLog", body);
    });

  program
    .command("timeline")
    .description("Get the resource loading timeline")
    .action(async () => { await deviceCommand(program, "getResourceTimeline"); });
}
