import type { Command } from "commander";
import { CLI_MCP_PORT } from "@unlikeotherai/kelpie-shared";

export function registerMcp(program: Command): void {
  program
    .command("mcp")
    .description("Start as an MCP server (stdio or HTTP)")
    .option("--http", "Use HTTP/SSE transport instead of stdio")
    .option("--port <port>", "HTTP port (default 8421)", String(CLI_MCP_PORT))
    .action(async (opts: { http?: boolean; port?: string }) => {
      const { createMcpServer } = await import("../mcp/server.js");
      const server = createMcpServer();

      if (opts.http) {
        const { startHttp } = await import("../mcp/transport.js");
        await startHttp(server, Number(opts.port) || CLI_MCP_PORT);
      } else {
        const { startStdio } = await import("../mcp/transport.js");
        await startStdio(server);
      }
    });
}
