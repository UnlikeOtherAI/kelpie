import { afterEach, describe, expect, it } from "vitest";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve, sep } from "node:path";
import { createProgram } from "../../src/program.js";

let directory: string | undefined;
afterEach(async () => {
  if (!directory) return;
  if (!resolve(directory).startsWith(resolve(tmpdir()) + sep)) throw new Error("Unsafe test cleanup");
  await rm(directory, { recursive: true, force: true });
  directory = undefined;
});
describe("script CLI file admission", () => {
  it.each(["script", "inputs"])("does not echo malformed %s JSON contents", async kind => {
    directory = await mkdtemp(join(tmpdir(), "kelpie-script-parse-"));
    const script = join(directory, "script.json");
    const values = join(directory, "values.json");
    const privateText = "private-fixture-contents";
    await writeFile(script, kind === "script" ? privateText : JSON.stringify({ version: 1, tabId: "tab", actions: [{ action: "wait", ms: 0 }] }));
    await writeFile(values, privateText);
    const program = createProgram("test");
    const args = ["script", "run", script, ...(kind === "inputs" ? ["--inputs", values] : [])];
    await expect(program.parseAsync(args, { from: "user" })).rejects.toThrow("Invalid script or input JSON");
    expect(await readFile(values, "utf8")).toBe(privateText);
  });
});

it("refuses host ENV mappings embedded in an authored script file", async () => {
  directory = await mkdtemp(join(tmpdir(), "kelpie-script-parse-"));
  const script = join(directory, "script.json");
  await writeFile(script, JSON.stringify({ version: 1, tabId: "tab", secretEnv: { password: "HOST_ENV" }, actions: [{ action: "fill", target: { label: "Password" }, text: { secret: "password" } }] }));
  await expect(createProgram("test").parseAsync(["script", "run", script], { from: "user" })).rejects.toThrow("Host bindings belong in explicit CLI options");
});
