/**
 * Cut `bytes` into pieces of 1…chunkMax bytes, always cutting inside every
 * "data:" field name and after the first byte of every multibyte UTF-8
 * sequence, so a client that decodes per chunk or matches "data:" per chunk
 * is guaranteed to break.
 */
export function chunkBytes(bytes, chunkMax, random) {
  const forced = new Set();
  const marker = Buffer.from("data:");
  for (let at = bytes.indexOf(marker); at !== -1; at = bytes.indexOf(marker, at + 1)) forced.add(at + 2);
  for (let i = 0; i < bytes.length; i += 1) if (bytes[i] >= 0xc0) forced.add(i + 1);
  const chunks = [];
  let start = 0;
  while (start < bytes.length) {
    let end = Math.min(bytes.length, start + 1 + Math.floor(random() * chunkMax));
    for (let i = start + 1; i < end; i += 1) {
      if (forced.has(i)) { end = i; break; }
    }
    chunks.push(bytes.subarray(start, end));
    start = end;
  }
  return chunks;
}
