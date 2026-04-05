export interface ModelDescription {
  summary: string;
  strengths: string[];
  limitations: string[];
  bestFor: string;
  speedRating: "fast" | "moderate" | "slow";
}

export interface ApprovedModel {
  id: string;
  name: string;
  huggingFaceRepo: string;
  huggingFaceFile: string;
  sha256: string;
  sizeBytes: number;
  ramWhenLoadedGB: number;
  capabilities: string[];
  memory: boolean;
  platforms: string[];
  minRamGB: number;
  recommendedRamGB: number;
  quantization: string;
  contextWindow: number;
  description: ModelDescription;
}

const APPROVED_MODELS: readonly ApprovedModel[] = [
  {
    id: "gemma-4-e2b-q4",
    name: "Gemma 4 E2B Q4",
    huggingFaceRepo: "bartowski/gemma-4-E2B-it-GGUF",
    huggingFaceFile: "gemma-4-E2B-it-Q4_K_M.gguf",
    sha256: "",
    sizeBytes: 2_500_000_000,
    ramWhenLoadedGB: 3.8,
    capabilities: ["text", "vision", "audio"],
    memory: false,
    platforms: ["macos"],
    minRamGB: 8,
    recommendedRamGB: 16,
    quantization: "Q4_K_M",
    contextWindow: 8192,
    description: {
      summary: "Understands text, images, and speech for local page analysis.",
      strengths: [
        "Describes screenshots and visual page layouts",
        "Summarises articles and extracts key information",
        "Answers spoken questions with native audio input",
      ],
      limitations: [
        "Image and audio prompts are slower than text-only prompts",
        "Long pages may need tighter prompting to stay focused",
      ],
      bestFor: "General local browsing assistance with text, vision, and audio input",
      speedRating: "moderate",
    },
  },
  {
    id: "gemma-4-e2b-q8",
    name: "Gemma 4 E2B Q8",
    huggingFaceRepo: "bartowski/gemma-4-E2B-it-GGUF",
    huggingFaceFile: "gemma-4-E2B-it-Q8_0.gguf",
    sha256: "",
    sizeBytes: 5_000_000_000,
    ramWhenLoadedGB: 8,
    capabilities: ["text", "vision", "audio"],
    memory: false,
    platforms: ["macos"],
    minRamGB: 16,
    recommendedRamGB: 32,
    quantization: "Q8_0",
    contextWindow: 8192,
    description: {
      summary: "Higher-quality Gemma 4 build with the same multimodal capabilities.",
      strengths: [
        "Produces more accurate answers on nuanced questions",
        "Handles complex visual layouts more reliably",
        "Retains the same screenshot and audio support as Q4",
      ],
      limitations: [
        "Needs substantially more RAM than the Q4 build",
        "Runs slower than the Q4 build on the same hardware",
      ],
      bestFor: "Accuracy-focused local analysis when memory headroom is available",
      speedRating: "moderate",
    },
  },
];

export function getApprovedModels(): ApprovedModel[] {
  return APPROVED_MODELS.map((model) => ({
    ...model,
    capabilities: [...model.capabilities],
    platforms: [...model.platforms],
    description: {
      ...model.description,
      strengths: [...model.description.strengths],
      limitations: [...model.description.limitations],
    },
  }));
}

export function findModel(id: string): ApprovedModel | undefined {
  const model = APPROVED_MODELS.find((candidate) => candidate.id === id);
  if (!model) {
    return undefined;
  }

  return {
    ...model,
    capabilities: [...model.capabilities],
    platforms: [...model.platforms],
    description: {
      ...model.description,
      strengths: [...model.description.strengths],
      limitations: [...model.description.limitations],
    },
  };
}
