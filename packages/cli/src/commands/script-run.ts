import { mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import type { Command } from "commander";
import { scriptArtifactSchema, type ScriptArtifact } from "@unlikeotherai/kelpie-shared";
import { createPinnedCommandTransport, type PinnedCommandTransport } from "../client/http-client.js";
import { print } from "../output/formatter.js";
import { scriptHostBody, redactScriptResult, admitScriptTransport } from "../mcp/script-tools.js";
import { commandTimeout, deviceCommand, getGlobals, requireDevice } from "./helpers.js";
import { downloadScriptArtifact } from "./script-artifacts.js";
import type { DiscoveredDevice } from "../types.js";

export interface ScriptRunOptions { inputs?: string; secret?: string[]; output?: string }

async function readObject(path: string): Promise<Record<string, unknown>> {
  const raw = await readFile(path, "utf8");
  let parsed: unknown;
  try { parsed = JSON.parse(raw) as unknown; } catch { throw new Error("Invalid script or input JSON"); }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("Expected a JSON object");
  return parsed as Record<string, unknown>;
}

async function readBoundScript(program: Command, file: string, options: ScriptRunOptions): Promise<Record<string, unknown>> {
  const raw = await readObject(file);
  if (["secretEnv", "values", "device"].some(key => Object.hasOwn(raw, key))) throw new Error("Host bindings belong in explicit CLI options");
  const values = options.inputs ? await readObject(options.inputs) : undefined;
  const secretEnv: Record<string, string> = {};
  for (const mapping of options.secret ?? []) {
    const match = /^([A-Za-z][A-Za-z0-9_.-]{0,127})=([A-Za-z_][A-Za-z0-9_]*)$/.exec(mapping);
    if (!match?.[1] || !match[2]) throw new Error("Use --secret reference=ENVIRONMENT_VARIABLE");
    if (Object.hasOwn(secretEnv, match[1])) throw new Error("Duplicate secret reference");
    secretEnv[match[1]] = match[2];
  }
  const tabId = getGlobals(program).tabId;
  return scriptHostBody({ ...raw, ...(tabId && !raw.tabId ? { tabId } : {}),
    ...(values ? { values } : {}), ...(options.secret ? { secretEnv } : {}) });
}

function manifestsFor(raw: unknown): ScriptArtifact[] {
  if (!Array.isArray(raw) || raw.length > 1002) throw new Error("Invalid run artifact set");
  const manifests = raw.map((item: unknown) => scriptArtifactSchema.parse(item));
  if (manifests.reduce((size, item) => size + item.byteLength, 0) > 268_435_456 ||
      new Set(manifests.map(item => item.id)).size !== manifests.length) throw new Error("Run artifacts exceed bounds or repeat an ID");
  return manifests;
}

async function saveRunArtifacts(
  device: DiscoveredDevice, runId: string, raw: unknown, output: string, timeout: number,
  transport: PinnedCommandTransport, safeResult: unknown,
): Promise<{ id: string; file: string }[]> {
  const manifests = manifestsFor(raw);
  await mkdir(output, { recursive: true });
  const directory = await mkdtemp(join(output, "kelpie-run-"));
  const downloaded: { id: string; file: string }[] = [];
  for (const [index, item] of manifests.entries()) {
    const extension = item.mimeType === "image/gif" ? "gif" : item.mimeType === "video/mp4" ? "mp4" : "png";
    const path = join(directory, String(index + 1).padStart(3, "0") + "." + extension);
    await downloadScriptArtifact(device, runId, item, path, timeout, transport);
    downloaded.push({ id: item.id, file: path });
  }
  await writeFile(join(directory, "manifest.json"), JSON.stringify({ result: safeResult, downloaded }, null, 2), { flag: "wx" });
  return downloaded;
}

export async function runScriptFile(program: Command, file: string, options: ScriptRunOptions): Promise<void> {
  const globals = getGlobals(program);
  const body = await readBoundScript(program, file, options);
  const device = await requireDevice(program);
  if (!device) return;
  const admission = await admitScriptTransport(device, body.version);
  if (!admission.ok) { print(admission.response.data, globals.format); process.exitCode = 1; return; }
  const transport = admission.send;
  const result = await transport("playScript", body, commandTimeout(program, body.version === 1 ? 360_000 : 10_000));
  const safeResult = redactScriptResult(result.data, body);
  let downloaded: { id: string; file: string }[] | undefined;
  if (options.output && result.data && typeof result.data === "object") {
    const data = result.data as Record<string, unknown>;
    if (typeof data.runId === "string" && Array.isArray(data.artifacts)) {
      downloaded = await saveRunArtifacts(device, data.runId, data.artifacts, options.output, commandTimeout(program), transport, safeResult);
    }
  }
  if (result.status === 0 || result.status === 408) {
    print({ result: safeResult, mayHaveCompleted: true, recovery: "Inspect script status --pinned on the same browser/device before starting another run" }, globals.format);
  } else print(downloaded ? { result: safeResult, downloaded } : safeResult, globals.format);
  if (!result.ok || (result.data && typeof result.data === "object" && (result.data as Record<string, unknown>).success === false)) process.exitCode = 1;
}

export async function downloadRunArtifact(program: Command, runId: string, artifactId: string, destination: string): Promise<void> {
  const globals = getGlobals(program);
  const device = await requireDevice(program);
  if (!device) return;
  const transport = await createPinnedCommandTransport(device);
  const response = await transport("getScriptStatus", { runId }, commandTimeout(program));
  if (!response.ok || !response.data || typeof response.data !== "object") throw new Error("Run status unavailable");
  const data = response.data as Record<string, unknown>;
  if (data.runId !== runId) throw new Error("Run status identity mismatch");
  const manifest = manifestsFor(data.artifacts).find(item => item.id === artifactId);
  if (!manifest) throw new Error("Run artifact unavailable");
  await downloadScriptArtifact(device, runId, manifest, destination, commandTimeout(program), transport);
  print({ runId, artifact: manifest, file: destination }, globals.format);
}

/** Run-owned controls must retain the exact socket/grant rather than re-pairing after rejection. */
export async function controlScriptRun(program: Command, method: "abortScript" | "getScriptStatus", runId?: string, pinCurrent = false): Promise<void> {
  if (!runId && !pinCurrent) { await deviceCommand(program, method); return; }
  const globals = getGlobals(program);
  const device = await requireDevice(program);
  if (!device) return;
  const result = await (await createPinnedCommandTransport(device))(method, runId ? { runId } : {}, commandTimeout(program));
  const uncertain = method === "abortScript" && (result.status === 0 || result.status === 408);
  print(uncertain ? { result: result.data, mayHaveCompleted: true } : result.data, globals.format);
  if (!result.ok || (result.data && typeof result.data === "object" && (result.data as Record<string, unknown>).success === false)) process.exitCode = 1;
}