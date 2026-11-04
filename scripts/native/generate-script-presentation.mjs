// Test-only vectors. The native library never loads JavaScript or JSON per frame.
import { mkdir, stat, writeFile } from "node:fs/promises";
import { dirname } from "node:path";
import { fileURLToPath } from "node:url";

const source = new URL("../../packages/shared/src/script-presentation.ts", import.meta.url);
const compiled = new URL("../../packages/shared/dist/script-presentation.js", import.meta.url);
let sourceStat, compiledStat;
try { [sourceStat, compiledStat] = await Promise.all([stat(source), stat(compiled)]); }
catch { throw new Error("Build the authoritative shared package before presentation parity tests"); }
if (compiledStat.mtimeMs < sourceStat.mtimeMs) throw new Error("Shared presentation dist is stale; rebuild the shared package");
const { scriptPointerPosition, scriptTapPresentation, scriptTimelineProgress } = await import(compiled.href);
const output = process.argv[2];
if (!output) throw new Error("Expected ignored build-directory vector output path");
const progress = [-1, 0, 0.001, 0.1, 0.25, 0.5, 0.75, 0.9, 1, 2];
const motions = [
  { from: { x: 0, y: 0 }, to: { x: 300, y: 0 } },
  { from: { x: 50, y: 80 }, to: { x: -20, y: 300 } },
  { from: { x: 10, y: 10 }, to: { x: 10, y: 10 } },
];
const pointer = motions.flatMap(motion => ["c", "s"].flatMap(curve => progress.map(value => ({
  ...motion, curve, progress: value, expected: scriptPointerPosition({ ...motion, curve }, value),
}))));
const tap = progress.flatMap(value => [false, true].flatMap(wobble => [false, true].map(fade => ({
  progress: value, wobble, fade, expected: scriptTapPresentation(value, wobble, fade),
}))));
const timeline = [-10, 0, 50, 100, 200].flatMap(elapsed => [-1, 0, 100].map(duration => ({
  elapsed, duration, expected: scriptTimelineProgress(elapsed, duration),
})));
await mkdir(dirname(output), { recursive: true });
await writeFile(output, JSON.stringify({ source: fileURLToPath(source), pointer, tap, timeline }));
