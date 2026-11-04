import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

export async function startCaptureFixture({ host = "127.0.0.1", port = 0 } = {}) {
  const assets = new Map(await Promise.all([
    ["/", "fixture.html", "text/html; charset=utf-8"],
    ["/fixture.js", "fixture.js", "text/javascript; charset=utf-8"],
  ].map(async ([path, name, type]) => [path, { type, body: await readFile(new URL(name, import.meta.url)) }])));
  const events = [];
  let dropped = 0;
  const write = (response, status, type, body) => {
    response.writeHead(status, { "content-type": type, "cache-control": "no-store",
      "x-content-type-options": "nosniff", "content-length": Buffer.byteLength(body) });
    response.end(body);
  };
  const server = createServer(async (request, response) => {
    const path = new URL(request.url ?? "/", "http://fixture.invalid").pathname;
    if (request.method === "POST" && path === "/events") {
      let length = 0;
      const chunks = [];
      for await (const chunk of request) {
        length += chunk.length;
        if (length > 16384) return write(response, 413, "text/plain", "event too large");
        chunks.push(chunk);
      }
      try {
        const event = JSON.parse(Buffer.concat(chunks).toString("utf8"));
        if (!event || typeof event !== "object" || typeof event.documentId !== "string"
          || event.documentId.length > 64 || typeof event.type !== "string") throw new Error("invalid event");
        if (events.length < 10000) events.push(event); else dropped++;
        write(response, 202, "text/plain", "accepted");
      } catch { write(response, 400, "text/plain", "invalid event"); }
      return;
    }
    if (request.method !== "GET") return write(response, 405, "text/plain", "method not allowed");
    if (path === "/events") return write(response, 200, "application/json", JSON.stringify({ events, dropped }));
    if (path === "/next" || path === "/details") return write(response, 200, "text/html",
      '<!doctype html><title>Next fixture document</title><h1>Next document</h1><a href="/">Return to fixture</a>');
    const asset = assets.get(path);
    if (asset) return write(response, 200, asset.type, asset.body);
    write(response, 404, "text/plain", "not found");
  });
  await new Promise((resolve, reject) => {
    server.once("error", reject); server.listen(port, host, resolve);
  });
  return {
    url: `http://${host}:${server.address().port}`, events,
    close: () => new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve())),
  };
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const fixture = await startCaptureFixture({
    host: process.env.CAPTURE_FIXTURE_HOST ?? "127.0.0.1", port: Number(process.env.CAPTURE_FIXTURE_PORT ?? 0),
  });
  console.log(fixture.url);
  for (const signal of ["SIGINT", "SIGTERM"]) process.once(signal, async () => { await fixture.close(); });
}
