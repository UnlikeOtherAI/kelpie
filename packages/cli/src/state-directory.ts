import { homedir } from "node:os";
import { join } from "node:path";

export function stateDirectory(): string {
  return process.env.KELPIE_HOME ?? join(homedir(), ".kelpie");
}
