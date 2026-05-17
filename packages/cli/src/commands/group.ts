import { writeFile, mkdir } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import type { Command } from "commander";
import { getAllDevices } from "../discovery/registry.js";
import { sendCommand } from "../client/http-client.js";
import {
  executeGroup,
  executeSmartQuery,
  type GroupResult,
  type SmartQueryResult,
} from "../group/orchestrator.js";
import { filterDevices, type FilterOptions } from "../group/filter.js";
import { getGlobals } from "./helpers.js";
import { print } from "../output/formatter.js";

interface GroupCommandOptions extends FilterOptions {
  allowPartial?: boolean;
}

function addGroupOptions(cmd: Command): Command {
  return cmd
    .option("--platform <platform>", "Filter: ios or android")
    .option("--include <devices>", "Only these devices (comma-separated IDs or names)")
    .option("--exclude <devices>", "Exclude these devices (comma-separated)")
    .option(
      "--allow-partial",
      "Exit 0 even when some devices fail (default: exit non-zero if any device fails)",
    );
}

function getFilteredDevices(opts: FilterOptions): ReturnType<typeof getAllDevices> {
  return filterDevices(getAllDevices(), opts);
}

/** Set exit code 1 if any device failed and --allow-partial was not passed. */
function applyExitCode(failed: number, opts: GroupCommandOptions): void {
  if (failed > 0 && !opts.allowPartial) {
    process.exitCode = 1;
  }
}

function printGroupResult<T>(result: GroupResult<T>, opts: GroupCommandOptions, format: "json" | "table" | "text"): void {
  print(result, format);
  applyExitCode(result.failed, opts);
}

function printSmartQueryResult<T>(result: SmartQueryResult<T>, opts: GroupCommandOptions, format: "json" | "table" | "text"): void {
  print(result, format);
  // For smart queries, "not found because of an error" counts as a failure.
  // notFound entries with no error reason are simply "element absent" and do
  // not flip exit code — only device-level errors do.
  applyExitCode(result.errors.length, opts);
}

export function registerGroup(program: Command): void {
  const group = program
    .command("group")
    .description("Send commands to all (or filtered) devices");

  // Navigate
  addGroupOptions(
    group
      .command("navigate <url>")
      .description("Navigate all devices to a URL"),
  ).action(async (url: string, opts: GroupCommandOptions) => {
    const globals = getGlobals(program);
    const devices = getFilteredDevices(opts);
    const result = await executeGroup(devices, "navigate", { url }, globals.timeout);
    printGroupResult(result, opts, globals.format);
  });

  // Screenshot
  addGroupOptions(
    group
      .command("screenshot")
      .description("Screenshot all devices")
      .option("--output <dir>", "Save directory"),
  ).action(async (opts: GroupCommandOptions & { output?: string }) => {
    const globals = getGlobals(program);
    const devices = getFilteredDevices(opts);
    const results = await Promise.all(
      devices.map(async (d) => {
        const r = await sendCommand<{ success: boolean; image?: string; width?: number; height?: number }>(
          d, "screenshot", { fullPage: false, format: "png" }, globals.timeout,
        );
        if (r.ok && r.data.image) {
          const slug = d.name.toLowerCase().replace(/[^a-z0-9]+/g, "-");
          const ts = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
          const filename = `${slug}-${ts}.png`;
          const dir = opts.output ? resolve(opts.output) : process.cwd();
          const filePath = join(dir, filename);
          await mkdir(dirname(filePath), { recursive: true });
          await writeFile(filePath, Buffer.from(r.data.image, "base64"));
          return { device: d.name, success: true, file: filePath };
        }
        return { device: d.name, success: false, error: r.data };
      }),
    );
    print({ command: "screenshot", results }, globals.format);
    const failed = results.filter((r) => !r.success).length;
    applyExitCode(failed, opts);
  });

  // Fill
  addGroupOptions(
    group
      .command("fill <selector> <value>")
      .description("Fill a field on all devices"),
  ).action(async (selector: string, value: string, opts: GroupCommandOptions) => {
    const globals = getGlobals(program);
    const devices = getFilteredDevices(opts);
    const result = await executeGroup(devices, "fill", { selector, value }, globals.timeout);
    printGroupResult(result, opts, globals.format);
  });

  // Click
  addGroupOptions(
    group
      .command("click <selector>")
      .description("Click an element on all devices"),
  ).action(async (selector: string, opts: GroupCommandOptions) => {
    const globals = getGlobals(program);
    const devices = getFilteredDevices(opts);
    const result = await executeGroup(devices, "click", { selector }, globals.timeout);
    printGroupResult(result, opts, globals.format);
  });

  // Scroll2
  addGroupOptions(
    group
      .command("scroll2 <selector>")
      .description("Resolution-aware scroll on all devices"),
  ).action(async (selector: string, opts: GroupCommandOptions) => {
    const globals = getGlobals(program);
    const devices = getFilteredDevices(opts);
    const result = await executeGroup(devices, "scroll2", { selector, position: "center" }, globals.timeout);
    printGroupResult(result, opts, globals.format);
  });

  // Smart queries
  for (const [cmd, method, argName] of [
    ["find-button", "findButton", "text"],
    ["find-element", "findElement", "text"],
    ["find-link", "findLink", "text"],
    ["find-input", "findInput", "label"],
  ] as const) {
    addGroupOptions(
      group
        .command(`${cmd} <${argName}>`)
        .description(`Find ${cmd.replace("find-", "")} across all devices`),
    ).action(async (arg: string, opts: GroupCommandOptions) => {
      const globals = getGlobals(program);
      const devices = getFilteredDevices(opts);
      const result = await executeSmartQuery(devices, method, { [argName]: arg }, globals.timeout);
      printSmartQueryResult(result, opts, globals.format);
    });
  }

  // Simple group commands (no args besides filter)
  for (const [cmd, method] of [
    ["a11y", "getAccessibilityTree"],
    ["dom", "getDOM"],
    ["console", "getConsoleMessages"],
    ["errors", "getJSErrors"],
    ["form-state", "getFormState"],
    ["visible", "getVisibleElements"],
  ] as const) {
    addGroupOptions(
      group
        .command(cmd)
        .description(`Get ${cmd} from all devices`),
    ).action(async (opts: GroupCommandOptions) => {
      const globals = getGlobals(program);
      const devices = getFilteredDevices(opts);
      const result = await executeGroup(devices, method, {}, globals.timeout);
      printGroupResult(result, opts, globals.format);
    });
  }

  // Eval
  addGroupOptions(
    group
      .command("eval <expression>")
      .description("Evaluate JS on all devices"),
  ).action(async (expression: string, opts: GroupCommandOptions) => {
    const globals = getGlobals(program);
    const devices = getFilteredDevices(opts);
    const result = await executeGroup(devices, "evaluate", { expression }, globals.timeout);
    printGroupResult(result, opts, globals.format);
  });

  // Keyboard show/hide
  addGroupOptions(
    group
      .command("keyboard-show")
      .description("Show keyboard on all devices"),
  ).action(async (opts: GroupCommandOptions) => {
    const globals = getGlobals(program);
    const devices = getFilteredDevices(opts);
    const result = await executeGroup(devices, "showKeyboard", {}, globals.timeout);
    printGroupResult(result, opts, globals.format);
  });

  addGroupOptions(
    group
      .command("keyboard-hide")
      .description("Hide keyboard on all devices"),
  ).action(async (opts: GroupCommandOptions) => {
    const globals = getGlobals(program);
    const devices = getFilteredDevices(opts);
    const result = await executeGroup(devices, "hideKeyboard", {}, globals.timeout);
    printGroupResult(result, opts, globals.format);
  });
}
