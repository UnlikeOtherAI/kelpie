import { writeFile, mkdir } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import type { Command } from "commander";
import { requireDevice, getGlobals } from "./helpers.js";
import { sendCommand } from "../client/http-client.js";
import { print } from "../output/formatter.js";

export function registerScreenshot(program: Command): void {
  program
    .command("screenshot")
    .description("Capture a screenshot of the current viewport")
    .option("--output <path>", "Save to explicit path or directory")
    .option("--full-page", "Capture the entire scrollable page")
    .option("--base64", "Return raw base64 instead of saving to file")
    .option("--image-format <fmt>", "Image format: png or jpeg", "png")
    .option("--quality <n>", "JPEG quality 1-100")
    .action(async (opts: {
      output?: string;
      fullPage?: boolean;
      base64?: boolean;
      imageFormat: string;
      quality?: string;
    }) => {
      const globals = getGlobals(program);
      const device = requireDevice(program);
      if (!device) return;

      const body: Record<string, unknown> = {
        fullPage: opts.fullPage ?? false,
        format: opts.imageFormat,
      };
      if (opts.quality) body.quality = Number(opts.quality);

      const result = await sendCommand<{
        success: boolean;
        image?: string;
        width?: number;
        height?: number;
        format?: string;
      }>(device, "screenshot", body, globals.timeout);

      if (!result.ok || !result.data.image) {
        print(result.data, globals.format);
        process.exitCode = 1;
        return;
      }

      if (opts.base64) {
        print(result.data, globals.format);
        return;
      }

      // File save mode
      const filePath = await saveScreenshot(
        result.data.image,
        opts.output,
        device.name,
        opts.imageFormat,
      );
      print({ success: true, file: filePath, width: result.data.width, height: result.data.height }, globals.format);
    });
}

async function saveScreenshot(
  base64: string,
  outputPath: string | undefined,
  deviceName: string,
  format: string,
): Promise<string> {
  const slug = deviceName.toLowerCase().replace(/[^a-z0-9]+/g, "-");
  const timestamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
  const filename = `${slug}-${timestamp}.${format}`;

  let filePath: string;
  if (!outputPath) {
    filePath = resolve(filename);
  } else if (outputPath.endsWith("/") || outputPath.endsWith("\\")) {
    filePath = join(resolve(outputPath), filename);
  } else {
    filePath = resolve(outputPath);
  }

  await mkdir(dirname(filePath), { recursive: true });
  await writeFile(filePath, Buffer.from(base64, "base64"));
  return filePath;
}
