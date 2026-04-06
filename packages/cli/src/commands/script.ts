import { readFile } from "node:fs/promises";
import type { Command } from "commander";
import { deviceCommand } from "./helpers.js";

async function readScriptFile(path: string): Promise<Record<string, unknown>> {
  const raw = await readFile(path, "utf8");
  const parsed = JSON.parse(raw) as unknown;
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("Script file must contain a JSON object");
  }
  return parsed as Record<string, unknown>;
}

export function registerScript(program: Command): void {
  program
    .command("swipe <fromX> <fromY> <toX> <toY>")
    .description("Swipe between two viewport coordinates")
    .option("--duration <ms>", "Swipe duration in milliseconds")
    .option("--steps <count>", "Interpolation steps for the swipe")
    .option("--color <hex>", "Swipe overlay color")
    .action(async (
      fromX: string,
      fromY: string,
      toX: string,
      toY: string,
      opts: { duration?: string; steps?: string; color?: string },
    ) => {
      const body: Record<string, unknown> = {
        from: { x: Number(fromX), y: Number(fromY) },
        to: { x: Number(toX), y: Number(toY) },
      };
      if (opts.duration) body.durationMs = Number(opts.duration);
      if (opts.steps) body.steps = Number(opts.steps);
      if (opts.color) body.color = opts.color;
      await deviceCommand(program, "swipe", body);
    });

  const commentary = program.command("commentary").description("Show or hide commentary overlays");

  commentary
    .command("show <text>")
    .description("Show a commentary pill inside the viewport")
    .option("--position <position>", "Commentary position: top, center, or bottom")
    .option("--duration <ms>", "How long to show commentary. Use 0 to persist.")
    .action(async (text: string, opts: { position?: string; duration?: string }) => {
      const body: Record<string, unknown> = { text };
      if (opts.position) body.position = opts.position;
      if (opts.duration) body.durationMs = Number(opts.duration);
      await deviceCommand(program, "showCommentary", body);
    });

  commentary
    .command("hide")
    .description("Hide the active commentary overlay")
    .action(async () => {
      await deviceCommand(program, "hideCommentary");
    });

  const highlight = program.command("highlight").description("Show or hide element highlights");

  highlight
    .command("show <selector>")
    .description("Draw a highlight ring around an element")
    .option("--color <hex>", "Highlight color")
    .option("--thickness <px>", "Stroke width in pixels")
    .option("--padding <px>", "Padding around the element in pixels")
    .option("--animation <mode>", "Highlight animation: appear or draw")
    .option("--duration <ms>", "How long to show the highlight. Use 0 to persist.")
    .action(async (
      selector: string,
      opts: { color?: string; thickness?: string; padding?: string; animation?: string; duration?: string },
    ) => {
      const body: Record<string, unknown> = { selector };
      if (opts.color) body.color = opts.color;
      if (opts.thickness) body.thickness = Number(opts.thickness);
      if (opts.padding) body.padding = Number(opts.padding);
      if (opts.animation) body.animation = opts.animation;
      if (opts.duration) body.durationMs = Number(opts.duration);
      await deviceCommand(program, "highlight", body);
    });

  highlight
    .command("hide")
    .description("Hide the active highlight overlay")
    .action(async () => {
      await deviceCommand(program, "hideHighlight");
    });

  const script = program.command("script").description("Run and manage scripted recording sessions");

  script
    .command("run <file>")
    .description("Run a recording script from a JSON file")
    .action(async (file: string) => {
      const body = await readScriptFile(file);
      await deviceCommand(program, "playScript", body);
    });

  script
    .command("abort")
    .description("Abort the active recording script")
    .action(async () => {
      await deviceCommand(program, "abortScript");
    });

  script
    .command("status")
    .description("Get recording script playback status")
    .action(async () => {
      await deviceCommand(program, "getScriptStatus");
    });
}
