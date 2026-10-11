import type { Command } from "commander";
import { BrowserControlRequestSchema } from "@unlikeotherai/kelpie-shared/browser-control";
import { nativeBrowserTransport } from "../client/browser-control.js";
import { getGlobals, requireDevice } from "./helpers.js";
import { print } from "../output/formatter.js";
export function registerCanonicalBrowserControl(program: Command): void {
  program.command("browser-control <request-json>")
    .description("Send the shared versioned browser request to the selected native gateway")
    .action(async (json: string) => {
      let input: unknown;
      try { input = JSON.parse(json); } catch { program.error("Request must be valid JSON."); }
      const request = BrowserControlRequestSchema.safeParse(input);
      if (!request.success) { program.error("Request must match the strict shared version 1 browser contract."); return; }
      const device = await requireDevice(program);
      if (!device) return;
      const globals = getGlobals(program);
      const result = await nativeBrowserTransport(device, globals.timeout).call(request.data);
      print(result, globals.format);
      if (!result.ok) process.exitCode = 1;
    });
}
