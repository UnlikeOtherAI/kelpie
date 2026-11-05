import type { Command } from "commander";

export function registerWorker(program: Command): void {
  program.command("worker").description("Use an operator-managed external browser worker")
    .command("mcp").description("Start stdio MCP with bounded owned sessions")
    .requiredOption("--config <path>", "Operator JSON with endpoint environment reference and explicit origin/resource policy")
    .action(async (options: { config: string }) => {
      try {
        const { startWorkerMcp } = await import("../worker/runtime.js");
        const version = program.version();
        if (!version) throw new Error("CLI version unavailable");
        await startWorkerMcp(options.config, version);
      } catch {
        process.stderr.write("Worker startup failed. Check the operator configuration and endpoint.\n");
        process.exitCode = 1;
      }
    });
}
