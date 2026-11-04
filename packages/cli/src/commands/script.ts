import { runScriptFile, downloadRunArtifact, controlScriptRun, type ScriptRunOptions } from "./script-run.js";
import type { Command } from "commander";
import { deviceCommand } from "./helpers.js";

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
  script.command("run <file>")
    .description("Run a recording script from a JSON file")
    .option("--inputs <file>", "JSON object binding declared workflow inputs")
    .option("--secret <reference=ENV...>", "Explicit secret reference to host environment variable")
    .option("--output <directory>", "Download and integrity-check run artifacts")
    .action(async (file: string, options: ScriptRunOptions) => { await runScriptFile(program, file, options); });
  script.command("download <runId> <artifactId> <file>")
    .description("Download one run-owned artifact and verify its bytes")
    .action(async (runId: string, artifactId: string, file: string) => { await downloadRunArtifact(program, runId, artifactId, file); });
  script.command("abort")
    .description("Abort the active recording script")
    .option("--run-id <id>", "Run owned by the current authenticated session")
    .option("--pinned", "Use the current exact socket/grant without pairing or fallback")
    .action(async (options: { runId?: string; pinned?: boolean }) => { await controlScriptRun(program, "abortScript", options.runId, options.pinned); });
  script.command("status")
    .description("Get recording script playback status")
    .option("--run-id <id>", "Run owned by the current authenticated session")
    .option("--pinned", "Use the current exact socket/grant without pairing or fallback")
    .action(async (options: { runId?: string; pinned?: boolean }) => { await controlScriptRun(program, "getScriptStatus", options.runId, options.pinned); });
}