#!/usr/bin/env node
// Emit only bounded, validated numeric/hash/boolean evidence from fixed files.
import { constants } from "node:fs";
import { lstat, mkdir, open, realpath, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const scopes = ["installed-smoke", "installed-smoke-replay", "installed-smoke-resource", "installed-smoke-cli-only"];
const count = value => Number.isSafeInteger(value) && value >= 0 ? value : null;
const number = value => typeof value === "number" && Number.isFinite(value) ? value : null;
const bool = value => typeof value === "boolean" ? value : null;
const hash = value => typeof value === "string" && /^[a-f0-9]{64}$/.test(value) ? value : null;
const mime = value => ["image/png", "image/gif", "video/mp4"].includes(value) ? value : null;
const array = (value, map, limit = 1000) =>
  Array.isArray(value) && value.length <= limit ? value.map(map) : null;
function checks(value) {
  if (!Array.isArray(value) || value.length > 1000) return null;
  const passed = value.filter(item => item?.passed === true).length;
  const failed = value.filter(item => item?.passed === false).length;
  return { total: value.length, passed, failed, unknown: value.length - passed - failed };
}
// Reject symlinked components and check the opened file size before reading.
// The evidence root is a private CI output; it is not writable by another job.
async function load(root, ...parts) {
  let path = root;
  try {
    for (const part of parts) {
      path = join(path, part);
      if ((await lstat(path)).isSymbolicLink()) return null;
    }
    const file = await open(path, constants.O_RDONLY | (constants.O_NOFOLLOW ?? 0));
    try {
      const info = await file.stat();
      if (!info.isFile() || info.size > 8 * 1024 * 1024) return null;
      const data = Buffer.alloc(info.size + 1);
      const { bytesRead } = await file.read(data, 0, data.length, 0);
      if (bytesRead !== info.size) return null;
      return JSON.parse(data.subarray(0, bytesRead).toString("utf8"));
    } finally { await file.close(); }
  } catch { return null; }
}
const decoded = item => ({ sha256: hash(item?.sha256), mimeType: mime(item?.mimeType),
  decodedFrames: count(item?.decodedFrames), timestamps: array(item?.timestamps, number) });
const marker = item => ({ mimeType: mime(item?.mimeType),
  markerPixels: array(item?.markerPixels, count),
  centers: array(item?.centers, point => point ? { x: number(point.x), y: number(point.y) } : null),
  expected: item?.expected ? { x: number(item.expected.x), y: number(item.expected.y) } : null,
});
const terminal = item => ({ sha256: hash(item?.sha256), frames: count(item?.frames),
  finalPTS: number(item?.finalPTS), packetSize: count(item?.packetSize),
  nalLengthSize: count(item?.nalLengthSize), idr: bool(item?.idr) });
function mismatch(item) {
  if (!item) return null;
  return { kind: item.kind === "marker-tail" ? "marker-tail" : item.kind === undefined ? "frame-count" : null,
    sha256: hash(item.sha256), mimeType: mime(item.mimeType),
    manifestFrames: count(item.manifestFrames), decodedFrames: count(item.decodedFrames),
    byteLength: count(item.byteLength), pts: array(item.pts, number),
    redPixels: count(item.redPixels?.count) };
}
export async function summarize(directory) {
  const root = await realpath(directory);
  const result = { version: 1, scopes: {} };
  for (const scope of scopes) {
    const get = (...parts) => load(root, scope, ...parts);
    const [launch, alias, observations, inner, media, mismatched, idr, frames, pixels] = await Promise.all([
      get("capture", "launch-report.json"), get("alias", "report.json"),
      get("alias", "observations.json"), get("alias", "alias", "report.json"),
      get("capture", "media-verification.json"), get("capture", "count-mismatch.json"),
      get("capture", "terminal-idr.json"), get("capture", "all-frame-decode.json"),
      get("capture", "continuous-marker-pixels.json"),
    ]);
    if (![launch, alias, observations, inner, media, mismatched, idr, frames, pixels].some(Boolean)) continue;
    result.scopes[scope] = {
      native: checks(launch?.checks), alias: checks(alias?.checks),
      nativeCleanup: launch ? launch.cleanup === "owned app exited and readiness removed" : null,
      aliasCleanup: alias ? alias.cleanup === "supported public alias stop; readiness removed" : null,
      observations: checks(observations?.checks), cli: checks(inner?.checks),
      mediaArtifacts: count(media?.artifacts), allFramesDecoded: bool(media?.allFramesDecoded),
      continuousMarkerCenterAndFade: bool(media?.continuousMarkerCenterAndFade),
      terminalIDRVerified: bool(media?.terminalIDRVerified), mismatch: mismatch(mismatched?.mismatch),
      decoded: array(frames?.artifacts, decoded), markers: array(pixels?.evidence, marker),
      markerViolations: Array.isArray(pixels?.violations) ? count(pixels.violations.length) : null,
      terminalIDR: array(idr?.results, terminal),
    };
  }
  return result;
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  if (!process.argv[2]) throw Error("Expected evidence directory");
  const root = resolve(process.argv[2]);
  await mkdir(root, { recursive: true });
  await writeFile(join(root, "safe-diagnostics.json"), JSON.stringify(await summarize(root), null, 2) + "\n", { flag: "wx" });
}
