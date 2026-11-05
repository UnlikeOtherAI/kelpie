#!/usr/bin/env node
// Independent decoded-pixel evidence for the shared continuous red-marker fixture.
import assert from "node:assert/strict";
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
  const counts = [], centers = [];
  for (let offset = 0; offset < bytes.length; offset += size) {
    let count = 0, minX = width, minY = height, maxX = -1, maxY = -1;
    for (let pixel = offset; pixel < offset + size; pixel += 3) {
      const r = bytes[pixel], g = bytes[pixel + 1], b = bytes[pixel + 2];
      // Fixture marker is #F54242 composited at 70% opacity over neutral UI.
      if (r > 190 && r - g > 80 && g < 160 && b < 160) {
        count++; const position = (pixel - offset) / 3, x = position % width, y = Math.floor(position / width);
        minX = Math.min(minX, x); maxX = Math.max(maxX, x); minY = Math.min(minY, y); maxY = Math.max(maxY, y);
      }
    }
    const center = count > 100 ? { x: left + (minX + maxX) / 2, y: top + (minY + maxY) / 2 } : null;
    if (center && (Math.abs(center.x - cx) > 4 || Math.abs(center.y - cy) > 4))
      violations.push({ id: item.id, frame: counts.length, count, expected: { x: cx, y: cy }, observed: center,
        message: "Decoded marker center differs from actual trusted target center" });
    counts.push(count); centers.push(center);
  }
  if (item.frameCount !== undefined) assert.equal(counts.length, item.frameCount);
  if (item.mimeType !== "image/png") {
    assert.ok(counts.some(count => count > 100), "Movie lacks marker at actual trusted target center");
    assert.equal(counts[0], 0, "Pre-action baseline unexpectedly has target marker");
    assert.equal(counts.at(-1), 0, "Marker did not fade from final movie frame");
  }
  evidence.push({ id: item.id, mimeType: item.mimeType, crop: { left, top, width, height }, expected: { x: cx, y: cy }, markerPixels: counts, centers });
}
assert.ok(evidence.filter(item => item.mimeType === "image/png").some(item => item.markerPixels[0] > 100),
  "No step PNG preserved the target marker");
await writeFile(outputPath, JSON.stringify({ source: report.source, event, evidence, violations }, null, 2));
assert.equal(violations.length, 0, "Decoded marker center differs; see persisted frame evidence");
console.log(JSON.stringify({ targetCenterPixelsVerified: true, artifacts: evidence.length }));
