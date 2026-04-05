export const OLLAMA_PREFIX = "ollama:";
export const DEFAULT_OLLAMA_ENDPOINT = "http://localhost:11434";

export interface OllamaModel {
  name: string;
  size: number;
  digest: string;
  modifiedAt: string;
}

export interface OllamaGenerateOptions {
  num_predict?: number;
  temperature?: number;
}

export interface OllamaGenerateRequest {
  model: string;
  prompt: string;
  stream: false;
  images?: string[];
  options?: OllamaGenerateOptions;
}

export interface OllamaGenerateResponse {
  response: string;
  totalDuration: number;
  evalCount: number;
}

interface OllamaTagsResponse {
  models?: {
    name: string;
    size: number;
    digest: string;
    modified_at: string;
  }[];
}

interface RawOllamaGenerateResponse {
  response: string;
  total_duration: number;
  eval_count: number;
}

export function isOllamaModelId(id: string): boolean {
  return id.startsWith(OLLAMA_PREFIX);
}

export function parseOllamaModelId(id: string): string {
  if (!isOllamaModelId(id)) {
    throw new Error("INVALID_OLLAMA_MODEL_ID");
  }

  return id.slice(OLLAMA_PREFIX.length);
}

export async function detectOllama(endpoint = DEFAULT_OLLAMA_ENDPOINT): Promise<boolean> {
  try {
    const response = await fetch(`${endpoint}/api/tags`, {
      signal: AbortSignal.timeout(2000),
    });
    return response.ok;
  } catch {
    return false;
  }
}

export async function listOllamaModels(endpoint = DEFAULT_OLLAMA_ENDPOINT): Promise<OllamaModel[]> {
  try {
    const response = await fetch(`${endpoint}/api/tags`, {
      signal: AbortSignal.timeout(5000),
    });
    if (!response.ok) {
      return [];
    }

    const data = (await response.json()) as OllamaTagsResponse;
    return (data.models ?? []).map((model) => ({
      name: model.name,
      size: model.size,
      digest: model.digest,
      modifiedAt: model.modified_at,
    }));
  } catch {
    return [];
  }
}

export function buildOllamaGenerateRequest(
  model: string,
  prompt: string,
  opts: { maxTokens?: number; temperature?: number; image?: string } = {},
): OllamaGenerateRequest {
  const request: OllamaGenerateRequest = {
    model,
    prompt,
    stream: false,
  };

  if (opts.image) {
    request.images = [opts.image];
  }

  const options: OllamaGenerateOptions = {};
  if (opts.maxTokens !== undefined) {
    options.num_predict = opts.maxTokens;
  }
  if (opts.temperature !== undefined) {
    options.temperature = opts.temperature;
  }
  if (Object.keys(options).length > 0) {
    request.options = options;
  }

  return request;
}

export async function ollamaGenerate(
  endpoint: string,
  request: OllamaGenerateRequest,
): Promise<OllamaGenerateResponse> {
  const response = await fetch(`${endpoint}/api/generate`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(request),
  });

  if (!response.ok) {
    throw new Error(`OLLAMA_ERROR: ${String(response.status)} ${response.statusText}`);
  }

  const data = (await response.json()) as RawOllamaGenerateResponse;
  return {
    response: data.response,
    totalDuration: data.total_duration,
    evalCount: data.eval_count,
  };
}
