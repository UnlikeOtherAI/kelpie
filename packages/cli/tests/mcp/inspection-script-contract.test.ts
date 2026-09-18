import { describe, expect, it } from "vitest";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

function rawScript(source: string, name: string): string {
  const match = new RegExp(`${name}[\\s\\S]*?R"JS\\(\\r?\\n([\\s\\S]*?)\\r?\\n\\)JS`).exec(source);
  if (!match) throw new Error(`Missing ${name}`);
  return match[1] ?? "";
}

describe("desktop inspection JavaScript", () => {
  it("parses each reusable browser expression before native evaluation", async () => {
    const source = await readFile(resolve("../../native/engine-chromium-desktop/src/handlers/inspection_scripts.h"), "utf8");
    for (const name of ["kVisibleElementsScript", "kPageTextScript", "kFormStateScript"]) {
      // The browser engine executes these expressions; compile them with V8 first.
      // eslint-disable-next-line @typescript-eslint/no-implied-eval
      expect(() => new Function(`return (${rawScript(source, name)});`)).not.toThrow();
    }
  });
});
