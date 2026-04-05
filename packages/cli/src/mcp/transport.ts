import { createServer } from "node:http";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";

export async function startStdio(server: McpServer): Promise<void> {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

export async function startHttp(server: McpServer, port: number): Promise<void> {
  const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: () => crypto.randomUUID() });

  const httpServer = createServer(async (req, res) => {
    const url = new URL(req.url ?? "/", `http://localhost:${port}`);
    if (url.pathname === "/mcp") {
      await transport.handleRequest(req, res);
    } else if (url.pathname === "/health") {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ status: "ok" }));
    } else {
      res.writeHead(404);
      res.end("Not found");
    }
  });

  await server.connect(transport);
  httpServer.listen(port, () => {
    console.error(`Kelpie MCP server listening on http://localhost:${port}/mcp`);
  });

  await new Promise<void>((resolve) => {
    process.on("SIGINT", () => { httpServer.close(); resolve(); });
    process.on("SIGTERM", () => { httpServer.close(); resolve(); });
  });
}
