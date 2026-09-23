/**
 * Reads a JPEG's pixel size from its frame header and requires the file to
 * end with the end-of-image marker. Like decodePng, this avoids a graphics
 * dependency while proving the browser returned a complete encoded JPEG
 * rather than a relabelled PNG or a truncated buffer.
 */
export function readJpegSize(bytes) {
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8) throw new Error("Screenshot is not a JPEG file");
  if (bytes[bytes.length - 2] !== 0xff || bytes[bytes.length - 1] !== 0xd9) throw new Error("JPEG has no end-of-image marker");
  let offset = 2;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset] !== 0xff) throw new Error("JPEG segment marker is missing");
    const marker = bytes[offset + 1];
    if (marker === 0xff) {
      offset += 1;
      continue;
    }
    if (marker === 0xd9 || marker === 0xda) break;
    const length = bytes.readUInt16BE(offset + 2);
    const frame = marker >= 0xc0 && marker <= 0xcf && ![0xc4, 0xc8, 0xcc].includes(marker);
    if (frame) {
      if (offset + 9 > bytes.length) throw new Error("JPEG frame header is truncated");
      return { height: bytes.readUInt16BE(offset + 5), width: bytes.readUInt16BE(offset + 7) };
    }
    offset += 2 + length;
  }
  throw new Error("JPEG has no frame header before its scan");
}
