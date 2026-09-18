import { describe, it, expect } from "vitest";
import {
  MAX_PARTITION_LENGTH,
  MAX_TAB_NAME_LENGTH,
  RESERVED_PARTITION_PREFIX,
  isValidPartition,
  partitionErrorMessage,
  validatePartition,
  type PartitionInvalidReason,
} from "../src/partition.js";

/** Reason for a rejection, or `"ok"` when the string is accepted. */
function outcome(value: string): PartitionInvalidReason | "ok" {
  const result = validatePartition(value);
  return result.ok ? "ok" : result.reason;
}

describe("validatePartition - accepted strings", () => {
  it.each([
    "a",
    "1",
    "_1",
    "sam.eng-lead",
    "morgan.product",
    "A-B_C.D",
    "Default1",
    "defaults",
    "ephemeral",
    "ephemeralx-thing",
    "Ephemeral-thing",
    "..a",
  ])("accepts %j", (value) => {
    expect(outcome(value)).toBe("ok");
    expect(isValidPartition(value)).toBe(true);
  });

  it("accepts exactly 128 characters", () => {
    expect(outcome("a".repeat(MAX_PARTITION_LENGTH))).toBe("ok");
  });

  it("accepts a 128-character string whose only alphanumeric is the last character", () => {
    expect(outcome(".".repeat(MAX_PARTITION_LENGTH - 1) + "z")).toBe("ok");
  });
});

describe("validatePartition - charset and length", () => {
  it("rejects the empty string", () => {
    expect(outcome("")).toBe("charset-or-length");
  });

  it("rejects 129 characters", () => {
    expect(outcome("a".repeat(MAX_PARTITION_LENGTH + 1))).toBe("charset-or-length");
  });

  it.each([
    ["space", "sam eng"],
    ["slash", "sam/eng"],
    ["backslash", "sam\\eng"],
    ["colon", "sam:eng"],
    ["at sign", "sam@eng"],
    ["percent", "sam%2e"],
    ["null byte", `sam${String.fromCharCode(0)}eng`],
    ["newline", "sam\neng"],
    ["tab", "sam\tent"],
    ["non-ASCII letter", "café"],
    ["emoji", "sam-\u{1F642}"],
    ["CJK", "サム"],
    ["combining mark", "saḿ"],
    ["full-width digit", "１23"],
  ])("rejects %s", (_label, value) => {
    expect(outcome(value)).toBe("charset-or-length");
  });

  it("rejects a leading or trailing newline even when the rest is valid", () => {
    // The pattern is anchored with ^/$, but JavaScript's `$` also matches
    // before a trailing newline, so both ends are worth asserting.
    expect(outcome("\nsam")).toBe("charset-or-length");
    expect(outcome("sam\n")).toBe("charset-or-length");
  });
});

describe("validatePartition - at least one alphanumeric", () => {
  it.each(["-", "_", "-_.", "._-.", "..."])("rejects %j as no-alnum", (value) => {
    expect(outcome(value)).toBe("no-alnum");
  });

  it("rejects 128 dots as no-alnum", () => {
    expect(outcome(".".repeat(MAX_PARTITION_LENGTH))).toBe("no-alnum");
  });
});

describe("validatePartition - reserved words", () => {
  it.each(["default", "Default", "DEFAULT", "DeFaUlT"])("rejects %j", (value) => {
    expect(outcome(value)).toBe("reserved");
  });

  it("rejects the traversal names", () => {
    // Both are caught by the alphanumeric rule first - the reserved-word list
    // still carries them so the rule survives any future charset change.
    expect(outcome(".")).toBe("no-alnum");
    expect(outcome("..")).toBe("no-alnum");
    expect(isValidPartition(".")).toBe(false);
    expect(isValidPartition("..")).toBe(false);
  });

  it("does not reject strings that merely contain a reserved word", () => {
    expect(outcome("default-sam")).toBe("ok");
    expect(outcome("sam.default")).toBe("ok");
  });
});

describe("validatePartition - reserved prefix", () => {
  it("rejects the exact reserved prefix", () => {
    expect(outcome(`${RESERVED_PARTITION_PREFIX}sam`)).toBe("reserved-prefix");
  });

  it("rejects the bare prefix", () => {
    expect(outcome(RESERVED_PARTITION_PREFIX)).toBe("reserved-prefix");
  });

  it("is case-sensitive, matching the platform mirrors", () => {
    // Android only ever writes the lowercase prefix, and every platform
    // mirror compares case-sensitively - keep them identical.
    expect(outcome("Ephemeral-sam")).toBe("ok");
    expect(outcome("EPHEMERAL-sam")).toBe("ok");
  });

  it("does not reject the prefix in a non-leading position", () => {
    expect(outcome("sam-ephemeral-1")).toBe("ok");
  });
});

describe("validatePartition - rejection ordering", () => {
  it("reports charset before reserved for an over-long reserved word", () => {
    expect(outcome("default".padEnd(MAX_PARTITION_LENGTH + 1, "x"))).toBe("charset-or-length");
  });

  it("reports no-alnum before the reserved-word list is consulted", () => {
    // Ordering is fixed by the shared spec so every platform mirror agrees:
    // charset/length, then alphanumeric, then reserved word, then prefix.
    expect(outcome("..")).toBe("no-alnum");
  });
});

describe("partitionErrorMessage", () => {
  it.each<PartitionInvalidReason>([
    "charset-or-length",
    "no-alnum",
    "reserved",
    "reserved-prefix",
  ])("returns a non-empty message for %s", (reason) => {
    expect(partitionErrorMessage(reason).length).toBeGreaterThan(0);
  });

  it("names the length bound in the charset message", () => {
    expect(partitionErrorMessage("charset-or-length")).toContain("128");
  });
});

describe("partition constants", () => {
  it("pins the documented bounds", () => {
    expect(MAX_PARTITION_LENGTH).toBe(128);
    expect(MAX_TAB_NAME_LENGTH).toBe(200);
    expect(RESERVED_PARTITION_PREFIX).toBe("ephemeral-");
  });
});
