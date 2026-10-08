import type { Command } from "commander";
import { join } from "node:path";
import { deviceCommand, getGlobals } from "./helpers.js";
import { getApprovedModels, findModel } from "../ai/models.js";
import { ModelStore } from "../ai/store.js";
import { buildDownloadUrl, downloadModel } from "../ai/download.js";
import { detectOllama, listOllamaModels } from "../ai/ollama.js";
import { print } from "../output/formatter.js";
import { registerAIEndpoint } from "./ai-endpoint.js";
import { EndpointInputError, parseMaxSteps } from "./ai-endpoint-input.js";

/**
 * Agent runs chain several model calls (each up to the device's 900 s cap),
 * so the global 10 s default would abandon nearly every run. A typed
 * `--timeout` still wins; `kelpie ai cancel` stops a run the CLI gave up on.
 */
const ASK_TIMEOUT_MS = 1_800_000;

interface AskOptions {
  context?: string;
  maxTokens?: string;
  temperature?: string;
  agent?: boolean;
  allowActions?: boolean;
  maxSteps?: string;
}

/** `ai-infer` body for `kelpie ai ask`; agent fields are sent only when typed. */
export function askBody(prompt: string, opts: AskOptions): Record<string, unknown> {
  const body: Record<string, unknown> = { prompt };
  if (opts.context) body.context = opts.context;
  if (opts.maxTokens) body.maxTokens = parseInt(opts.maxTokens, 10);
  if (opts.temperature) body.temperature = parseFloat(opts.temperature);
  if (opts.agent !== undefined) body.agent = opts.agent;
  if (opts.allowActions) {
    if (opts.agent === false) throw new EndpointInputError("INVALID_PARAMS", "--allow-actions needs the agent; drop --no-agent.");
    body.allowActions = true;
  }
  if (opts.maxSteps !== undefined) body.maxSteps = parseMaxSteps(opts.maxSteps);
  return body;
}

export function registerAI(program: Command): void {
  const ai = program.command("ai").description("Local AI model management and inference");

  ai.command("list")
    .description("List approved models, download status, and Ollama models if available")
    .action(async () => {
      const globals = getGlobals(program);
      const store = new ModelStore();
      const approved = getApprovedModels();
      const downloaded = store.listDownloaded();
      const rows = approved.map((m) => ({
        id: m.id,
        name: m.name,
        quantization: m.quantization,
        sizeGB: +(m.sizeBytes / 1_073_741_824).toFixed(1),
        downloaded: downloaded.some((d) => d.id === m.id),
      }));
      const result: Record<string, unknown> = { success: true, models: rows };

      const ollama = await detectOllama();
      if (ollama) {
        const ollamaModels = await listOllamaModels();
        result.ollama = { endpoint: "http://localhost:11434", models: ollamaModels };
      }

      print(result, globals.format);
    });

  ai.command("pull <model>")
    .description("Download a model from HuggingFace")
    .action(async (modelId: string) => {
      const globals = getGlobals(program);
      const model = findModel(modelId);
      if (!model) {
        print({ success: false, error: { code: "MODEL_NOT_FOUND", message: `Unknown model "${modelId}". Run 'kelpie ai list' to see available models.` } }, globals.format);
        process.exitCode = 1;
        return;
      }
      const store = new ModelStore();
      if (store.isDownloaded(modelId)) {
        print({ success: true, message: `Model ${modelId} is already downloaded`, path: store.getModelPath(modelId) }, globals.format);
        return;
      }
      try {
        const sizeGB = (model.sizeBytes / 1_073_741_824).toFixed(1);
        console.error(`Downloading ${model.name} (${sizeGB} GB)...`);
        const url = buildDownloadUrl(model.huggingFaceRepo, model.huggingFaceFile);
        const destPath = join(store.getModelDir(modelId), "model.gguf");
        await downloadModel(url, destPath, model.sha256);
        store.register(modelId, { name: model.name, capabilities: [...model.capabilities] });
        print({ success: true, model: modelId, path: destPath }, globals.format);
      } catch (err) {
        print({ success: false, error: { code: "DOWNLOAD_FAILED", message: (err as Error).message } }, globals.format);
        process.exitCode = 1;
      }
    });

  ai.command("rm <model>")
    .description("Delete a downloaded model")
    .action((modelId: string) => {
      const globals = getGlobals(program);
      const store = new ModelStore();
      if (!store.isDownloaded(modelId)) {
        print({ success: false, error: { code: "MODEL_NOT_FOUND", message: `Model "${modelId}" is not downloaded` } }, globals.format);
        process.exitCode = 1;
        return;
      }
      store.remove(modelId);
      print({ success: true, message: `Model ${modelId} removed` }, globals.format);
    });

  ai.command("status")
    .description("Check inference status on a device")
    .action(async () => { await deviceCommand(program, "ai-status"); });

  ai.command("load <model>")
    .description("Load a native, platform or ollama: model on a device (OpenAI-compatible endpoints: ai endpoint use)")
    .action(async (model: string) => {
      await deviceCommand(program, "ai-load", { model });
    });

  ai.command("unload")
    .description("Unload model from a device")
    .action(async () => { await deviceCommand(program, "ai-unload"); });

  ai.command("ask <prompt>")
    .description("Run inference on the device's active backend; with an OpenAI-compatible endpoint and no context this runs Kelpie's browser agent")
    .option("-c, --context <mode>", "Context mode: page_text, screenshot, dom, accessibility")
    .option("--max-tokens <n>", "Max tokens", "512")
    .option("--temperature <t>", "Temperature", "0.7")
    .option("--agent", "Run the browser-agent tool loop (default for OpenAI-compatible endpoints when no context is given)")
    .option("--no-agent", "Plain inference only, no tool loop")
    .option("--allow-actions", "Let the agent click, fill, select and check in the pinned tab (read-only otherwise)")
    .option("--max-steps <n>", "Maximum browser tool steps, 1-40 (device default 20); when it runs out the model gives a final report")
    .action(async (prompt: string, opts: AskOptions) => {
      let body: Record<string, unknown>;
      try {
        body = askBody(prompt, opts);
      } catch (error) {
        if (!(error instanceof EndpointInputError)) throw error;
        print({ success: false, error: { code: error.code, message: error.message } }, getGlobals(program).format);
        process.exitCode = 1;
        return;
      }
      await deviceCommand(program, "ai-infer", body, { defaultTimeoutMs: ASK_TIMEOUT_MS });
    });

  ai.command("cancel")
    .description("Cancel in-flight AI requests and agent runs on a device")
    .action(async () => { await deviceCommand(program, "ai-cancel"); });

  registerAIEndpoint(program, ai);

  ai.command("catalog")
    .description("List the approved on-device model catalog from a device (requires a HuggingFace token on the device)")
    .action(async () => { await deviceCommand(program, "ai-catalog"); });

  ai.command("fitness <model>")
    .description("Check whether a catalog model fits a device's RAM and disk")
    .option("--ram <gb>", "Total device RAM in GB to score against")
    .option("--disk <gb>", "Free disk space in GB to score against")
    .action(async (model: string, opts: { ram?: string; disk?: string }) => {
      const body: Record<string, unknown> = { model };
      if (opts.ram) body.ramGB = parseFloat(opts.ram);
      if (opts.disk) body.diskGB = parseFloat(opts.disk);
      await deviceCommand(program, "ai-fitness", body);
    });
}
