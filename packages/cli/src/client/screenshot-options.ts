/**
 * Whether a device honoured the screenshot options it was sent. A device that
 * does not know `maxWidth` (or JPEG) silently returns the full image, and the
 * whole point of those options is to keep that image away from the caller —
 * so the CLI checks the result itself instead of trusting a platform table,
 * which would miss an older app build. `width` is the encoded image's pixel
 * width on every platform that reports it.
 */

export const SCREENSHOT_OPTION_UNSUPPORTED = "SCREENSHOT_OPTION_UNSUPPORTED";

/** The options a caller asked for, as sent to the device. */
export interface ScreenshotRequest {
  format?: unknown;
  maxWidth?: unknown;
}

/** The parts of a device's screenshot response the check reads. */
export interface ScreenshotAnswer {
  format?: unknown;
  width?: unknown;
}

export interface ScreenshotDevice {
  name?: string;
  platform?: string;
  version?: string;
}

export interface ScreenshotOptionFailure {
  success: false;
  error: { code: typeof SCREENSHOT_OPTION_UNSUPPORTED; message: string; option: "format" | "maxWidth" };
}

export function screenshotOptionError(
  request: ScreenshotRequest,
  answer: ScreenshotAnswer,
  device: ScreenshotDevice = {},
): ScreenshotOptionFailure | undefined {
  const app = describeDevice(device);
  if (request.format === "jpeg" && normalizeImageFormat(answer.format) !== "jpeg") {
    const returned = typeof answer.format === "string" ? answer.format : "png";
    return failure(
      "format",
      `JPEG was requested but ${app} returned ${returned}. Update the Kelpie app or omit format.`,
    );
  }
  if (typeof request.maxWidth === "number" && typeof answer.width === "number" && answer.width > request.maxWidth) {
    return failure(
      "maxWidth",
      `maxWidth=${request.maxWidth} was requested but ${app} returned a ${answer.width} px wide image, so it does not support maxWidth. Update the Kelpie app, omit maxWidth, or shrink the window with kelpie_resize_viewport.`,
    );
  }
  return undefined;
}

export function normalizeImageFormat(raw: unknown): "jpeg" | "png" {
  return raw === "jpeg" || raw === "jpg" ? "jpeg" : "png";
}

function failure(option: "format" | "maxWidth", message: string): ScreenshotOptionFailure {
  return { success: false, error: { code: SCREENSHOT_OPTION_UNSUPPORTED, message, option } };
}

function describeDevice(device: ScreenshotDevice): string {
  const parts = [device.platform, device.version].filter((part): part is string => Boolean(part));
  const name = device.name ? `"${device.name}"` : "the device";
  return parts.length > 0 ? `${name} (${parts.join(" ")})` : name;
}
