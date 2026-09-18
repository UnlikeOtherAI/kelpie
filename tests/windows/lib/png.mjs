import { inflateSync } from "node:zlib";

function readUint32(bytes, offset) {
  return bytes.readUInt32BE(offset);
}

/**
 * Decodes the PNG container and inflated scanlines. This deliberately avoids a
 * graphics dependency while proving the browser returned an encoded image,
 * rather than a CEF paint buffer mislabeled as PNG.
 */
export function decodePng(bytes) {
  const signature = "89504e470d0a1a0a";
  if (bytes.subarray(0, 8).toString("hex") !== signature) {
    throw new Error("Screenshot is not a PNG file");
  }

  let offset = 8;
  let width = 0;
  let height = 0;
  let bitDepth = 0;
  let colorType = 0;
  let interlace = 0;
  const compressed = [];
  let sawEnd = false;
  while (offset < bytes.length) {
    if (offset + 12 > bytes.length) throw new Error("PNG chunk is truncated");
    const length = readUint32(bytes, offset);
    const type = bytes.subarray(offset + 4, offset + 8).toString("ascii");
    const dataStart = offset + 8;
    const dataEnd = dataStart + length;
    if (dataEnd + 4 > bytes.length) throw new Error(`PNG ${type} chunk is truncated`);
    const data = bytes.subarray(dataStart, dataEnd);
    if (type === "IHDR") {
      if (length !== 13) throw new Error("PNG IHDR has an invalid size");
      width = readUint32(data, 0);
      height = readUint32(data, 4);
      bitDepth = data[8];
      colorType = data[9];
      interlace = data[12];
    } else if (type === "IDAT") {
      compressed.push(data);
    } else if (type === "IEND") {
      sawEnd = true;
      break;
    }
    offset = dataEnd + 4;
  }
  if (!sawEnd || width < 1 || height < 1 || compressed.length === 0) {
    throw new Error("PNG is missing required image chunks");
  }
  if (bitDepth !== 8 || ![0, 2, 4, 6].includes(colorType)) {
    throw new Error(`Unsupported PNG format: bit depth ${bitDepth}, color type ${colorType}`);
  }
  if (interlace !== 0) throw new Error("Interlaced PNG screenshots are not supported by this release validator");
  const channels = { 0: 1, 2: 3, 4: 2, 6: 4 }[colorType];
  const decoded = inflateSync(Buffer.concat(compressed));
  const scanlineBytes = 1 + width * channels;
  if (decoded.length !== scanlineBytes * height) {
    throw new Error("PNG decompressed scanlines have an invalid length");
  }
  for (let row = 0; row < height; row += 1) {
    if (decoded[row * scanlineBytes] > 4) throw new Error("PNG has an invalid scanline filter");
  }
  return { width, height, colorType };
}
