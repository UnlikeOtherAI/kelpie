import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

export interface ModelMeta {
  name: string;
  capabilities: string[];
  [key: string]: unknown;
}

export interface DownloadedModel {
  id: string;
  dir: string;
  path: string;
  meta: ModelMeta;
}

interface RegistryFile {
  models: Record<string, ModelMeta>;
}

const REGISTRY_FILE = "registry.json";
const METADATA_FILE = "metadata.json";
const MODEL_FILE = "model.gguf";
const LOCK_FILE = ".downloading";

function isPidAlive(pid: number): boolean {
  if (!Number.isInteger(pid) || pid <= 0) {
    return false;
  }

  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

export class ModelStore {
  readonly rootDir: string;

  constructor(rootDir = join(homedir(), ".kelpie", "models")) {
    this.rootDir = rootDir;
  }

  listDownloaded(): DownloadedModel[] {
    const registry = this.readRegistry();

    return Object.entries(registry.models).map(([id, meta]) => ({
      id,
      dir: this.modelDirPath(id),
      path: this.modelPath(id),
      meta,
    }));
  }

  isDownloaded(id: string): boolean {
    return id in this.readRegistry().models;
  }

  getModelPath(id: string): string | undefined {
    if (!this.isDownloaded(id)) {
      return undefined;
    }

    return this.modelPath(id);
  }

  getModelDir(id: string): string {
    this.ensureDir(this.rootDir);
    const dir = this.modelDirPath(id);
    this.ensureDir(dir);
    return dir;
  }

  register(id: string, meta: ModelMeta): void {
    const registry = this.readRegistry();
    registry.models[id] = meta;

    const modelDir = this.getModelDir(id);
    writeFileSync(join(modelDir, METADATA_FILE), JSON.stringify(meta, null, 2));
    this.writeRegistry(registry);
  }

  remove(id: string): void {
    const registry = this.readRegistry();
    const { [id]: _removed, ...remaining } = registry.models;
    registry.models = remaining;

    rmSync(this.modelDirPath(id), { recursive: true, force: true });
    this.writeRegistry(registry);
  }

  cleanOrphans(): void {
    if (!existsSync(this.rootDir)) {
      return;
    }

    for (const entry of readdirSync(this.rootDir)) {
      const entryPath = join(this.rootDir, entry);
      if (!statSync(entryPath).isDirectory()) {
        continue;
      }

      const lockPath = join(entryPath, LOCK_FILE);
      const lockAlive = this.isLockAlive(lockPath);
      if (!lockAlive && existsSync(lockPath)) {
        rmSync(lockPath, { force: true });
      }

      for (const fileName of readdirSync(entryPath)) {
        if (fileName.endsWith(".tmp") && !lockAlive) {
          rmSync(join(entryPath, fileName), { force: true });
        }
      }
    }
  }

  private readRegistry(): RegistryFile {
    const registryPath = this.registryPath();
    if (!existsSync(registryPath)) {
      return { models: {} };
    }

    try {
      const parsed = JSON.parse(readFileSync(registryPath, "utf8")) as Partial<RegistryFile>;
      return { models: parsed.models ?? {} };
    } catch {
      return { models: {} };
    }
  }

  private writeRegistry(registry: RegistryFile): void {
    this.ensureDir(this.rootDir);
    writeFileSync(this.registryPath(), JSON.stringify(registry, null, 2));
  }

  private ensureDir(dir: string): void {
    mkdirSync(dir, { recursive: true });
  }

  private registryPath(): string {
    return join(this.rootDir, REGISTRY_FILE);
  }

  private modelDirPath(id: string): string {
    return join(this.rootDir, id);
  }

  private modelPath(id: string): string {
    return join(this.modelDirPath(id), MODEL_FILE);
  }

  private isLockAlive(lockPath: string): boolean {
    if (!existsSync(lockPath)) {
      return false;
    }

    try {
      const data = JSON.parse(readFileSync(lockPath, "utf8")) as { pid?: number };
      return isPidAlive(data.pid ?? 0);
    } catch {
      return false;
    }
  }
}
