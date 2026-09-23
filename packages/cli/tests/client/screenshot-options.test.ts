import { describe, expect, it } from "vitest";
import { screenshotOptionError } from "../../src/client/screenshot-options.js";

describe("screenshotOptionError", () => {
  it("accepts a result that honours every requested option", () => {
    expect(screenshotOptionError({ format: "jpeg", maxWidth: 960 }, { format: "jpeg", width: 960 })).toBeUndefined();
    expect(screenshotOptionError({ format: "jpeg", maxWidth: 960 }, { format: "jpeg", width: 390 })).toBeUndefined();
  });

  it("accepts anything when no option was requested", () => {
    expect(screenshotOptionError({}, { format: "png", width: 5000 })).toBeUndefined();
    expect(screenshotOptionError({ format: "png" }, { format: "png", width: 5000 })).toBeUndefined();
  });

  it("treats a jpg label as JPEG", () => {
    expect(screenshotOptionError({ format: "jpeg" }, { format: "jpg" })).toBeUndefined();
  });

  it("names an unhonoured JPEG request", () => {
    const failure = screenshotOptionError({ format: "jpeg" }, { format: "png" }, { name: "win", platform: "windows" });
    expect(failure).toEqual({
      success: false,
      error: {
        code: "SCREENSHOT_OPTION_UNSUPPORTED",
        option: "format",
        message: "JPEG was requested but \"win\" (windows) returned png. Update the Kelpie app or omit format.",
      },
    });
  });

  it("names an unhonoured maxWidth and says what came back", () => {
    const failure = screenshotOptionError({ maxWidth: 960 }, { width: 1918 });
    expect(failure?.error.option).toBe("maxWidth");
    expect(failure?.error.message).toContain("maxWidth=960");
    expect(failure?.error.message).toContain("the device returned a 1918 px wide image");
    expect(failure?.error.message).toContain("kelpie_resize_viewport");
  });

  it("cannot judge maxWidth without a reported width, so it lets the result through", () => {
    expect(screenshotOptionError({ maxWidth: 960 }, { format: "png" })).toBeUndefined();
  });
});
