import type { Command } from "commander";
import { deviceCommand } from "./helpers.js";

export function registerGeo(program: Command): void {
  const geo = program
    .command("geo")
    .description("Manage geolocation override");

  geo
    .command("set <lat> <lng>")
    .description("Override geolocation")
    .option("--accuracy <m>", "Accuracy in meters", "10")
    .action(async (lat: string, lng: string, opts: { accuracy: string }) => {
      await deviceCommand(program, "setGeolocation", {
        latitude: Number(lat),
        longitude: Number(lng),
        accuracy: Number(opts.accuracy),
      });
    });

  geo
    .command("clear")
    .description("Remove geolocation override")
    .action(async () => { await deviceCommand(program, "clearGeolocation"); });
}
