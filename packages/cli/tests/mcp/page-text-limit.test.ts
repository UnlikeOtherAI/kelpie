import { describe, expect, it } from "vitest";
import { DEFAULT_PAGE_TEXT_MAX_CHARS, limitPageText } from "../../src/mcp/page-text-limit.js";
import { browserTools } from "../../src/mcp/tools.js";

describe("limitPageText", () => {
  it("cuts an 80 000-character article to the 20 000-character default and says so", () => {
    const content = "a".repeat(80_000);
    const result = limitPageText({ success: true, title: "Article", content, wordCount: 1, excerpt: "a" }) as Record<string, unknown>;

    expect(DEFAULT_PAGE_TEXT_MAX_CHARS).toBe(20_000);
    expect((result.content as string).length).toBe(20_000);
    expect(result).toMatchObject({
      success: true,
      title: "Article",
      wordCount: 1,
      excerpt: "a",
      truncated: true,
      totalChars: 80_000,
      note: "Page text truncated to 20000 of 80000 characters. Pass a larger maxChars, or a selector for the part you need.",
    });
  });

  it("cuts the desktop engine's text field and keeps its own length", () => {
    const result = limitPageText({ success: true, mode: "readable", text: "b".repeat(50), length: 50 }, 20) as Record<string, unknown>;
    expect(result).toMatchObject({ text: "b".repeat(20), length: 50, truncated: true, totalChars: 50 });
  });

  it("marks text under the ceiling as not truncated and leaves it whole", () => {
    const result = limitPageText({ success: true, content: "short" }, 5);
    expect(result).toEqual({ success: true, content: "short", truncated: false });
  });

  it("never leaves half a surrogate pair at the cut", () => {
    const text = `${"x".repeat(9)}\u{1F600}tail`;
    const result = limitPageText({ success: true, content: text }, 10) as Record<string, unknown>;
    expect(result.content).toBe("x".repeat(9));
    expect(result.totalChars).toBe(text.length);
    expect(result.note).toContain("truncated to 9 of 15 characters");
  });

  it("keeps a whole surrogate pair that fits", () => {
    const text = `${"x".repeat(8)}\u{1F600}tail`;
    const result = limitPageText({ success: true, content: text }, 10) as Record<string, unknown>;
    expect(result.content).toBe(`${"x".repeat(8)}\u{1F600}`);
  });

  it("passes failures and unknown shapes through unchanged", () => {
    const failure = { success: false, error: { code: "TIMEOUT", message: "late" } };
    expect(limitPageText(failure, 1)).toBe(failure);
    const odd = { success: true, words: 3 };
    expect(limitPageText(odd, 1)).toBe(odd);
  });

  it("never forwards maxChars to the device", () => {
    const tool = browserTools.find((candidate) => candidate.name === "kelpie_get_page_text")!;
    expect(tool.bodyFromArgs({ device: "d", mode: "markdown", selector: "main", maxChars: 100 })).toEqual({ mode: "markdown", selector: "main" });
    expect(tool.schema.maxChars!.safeParse(0).success).toBe(false);
    expect(tool.schema.maxChars!.safeParse(1.5).success).toBe(false);
    expect(tool.schema.maxChars!.safeParse(500).success).toBe(true);
  });
});
