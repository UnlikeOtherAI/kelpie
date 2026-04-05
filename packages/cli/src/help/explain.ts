import { commandMetadata } from "./command-metadata.js";
import { browserTools, cliTools } from "../mcp/tools.js";

/** Generate a natural language explanation for a command. */
export function explainCommand(command: string): string {
  // Try direct lookup
  const meta = commandMetadata[command];
  if (meta) {
    return formatExplanation(command, meta.explanation, meta.related);
  }

  // Try MCP tool name match
  const mcpName = `kelpie_${command.replace(/-/g, "_")}`;
  const tool = [...browserTools, ...cliTools].find((t) => t.name === mcpName);
  if (tool) {
    const m = commandMetadata[command];
    return formatExplanation(command, m?.explanation ?? tool.description, m?.related);
  }

  return `Unknown command: ${command}\n\nRun 'kelpie --help' to see all available commands.`;
}

function formatExplanation(command: string, explanation: string, related?: string[]): string {
  let output = `${command}\n${"─".repeat(command.length)}\n\n${explanation}`;
  if (related?.length) {
    output += `\n\nRelated: ${related.join(", ")}`;
  }
  return output;
}
