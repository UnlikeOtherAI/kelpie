import type { Command } from "commander";
import { join } from "node:path";
import { deviceCommand, getGlobals } from "./helpers.js";
import { getApprovedModels, findModel } from "../ai/models.js";
import { ModelStore } from "../ai/store.js";
import { buildDownloadUrl, downloadModel } from "../ai/download.js";
import { detectOllama, listOllamaModels } from "../ai/ollama.js";
import { print } from "../output/formatter.js";

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
    .action(async (modelId: string) => {
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
    .description("Load a model on a device")
    .action(async (model: string) => {
      await deviceCommand(program, "ai-load", { model });
    });

  ai.command("unload")
    .description("Unload model from a device")
    .action(async () => { await deviceCommand(program, "ai-unload"); });

  ai.command("ask <prompt>")
    .description("Run inference on the device's loaded model")
    .option("-c, --context <mode>", "Context mode: page_text, screenshot, dom, accessibility")
    .option("--max-tokens <n>", "Max tokens", "512")
    .option("--temperature <t>", "Temperature", "0.7")
    .action(async (prompt: string, opts: { context?: string; maxTokens?: string; temperature?: string }) => {
      const body: Record<string, unknown> = { prompt };
      if (opts.context) body.context = opts.context;
      if (opts.maxTokens) body.maxTokens = parseInt(opts.maxTokens, 10);
      if (opts.temperature) body.temperature = parseFloat(opts.temperature);
      await deviceCommand(program, "ai-infer", body);
    });
}
