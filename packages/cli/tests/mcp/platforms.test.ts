import { describe, it, expect } from "vitest";
import { browserTools } from "../../src/mcp/tools.js";
import {
  BrowserToolUnsupportedPlatforms,
  type Platform,
} from "../../../shared/src/index.js";

const ALL_PLATFORMS: readonly Platform[] = ["ios", "android", "macos", "linux", "windows"];

/**
 * Cross-checks the per-tool `platforms` array declared in `mcp/tools.ts`
 * against the unsupported-platforms catalog in `@unlikeotherai/kelpie-shared`.
 *
 * Goal: if a tool declares `platforms`, the set must equal
 * (all platforms) MINUS (unsupported platforms for that tool).
 * This prevents the MCP server from advertising platform support that the
 * shared catalog says is missing — and vice versa.
 */
describe("MCP tool platform metadata matches shared unsupported catalog", () => {
  for (const tool of browserTools) {
    if (!tool.platforms) continue;
    const unsupported =
      BrowserToolUnsupportedPlatforms[
        tool.name as keyof typeof BrowserToolUnsupportedPlatforms
      ] ?? [];
    const expected = ALL_PLATFORMS.filter((p) => !unsupported.includes(p));

    it(`${tool.name} declares the platforms left after subtracting unsupported`, () => {
      const declared = [...(tool.platforms ?? [])].sort();
      const expectedSorted = [...expected].sort();
      expect(declared).toEqual(expectedSorted);
    });
  }

  it("geolocation and request-interception tools declare an empty platforms array (unsupported everywhere)", () => {
    const names = [
      "kelpie_set_geolocation",
      "kelpie_clear_geolocation",
      "kelpie_set_request_interception",
      "kelpie_get_intercepted_requests",
      "kelpie_clear_request_interception",
    ];
    for (const name of names) {
      const tool = browserTools.find((t) => t.name === name);
      expect(tool, `${name} should be registered`).toBeDefined();
      expect(tool!.platforms, `${name} should declare an explicit platforms array`).toBeDefined();
      expect(tool!.platforms).toHaveLength(0);
    }
  });
});
