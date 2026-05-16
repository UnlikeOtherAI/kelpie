import type { IncomingMessage, ServerResponse } from "node:http";
import { createServer } from "node:http";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import {
  makeErrorResponse,
  PARSE_ERROR_CODE,
  validatePayload,
} from "./jsonrpc.js";

export async function startStdio(server: McpServer): Promise<void> {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

const MAX_BODY_BYTES = 1_048_576; // 1 MiB — generous for MCP envelopes; rejects accidental floods.

async function readBody(req: IncomingMessage): Promise<string> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    let total = 0;
    req.on("data", (chunk: Buffer) => {
      total += chunk.length;
      if (total > MAX_BODY_BYTES) {
        reject(new Error("payload too large"));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => {
      resolve(Buffer.concat(chunks).toString("utf8"));
    });
    req.on("error", reject);
  });
}

function writeJsonRpcError(
  res: ServerResponse,
  status: number,
  id: string | number | null,
  code: number,
  message: string,
): void {
  res.writeHead(status, { "Content-Type": "application/json" });
  res.end(JSON.stringify(makeErrorResponse(id, { code, message })));
}

async function handleMcpPost(
  transport: StreamableHTTPServerTransport,
  req: IncomingMessage,
  res: ServerResponse,
): Promise<void> {
  let raw: string;
  try {
    raw = await readBody(req);
  } catch (err) {
    writeJsonRpcError(res, 413, null, PARSE_ERROR_CODE, (err as Error).message);
    return;
  }

  // Empty body is allowed for some non-POST routes; on POST it is invalid JSON.
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    writeJsonRpcError(res, 400, null, PARSE_ERROR_CODE, "Parse error: invalid JSON");
    return;
  }

  const validation = validatePayload(parsed);
  if (!validation.ok) {
    writeJsonRpcError(res, 400, validation.id, validation.error.code, validation.error.message);
    return;
  }

  await transport.handleRequest(req, res, parsed);
}

export async function startHttp(server: McpServer, port: number): Promise<void> {
  const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: () => crypto.randomUUID() });

  const httpServer = createServer((req, res) => {
    const url = new URL(req.url ?? "/", `http://localhost:${port}`);
    if (url.pathname === "/mcp") {
      const handler = req.method === "POST"
        ? handleMcpPost(transport, req, res)
        : transport.handleRequest(req, res);
      handler.catch((err: unknown) => {
        console.error("MCP transport error:", err);
        if (!res.headersSent) {
          res.writeHead(500);
          res.end();
        }
      });
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
