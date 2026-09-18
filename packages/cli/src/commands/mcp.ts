import type { Command } from "commander";
import { CLI_MCP_PORT, httpToMcp, type BrowserMcpTool } from "@unlikeotherai/kelpie-shared";
import { DEFAULT_MCP_BIND_HOST } from "../mcp/transport.js";
import { localBrowserDevice } from "./helpers.js";
import { sendCommand } from "../client/http-client.js";
import type { DiscoveredDevice } from "../types.js";

export function rejectsWindowsLocalHttpProxy(http: boolean | undefined, platform: string | undefined): boolean {
  return http === true && platform === "windows";
}

/** Read the running browser's own callable catalogue before exposing alias MCP tools. */
export async function localCallableTools(device: DiscoveredDevice): Promise<Set<BrowserMcpTool>> {
  const result = await sendCommand<{ supported?: unknown }>(device, "getCapabilities");
  const supported = result.data.supported;
  if (!result.ok || !Array.isArray(supported) || !supported.every((item) => typeof item === "string")) {
    throw new Error("Local browser did not return a valid callable capability catalogue");
  }
  return new Set(supported.flatMap((endpoint) => {
    const tool = httpToMcp[endpoint];
    return tool ? [tool] : [];
  }));
}

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
        const globals = program.opts<{ browser?: string }>();
        const local = globals.browser ? await localBrowserDevice(globals.browser) : undefined;
        if (globals.browser && !local) {
          process.stderr.write(`No ready local browser named ${globals.browser}\n`);
          process.exitCode = 4;
          return;
        }
        if (rejectsWindowsLocalHttpProxy(opts.http, local?.platform)) {
          process.stderr.write("Windows local aliases support MCP over CLI stdio only; use the browser's authenticated /mcp endpoint for HTTP.\n");
          process.exitCode = 4;
          return;
        }
        let callableTools: Set<BrowserMcpTool> | undefined;
        if (local?.platform === "windows") {
          try {
            callableTools = await localCallableTools(local);
          } catch (error) {
            process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
            process.exitCode = 4;
            return;
          }
        }
        const { createMcpServer } = await import("../mcp/server.js");
        const server = createMcpServer(local ?? undefined, callableTools);

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
