import assert from "node:assert/strict";
import { test } from "node:test";
import { redMarkerPixels } from "./red-marker-pixels.mjs";
const size = 81, center = 40, radius = 24;
const quantize = ([r, g, b]) => [
  Math.floor((r >> 5) * 255 / 7), Math.floor((g >> 5) * 255 / 7), Math.floor((b >> 6) * 255 / 3),
];
function frame(alpha, palette = true) {
  const bytes = Buffer.alloc(size * size * 3);
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
    // White/gray button surfaces plus black label pixels, never red page content.
    const base = x % 11 < 2 ? 0 : y < center ? 255 : 180;
    const inside = Math.hypot(x - center, y - center) <= radius;
    const color = [245, 66, 66].map(channel => Math.round(inside ? channel * alpha + base * (1 - alpha) : base));
    bytes.set(palette ? quantize(color) : color, (y * size + x) * 3);
  }
  return bytes;
}
test("faded marker retains its center across neutral UI and 3/3/2 palette", () => {
  for (const alpha of [0.7, 0.5, 0.3]) for (const palette of [false, true]) {
    const found = redMarkerPixels(frame(alpha, palette), size, size);
    assert.ok(found.count > 1500);
    assert.deepEqual(found.bounds, { minX: 16, maxX: 64, minY: 16, maxY: 64 });
  }
});
test("old absolute threshold biases a faded palette marker toward gray button pixels", () => {
  const bytes = frame(0.5), ys = [];
  for (let i = 0; i < bytes.length; i += 3)
    if (bytes[i] > 190 && bytes[i] - bytes[i + 1] > 80 && bytes[i + 1] < 160 && bytes[i + 2] < 160)
      ys.push(Math.floor(i / 3 / size));
  assert.ok(ys.length > 100);
  assert.ok((Math.min(...ys) + Math.max(...ys)) / 2 - center > 4);
});
test("neutral button text, blank UI and near-zero alpha are not reliable marker evidence", () => {
  for (const alpha of [0, 0.01]) for (const palette of [false, true])
    assert.equal(redMarkerPixels(frame(alpha, palette), size, size).count, 0);
  const blue = Buffer.from(Array.from({ length: size * size }, () => [0, 80, 255]).flat());
  assert.equal(redMarkerPixels(blue, size, size).count, 0);
});
