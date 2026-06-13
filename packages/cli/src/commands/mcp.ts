import type { Command } from "commander";
import { CLI_MCP_PORT } from "@unlikeotherai/kelpie-shared";
import { DEFAULT_MCP_BIND_HOST } from "../mcp/transport.js";

export function registerMcp(program: Command): void {
  program
    .command("mcp")
    .description("Start as an MCP server (stdio or HTTP)")
    .option("--http", "Use HTTP/SSE transport instead of stdio")
    .option("--port <port>", "HTTP port (default 8421)", String(CLI_MCP_PORT))
    .option(
      "--bind <host>",
      "HTTP bind host (default 127.0.0.1; non-loopback requires --unsafe-host)",
      DEFAULT_MCP_BIND_HOST,
    )
    .option(
      "--unsafe-host",
      "Allow binding to a non-loopback address (exposes stored tokens to the network)",
    )
    .action(
      async (opts: {
        http?: boolean;
        port?: string;
        bind?: string;
        unsafeHost?: boolean;
      }) => {
        const { createMcpServer } = await import("../mcp/server.js");
        const server = createMcpServer();

        if (opts.http) {
          const { startHttp } = await import("../mcp/transport.js");
          try {
            await startHttp(server, Number(opts.port) || CLI_MCP_PORT, {
              bindHost: opts.bind,
              unsafeHost: opts.unsafeHost,
            });
          } catch (err) {
            process.stderr.write(`${err instanceof Error ? err.message : String(err)}\n`);
            process.exitCode = 1;
          }
        } else {
          const { startStdio } = await import("../mcp/transport.js");
          await startStdio(server);
        }
      },
    );
}
