import { createServer } from "node:http";

/** Synthetic SSE commands only; never execute page-provided code or endpoints. */
export async function startReplacementFixture() {
  const events = [], sockets = new Set(), channels = new Map();
  const html = `<!doctype html><title>Replacement barrier fixture</title><style>
body{margin:0;background:white}a{position:absolute;left:150px;top:150px;width:160px;height:60px;display:grid;place-items:center;background:#eee;color:black}
</style><a id="next" data-object="original" href="/next">Next document</a><script>
const documentId=crypto.randomUUID();window.captureReplacement={documentId,x:230,y:180};
let sequence=0;const send=value=>navigator.sendBeacon('/events',new Blob([JSON.stringify({documentId,sequence:++sequence,time:performance.now(),...value})],{type:'application/json'}));
for(const type of ['pointerdown','click'])document.addEventListener(type,e=>{const target=e.target.closest('a');send({type,target:target?.id,object:target?.dataset.object,trusted:e.isTrusted,x:e.clientX,y:e.clientY});},true);
const control=new EventSource('/control?documentId='+documentId);
control.onopen=()=>send({type:'ready'});
control.onmessage=e=>{if(e.data!=='replace-next')return;const old=document.querySelector('#next'),copy=old.cloneNode(true);copy.dataset.object='replacement';old.replaceWith(copy);send({type:'replaced',oldConnected:old.isConnected});};
</script>`;
  let closing = false;
  const server = createServer((request, response) => {
    void (async () => {
      const url = new URL(request.url, "http://fixture.invalid");
      if (closing) { response.writeHead(503); response.end(); return; }
      if (request.method === "GET" && url.pathname === "/control") {
        const id = url.searchParams.get("documentId");
        if (!/^[a-f0-9-]{36}$/.test(id ?? "") || channels.has(id)) { response.writeHead(400); response.end(); return; }
        response.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-store" });
        response.write(": ready\n\n"); channels.set(id, response);
        response.once("close", () => { if (channels.get(id) === response) channels.delete(id); }); return;
      }
      if (request.method === "POST" && url.pathname === "/events") {
        const parts = []; let size = 0;
        for await (const part of request) { size += part.length; if (size > 16384) throw Error("Fixture event bound"); parts.push(part); }
        const event = JSON.parse(Buffer.concat(parts).toString("utf8"));
        if (!/^[a-f0-9-]{36}$/.test(event.documentId ?? "") ||
            !["ready", "replaced", "pointerdown", "click"].includes(event.type) || events.length >= 256)
          throw Error("Unexpected fixture event");
        events.push(event); response.writeHead(202); response.end(); return;
      }
      if (request.method !== "GET") { response.writeHead(405); response.end(); return; }
      response.writeHead(200, { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" });
      response.end(url.pathname === "/next" ? "<!doctype html><title>Unexpected activation</title>" : html);
    })().catch(() => response.destroy());
  });
  server.on("connection", socket => { sockets.add(socket); socket.once("close", () => sockets.delete(socket)); });
  await new Promise((resolve, reject) => { server.once("error", reject); server.listen(0, "127.0.0.1", resolve); });
  return {
    url: "http://127.0.0.1:" + server.address().port, events,
    replaceNext(documentId) {
      const response = channels.get(documentId);
      if (!response || response.destroyed) throw Error("Replacement setup lost its owned document");
      response.write("data: replace-next\n\n");
    },
    async close() {
      closing = true;
      const stopped = new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
      for (const response of channels.values()) response.end();
      for (const socket of sockets) socket.destroy();
      await stopped;
    },
  };
}
