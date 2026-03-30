import { writeFile, mkdir } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import type { Command } from "commander";
import { requireDevice, getGlobals, deviceCommand } from "./helpers.js";
import { sendCommand } from "../client/http-client.js";
import { print } from "../output/formatter.js";

export function registerAnnotate(program: Command): void {
  program
    .command("annotate")
    .description("Take an annotated screenshot with numbered labels")
    .option("--output <path>", "Save to explicit path or directory")
    .option("--full-page", "Capture entire page")
    .option("--base64", "Return raw base64 instead of saving")
    .option("--interactable-only", "Only label interactive elements")
    .action(async (opts: {
      output?: string;
      fullPage?: boolean;
      base64?: boolean;
      interactableOnly?: boolean;
    }) => {
      const globals = getGlobals(program);
      const device = requireDevice(program);
      if (!device) return;

      const body: Record<string, unknown> = {
        fullPage: opts.fullPage ?? false,
        interactableOnly: opts.interactableOnly ?? true,
      };

      const result = await sendCommand<{
        success: boolean;
        image?: string;
        annotations?: unknown[];
        width?: number;
        height?: number;
      }>(device, "screenshotAnnotated", body, globals.timeout);

      if (!result.ok || !result.data.image) {
        print(result.data, globals.format);
        process.exitCode = 1;
        return;
      }

      if (opts.base64) {
        print(result.data, globals.format);
        return;
      }

      const slug = device.name.toLowerCase().replace(/[^a-z0-9]+/g, "-");
      const timestamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
      const filename = `${slug}-annotated-${timestamp}.png`;

      let filePath: string;
      if (!opts.output) {
        filePath = resolve(filename);
      } else if (opts.output.endsWith("/")) {
        filePath = join(resolve(opts.output), filename);
      } else {
        filePath = resolve(opts.output);
      }

      await mkdir(dirname(filePath), { recursive: true });
      await writeFile(filePath, Buffer.from(result.data.image, "base64"));
      print({
        success: true,
        file: filePath,
        annotations: result.data.annotations,
        width: result.data.width,
        height: result.data.height,
      }, globals.format);
    });

  program
    .command("click-index <index>")
    .description("Click an element by annotation index")
    .action(async (index: string) => {
      await deviceCommand(program, "clickAnnotation", { index: Number(index) });
    });

  program
    .command("fill-index <index> <value>")
    .description("Fill an element by annotation index")
    .action(async (index: string, value: string) => {
      await deviceCommand(program, "fillAnnotation", { index: Number(index), value });
    });
}
