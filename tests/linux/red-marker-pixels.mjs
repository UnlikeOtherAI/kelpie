// Neutral fixture UI only: channel excess survives palette quantization and fading.
export function redMarkerPixels(bytes, width, height) {
  if (bytes.length !== width * height * 3) throw Error("Unexpected RGB frame length");
  let count = 0, minX = width, minY = height, maxX = -1, maxY = -1, excess = 0;
  for (let pixel = 0; pixel < bytes.length; pixel += 3) {
    const r = bytes[pixel], g = bytes[pixel + 1], b = bytes[pixel + 2];
    // Green has the same three-bit quantizer as red; blue has only two bits.
    const red = r - g;
    if (red >= 35 && r >= b) {
      count++; excess += red;
      const position = pixel / 3, x = position % width, y = Math.floor(position / width);
      minX = Math.min(minX, x); maxX = Math.max(maxX, x);
      minY = Math.min(minY, y); maxY = Math.max(maxY, y);
    }
  }
  return { count, excess, bounds: count ? { minX, maxX, minY, maxY } : null };
}
