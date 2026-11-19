import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";
import { describe, expect, it } from "vitest";

const sources = [
  {
    name: "Apple",
    path: "../../../core/apple/shared/Browser/NetworkDiagnosticEntries.swift",
    pattern: /static let snapshotScript = #"""\r?\n([\s\S]*?)\r?\n {4}"""#/,
  },
  {
    name: "Android",
    path: "../../../core/android/src/main/java/com/kelpie/browser/devtools/NetworkDiagnosticEntries.kt",
    pattern: /const val NETWORK_SNAPSHOT = """\r?\n([\s\S]*?)\r?\n"""/,
  },
];

describe.each(sources)("$name network timing fallback", ({ path, pattern }) => {
  const source = readFileSync(new URL(path, import.meta.url), "utf8");
  const snapshot = source.match(pattern)?.[1] ?? "";

  it("uses module preload metadata when the engine reports an unknown initiator", () => {
    const url = "https://example.test/chunk.js";
    const [entry] = runInNewContext(snapshot, {
      location: { href: "https://example.test/" },
      document: {
        querySelectorAll: () => [{ href: url, relList: { contains: (rel: string) => rel === "modulepreload" } }],
      },
      performance: {
        timeOrigin: 1704067200000,
        getEntriesByType: (type: string) => type === "resource"
          ? [{ name: url, entryType: "resource", initiatorType: "other", startTime: 2, duration: 10 }]
          : [],
      },
    }).entries;
    expect(entry).toMatchObject({ type: "script", initiator: "other", method: null, status: null });
  });
});
