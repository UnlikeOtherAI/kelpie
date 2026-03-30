import type { Command } from "commander";
import { deviceCommand } from "./helpers.js";

export function registerIntercept(program: Command): void {
  const intercept = program
    .command("intercept")
    .description("Manage request interception rules");

  intercept
    .command("block <pattern>")
    .description("Block requests matching pattern")
    .action(async (pattern: string) => {
      await deviceCommand(program, "setRequestInterception", {
        rules: [{ pattern, action: "block" }],
      });
    });

  intercept
    .command("mock <url>")
    .description("Mock a request URL")
    .option("--body <json>", "Response body JSON")
    .option("--mock-status <code>", "Response status code", "200")
    .action(async (url: string, opts: { body?: string; mockStatus: string }) => {
      await deviceCommand(program, "setRequestInterception", {
        rules: [{
          pattern: url,
          action: "mock",
          mockResponse: {
            status: Number(opts.mockStatus),
            headers: { "Content-Type": "application/json" },
            body: opts.body ?? "{}",
          },
        }],
      });
    });

  intercept
    .command("list")
    .description("List intercepted requests")
    .action(async () => { await deviceCommand(program, "getInterceptedRequests"); });

  intercept
    .command("clear")
    .description("Remove all interception rules")
    .action(async () => { await deviceCommand(program, "clearRequestInterception"); });
}
