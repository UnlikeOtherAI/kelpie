import type { Command } from "commander";
import { print } from "../output/formatter.js";
import { requireDevice } from "./helpers.js";
import { pair } from "../auth/pairing.js";
import {
  defaultClientName,
  getSessionCache,
  getTokenStore,
} from "../auth/token-store.js";
import type { GlobalOptions } from "../types.js";

/**
 * `kelpie pair` — explicit pairing flow.
 *
 * Same state machine as the implicit retry in {@link sendCommand}, but
 * exposed as a first-class command so scripts can prime credentials before
 * automation runs.
 *
 *   kelpie pair --device <id|name|ip>
 *     -> POST /v1/pair, poll /v1/pair/status, store the token by scope.
 *
 * Persistent-scope tokens land in `~/.kelpie/tokens.json` (mode 0600).
 * Session-scope tokens stay in process memory and are lost at exit — same
 * contract as approval "Yes, once" on the device.
 */
export function registerPair(program: Command): void {
  program
    .command("pair")
    .description("Pair the CLI with a Kelpie device (one-time, requires on-device approval)")
    .option("--client-name <name>", "Client name shown on the device prompt", defaultClientName())
    .option(
      "--timeout-ms <ms>",
      "How long to wait for on-device approval before giving up",
      String(5 * 60_000),
    )
    .action(async (opts: { clientName: string; timeoutMs: string }) => {
      const globals = program.opts<GlobalOptions>();
      const device = await requireDevice(program);
      if (!device) return;

      const store = getTokenStore();
      const clientId = await store.clientId();
      const overallTimeoutMs = Number(opts.timeoutMs) || 5 * 60_000;

      const result = await pair({
        host: device.ip,
        port: device.port,
        clientId,
        clientName: opts.clientName,
        overallTimeoutMs,
      });

      if (result.status !== "approved") {
        print(
          {
            success: false,
            error: {
              code: result.status === "error" ? result.code : `PAIR_${result.status.toUpperCase()}`,
              message:
                result.status === "error"
                  ? result.message
                  : `Pairing ${result.status}`,
            },
          },
          globals.format,
        );
        process.exitCode = 2;
        return;
      }

      if (result.scope === "persistent") {
        await store.set(device.id, device.ip, device.port, result.token);
      } else {
        getSessionCache().set(device.id, device.ip, device.port, result.token);
      }

      print(
        {
          success: true,
          deviceId: device.id,
          deviceName: device.name,
          host: device.ip,
          port: device.port,
          scope: result.scope,
          persisted: result.scope === "persistent",
        },
        globals.format,
      );
    });
}
