import type { Command } from "commander";

export function registerWorker(program: Command): void {
  program.command("worker").description("Use an operator-managed external browser worker")
    .command("mcp").description("Start stdio MCP with bounded owned sessions")
    .requiredOption("--config <path>", "Operator JSON with endpoint environment reference and explicit origin/resource policy")
    .action(async (options: { config: string }) => {
      try {
        const { startWorkerMcp } = await import("../worker/runtime.js");
        await startWorkerMcp(options.config);
      } catch {
        process.stderr.write("Worker startup failed. Check the operator configuration and endpoint.\n");
        process.exitCode = 1;
      }
    });
}
