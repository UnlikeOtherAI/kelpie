#!/usr/bin/env node
// Only fixed counts and booleans leave the private installed-test outputs.
import { readFile, mkdir, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const scopes = ["installed-smoke", "installed-smoke-replay", "installed-smoke-resource", "installed-smoke-cli-only"];
const count = value => Number.isSafeInteger(value) && value >= 0 ? value : null;
const bool = value => typeof value === "boolean" ? value : null;
function checks(value) {
  if (!Array.isArray(value) || value.length > 1000) return null;
  return { total: value.length, passed: value.filter(item => item?.passed === true).length,
    failed: value.filter(item => item?.passed === false).length };
}
async function load(path) {
  try {
    const data = await readFile(path);
    if (data.length > 8 * 1024 * 1024) return null;
    return JSON.parse(data.toString("utf8"));
  } catch { return null; }
}
export async function summarize(root) {
  const result = { version: 1, scopes: {} };
  for (const scope of scopes) {
    const base = join(root, scope);
    const [launch, alias, observations, inner, media, mismatch, idr] = await Promise.all([
      load(join(base, "capture", "launch-report.json")),
      load(join(base, "alias", "report.json")),
      load(join(base, "alias", "observations.json")),
      load(join(base, "alias", "alias", "report.json")),
      load(join(base, "capture", "media-verification.json")),
      load(join(base, "capture", "count-mismatch.json")),
      load(join(base, "capture", "terminal-idr.json")),
    ]);
    if (![launch, alias, observations, inner, media, mismatch, idr].some(Boolean)) continue;
    result.scopes[scope] = {
      native: checks(launch?.checks), alias: checks(alias?.checks),
      observations: checks(observations?.checks), cli: checks(inner?.checks),
      mediaArtifacts: count(media?.artifacts), allFramesDecoded: bool(media?.allFramesDecoded),
      continuousMarkerCenterAndFade: bool(media?.continuousMarkerCenterAndFade),
      terminalIDRVerified: bool(media?.terminalIDRVerified),
      mismatch: mismatch?.mismatch ? {
        kind: ["frame-count", "marker-tail"].includes(mismatch.mismatch.kind) ? mismatch.mismatch.kind : null,
        manifestFrames: count(mismatch.mismatch.manifestFrames), decodedFrames: count(mismatch.mismatch.decodedFrames),
        byteLength: count(mismatch.mismatch.byteLength),
        sha256: /^[a-f0-9]{64}$/.test(mismatch.mismatch.sha256 ?? "") ? mismatch.mismatch.sha256 : null,
        mimeType: ["image/gif", "video/mp4"].includes(mismatch.mismatch.mimeType) ? mismatch.mismatch.mimeType : null,
      } : null,
      terminalIDRCount: Array.isArray(idr?.results) ? count(idr.results.length) : null,
    };
  }
  return result;
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  if (!process.argv[2]) throw Error("Expected evidence directory");
  const root = resolve(process.argv[2]);
  await mkdir(root, { recursive: true });
  await writeFile(join(root, "safe-diagnostics.json"), JSON.stringify(await summarize(root), null, 2) + "\n");
}
