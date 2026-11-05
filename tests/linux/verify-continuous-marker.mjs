#!/usr/bin/env node
// Independent decoded-pixel evidence for the shared continuous red-marker fixture.
import assert from "node:assert/strict";
import { redMarkerPixels } from "./red-marker-pixels.mjs";
import { readFile, writeFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
const [inputPath, outputPath] = process.argv.slice(2);
assert.ok(inputPath && outputPath, "Provide downloaded media-input.json and output JSON");
const report = JSON.parse(await readFile(inputPath, "utf8"));
const event = report.checks.find(check => check.name.startsWith("continuous "))?.detail?.event;
assert.ok(event?.trusted && event.hit === "unique");
const evidence = [], violations = [];
for (const item of report.artifacts) {
  const scale = item.width / event.viewport.width;
  const cx = event.x * scale, cy = event.y * scale, radius = Math.ceil(24 * scale + 3);
  const left = Math.max(0, Math.floor(cx - radius)), top = Math.max(0, Math.floor(cy - radius));
  const width = Math.min(item.width - left, 2 * radius + 1);
  const height = Math.min(item.height - top, 2 * radius + 1);
  const result = spawnSync(process.env.FFMPEG ?? "ffmpeg", ["-v", "error", "-threads", "1",
    "-i", item.file, "-vf", `format=rgb24,crop=${width}:${height}:${left}:${top}:exact=1`,
    "-fps_mode", "passthrough", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
  { timeout: 30000, maxBuffer: 16 * 1024 * 1024 });
  assert.equal(result.status, 0, result.stderr?.toString() ?? result.error?.message);
  const size = width * height * 3, bytes = result.stdout;
  assert.equal(bytes.length % size, 0);
  const counts = [], centers = [], frames = [];
  for (let offset = 0; offset < bytes.length; offset += size) {
    const pixels = redMarkerPixels(bytes.subarray(offset, offset + size), width, height);
    const { count, bounds } = pixels;
    // Sparse near-transparent pixels do not establish the geometric center.
    const reliable = count > 100 && count >= Math.PI * (24 * scale) ** 2 * 0.4;
    const center = reliable ? { x: left + (bounds.minX + bounds.maxX) / 2, y: top + (bounds.minY + bounds.maxY) / 2 } : null;
    frames.push({ ...pixels, reliableCenter: reliable });
    if (center && (Math.abs(center.x - cx) > 4 || Math.abs(center.y - cy) > 4))
      violations.push({ id: item.id, frame: counts.length, count, expected: { x: cx, y: cy }, observed: center,
        message: "Decoded marker center differs from actual trusted target center" });
    counts.push(count); centers.push(center);
  }
  if (item.frameCount !== undefined) assert.equal(counts.length, item.frameCount);
  if (item.mimeType !== "image/png") {
    assert.ok(centers.some(Boolean), "Movie lacks enough marker area for a reliable target-center check");
    assert.equal(counts[0], 0, "Pre-action baseline unexpectedly has target marker");
    assert.equal(counts.at(-1), 0, "Marker did not fade from final movie frame");
  }
  evidence.push({ id: item.id, mimeType: item.mimeType, crop: { left, top, width, height }, expected: { x: cx, y: cy }, markerPixels: counts, centers, frames });
}
assert.ok(evidence.filter(item => item.mimeType === "image/png").some(item => item.markerPixels[0] > 100),
  "No step PNG preserved the target marker");
await writeFile(outputPath, JSON.stringify({ source: report.source, event, evidence, violations }, null, 2));
assert.equal(violations.length, 0, "Decoded marker center differs; see persisted frame evidence");
console.log(JSON.stringify({ targetCenterPixelsVerified: true, artifacts: evidence.length }));
