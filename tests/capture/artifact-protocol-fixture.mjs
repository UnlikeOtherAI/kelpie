import { createServer } from "node:http";
import { deflateSync } from "node:zlib";
import { createHash } from "node:crypto";

function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
  }
  return (crc ^ 0xffffffff) >>> 0;
}
function chunk(type, bytes) {
  const body = Buffer.concat([Buffer.from(type), bytes]), size = Buffer.alloc(4), crc = Buffer.alloc(4);
  size.writeUInt32BE(bytes.length); crc.writeUInt32BE(crc32(body));
  return Buffer.concat([size, body, crc]);
}
/** Fixed synthetic RGB noise, no page/user data; native screenshot must still exceed262KiB. */
export function artifactProtocolPng() {
  const width = 512, height = 512, raw = Buffer.alloc((width * 3 + 1) * height);
  let state = 0x13579bdf;
  for (let y = 0, index = 0; y < height; y++) {
    raw[index++] = 0;
    for (let x = 0; x < width * 3; x++) {
      state ^= state << 13; state ^= state >>> 17; state ^= state << 5;
      raw[index++] = state & 255;
    }
  }
  const header = Buffer.alloc(13); header.writeUInt32BE(width); header.writeUInt32BE(height, 4);
  header[8] = 8; header[9] = 2;
  return Buffer.concat([Buffer.from("89504e470d0a1a0a", "hex"),
    chunk("IHDR", header), chunk("IDAT", deflateSync(raw, { level: 0 })), chunk("IEND", Buffer.alloc(0))]);
}
export async function startArtifactProtocolFixture() {
  const png = artifactProtocolPng(), sockets = new Set();
  const html = '<!doctype html><title>Nonprivate artifact protocol fixture</title><style>body{margin:0}img{display:block;width:512px;height:512px}</style><img src="/noise.png" width="512" height="512" alt="Deterministic synthetic noise">';
  const server = createServer((request, response) => {
    const image = request.url === "/noise.png", body = image ? png : Buffer.from(html);
    response.writeHead(200, { "content-type": image ? "image/png" : "text/html; charset=utf-8",
      "content-length": body.length, "cache-control": "no-store" }); response.end(body);
  });
  server.on("connection", socket => { sockets.add(socket); socket.once("close", () => sockets.delete(socket)); });
  await new Promise((resolve, reject) => { server.once("error", reject); server.listen(0, "127.0.0.1", resolve); });
  return { url: "http://127.0.0.1:" + server.address().port, png,
    fixtureSha256: createHash("sha256").update(png).digest("hex"),
    async close() {
      const closed = new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
      for (const socket of sockets) socket.destroy();
      await closed;
    } };
}
