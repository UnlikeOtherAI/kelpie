import { Command } from "commander";
import { beforeEach, expect, it, vi } from "vitest";
import { registerInteraction } from "../../src/commands/interaction.js";
import { deviceCommand } from "../../src/commands/helpers.js";

vi.mock("../../src/commands/helpers.js", () => ({ deviceCommand: vi.fn() }));

function command(): Command {
  const program = new Command().exitOverride().configureOutput({ writeErr: vi.fn() });
  registerInteraction(program);
  return program;
}

beforeEach(() => { vi.clearAllMocks(); });

it("keeps the legacy tap body without marker flags", async () => {
  const program = command();
  await program.parseAsync(["tap", "120", "240"], { from: "user" });
  expect(deviceCommand).toHaveBeenCalledWith(program, "tap", { x: 120, y: 240 });
});

it("forwards a crosshair and an immediate fade", async () => {
  const program = command();
  await program.parseAsync(["tap", "120", "240", "--marker-style", "crosshair-coordinates", "--marker-duration", "0"], { from: "user" });
  expect(deviceCommand).toHaveBeenCalledWith(program, "tap", {
    x: 120, y: 240, marker: { style: "crosshair-coordinates", durationMs: 0 },
  });
});

it.each([["--marker-style", "square"], ["--marker-duration", "1.5"], ["--marker-duration", "-1"]])(
  "rejects invalid %s value %s before calling the device",
  async (flag, value) => {
    await expect(command().parseAsync(["tap", "120", "240", flag, value], { from: "user" })).rejects.toThrow();
    expect(deviceCommand).not.toHaveBeenCalled();
  },
);
