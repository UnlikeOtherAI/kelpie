import { createHash, randomUUID } from "node:crypto";
import { open, link, unlink, realpath } from "node:fs/promises";
import { basename, dirname, join } from "node:path";
import { z } from "zod";
import { scriptArtifactSchema, scriptArtifactChunkSchema, type ScriptArtifact } from "@unlikeotherai/kelpie-shared";
import { createPinnedCommandTransport, type PinnedCommandTransport } from "../client/http-client.js";
import type { DiscoveredDevice } from "../types.js";

const chunkSchema = scriptArtifactChunkSchema.extend({
  data: z.string().max(349_528).regex(/^[A-Za-z0-9+/]*={0,2}$/),
});

/** Pin one socket/grant. IDs never become paths; final/partial symlinks and existing files refuse exclusive creation. */
export async function downloadScriptArtifact(
  device: DiscoveredDevice,
  runId: string,
  rawManifest: unknown,
  destination: string,
  timeout: number,
  transport?: PinnedCommandTransport,
): Promise<ScriptArtifact> {
  const manifest = scriptArtifactSchema.parse(rawManifest);
  if (manifest.byteLength > 268_435_456) throw new Error("Artifact exceeds download bound");
  const send = transport ?? await createPinnedCommandTransport(device);
  // Resolve an explicitly chosen parent once; all remote identifiers stay in the HTTP request.
  const finalPath = join(await realpath(dirname(destination)), basename(destination));
  const partialPath = finalPath + ".partial-" + randomUUID();
  const file = await open(partialPath, "wx");
  const hash = createHash("sha256");
  let offset = 0;
  let verified = false;
  try {
    do {
      const response = await send("getScriptArtifact", { runId, artifactId: manifest.id, offset, length: 262_144 }, timeout);
      if (!response.ok) throw new Error("Artifact request failed");
      const chunk = chunkSchema.parse(response.data);
      const data = Buffer.from(chunk.data, "base64");
      if (chunk.runId !== runId || chunk.artifactId !== manifest.id || data.toString("base64") !== chunk.data ||
          data.length > 262_144 || chunk.offset !== offset || chunk.nextOffset !== offset + data.length ||
          chunk.nextOffset > manifest.byteLength || chunk.byteLength !== manifest.byteLength ||
          chunk.sha256 !== manifest.sha256 || chunk.mimeType !== manifest.mimeType ||
          chunk.eof !== (chunk.nextOffset === manifest.byteLength) || (!chunk.eof && !data.length)) {
        throw new Error("Invalid artifact chunk");
      }
      await file.writeFile(data);
      hash.update(data);
      offset = chunk.nextOffset;
      if (chunk.eof) break;
    } while (offset < manifest.byteLength);
    if (offset !== manifest.byteLength || hash.digest("hex") !== manifest.sha256) throw new Error("Artifact integrity mismatch");
    verified = true;
  } finally {
    let closed = false;
    try { await file.close(); closed = true; } finally { if (!verified || !closed) await unlink(partialPath); }
  }
  try {
    // Atomic exclusive promotion: a pre-existing file or symlink is never followed or replaced.
    await link(partialPath, finalPath);
  } catch (error) {
    await unlink(partialPath);
    throw error;
  }
  await unlink(partialPath);
  return manifest;
}
