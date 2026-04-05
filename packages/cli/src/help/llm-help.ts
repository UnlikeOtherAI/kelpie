import { browserTools, cliTools } from "../mcp/tools.js";
import { commandMetadata } from "./command-metadata.js";
import type { BrowserToolDef, CliToolDef } from "../mcp/tools.js";

interface ParamInfo {
  name: string;
  type: string;
  required: boolean;
  description?: string;
}

interface CommandHelpOutput {
  command: string;
  purpose: string;
  when: string;
  params: ParamInfo[];
  errors?: string[];
  related?: string[];
}

const manualCommandHelp: Record<string, CommandHelpOutput> = {
  browser: {
    command: "browser",
    purpose: "Manage local macOS browser aliases",
    when: "You need to register, launch, inspect, or remove named local Kelpie app instances",
    params: [],
    related: ["browser register", "browser launch", "browser list", "browser inspect", "browser remove"],
  },
  "browser register": {
    command: "browser register",
    purpose: "Register a named local macOS browser alias",
    when: "You need a stable local identifier before launching a browser instance",
    params: [
      { name: "name", type: "string", required: true, description: "Browser alias name" },
      { name: "app", type: "string", required: false, description: "Optional path to Kelpie.app" },
    ],
    related: ["browser launch", "browser inspect", "browser remove"],
  },
  "browser launch": {
    command: "browser launch",
    purpose: "Launch a named local macOS browser instance",
    when: "You want a fresh local Kelpie.app process for a saved alias",
    params: [
      { name: "name", type: "string", required: true, description: "Browser alias name" },
      { name: "port", type: "number", required: false, description: "Optional explicit HTTP port" },
      { name: "wait", type: "boolean", required: false, description: "Wait until the local browser becomes reachable" },
    ],
    errors: ["BROWSER_NOT_REGISTERED", "APP_NOT_INSTALLED", "BROWSER_LAUNCH_FAILED"],
    related: ["browser register", "browser list", "browser inspect"],
  },
  "browser list": {
    command: "browser list",
    purpose: "List local macOS browser aliases",
    when: "You need to see saved aliases and their current runtime state",
    params: [],
    related: ["browser inspect", "browser launch"],
  },
  "browser inspect": {
    command: "browser inspect",
    purpose: "Inspect one local macOS browser alias",
    when: "You need to inspect one saved alias and its live port",
    params: [{ name: "name", type: "string", required: true, description: "Browser alias name" }],
    related: ["browser list", "browser launch", "browser remove"],
  },
  "browser remove": {
    command: "browser remove",
    purpose: "Remove a local macOS browser alias",
    when: "A saved alias is no longer needed",
    params: [{ name: "name", type: "string", required: true, description: "Browser alias name" }],
    related: ["browser list", "browser register"],
  },
};

/** Convert a MCP tool name to CLI kebab-case command name */
function mcpToCommand(name: string): string {
  return name
    .replace(/^kelpie_/, "")
    .replace(/^group_/, "group ")
    .replace(/_/g, "-");
}

function extractParams(schema: Record<string, unknown>): ParamInfo[] {
  return Object.entries(schema).map(([name, zodType]) => {
    const z = zodType as { _def?: { typeName?: string; description?: string; innerType?: unknown }; isOptional?: () => boolean; description?: string };
    const isOptional = z._def?.typeName === "ZodOptional" || z._def?.typeName === "ZodDefault";
    const desc = z._def?.description ?? z.description;
    const innerType = z._def?.innerType as { _def?: { typeName?: string } } | undefined;
    const baseType = isOptional ? innerType?._def?.typeName ?? "string" : z._def?.typeName ?? "string";
    return { name, type: baseType.replace("Zod", "").toLowerCase(), required: !isOptional, description: desc ?? undefined };
  });
}

function toolToHelp(tool: BrowserToolDef | CliToolDef): CommandHelpOutput {
  const cmd = mcpToCommand(tool.name);
  const meta = commandMetadata[cmd];
  return {
    command: cmd,
    purpose: meta?.purpose ?? tool.description,
    when: meta?.when ?? "",
    params: extractParams(tool.schema),
    errors: meta?.errors,
    related: meta?.related,
  };
}

/** Generate help for a specific command or all commands. */
export function generateLlmHelp(commandFilter?: string): string {
  if (commandFilter) {
    const manualMatch = manualCommandHelp[commandFilter];
    if (manualMatch) {
      return JSON.stringify(manualMatch, null, 2);
    }

    const all = [...browserTools, ...cliTools];
    const match = all.find((t) => mcpToCommand(t.name) === commandFilter || t.name === commandFilter);
    if (match) {
      return JSON.stringify(toolToHelp(match), null, 2);
    }
    // Try prefix match for group commands
    const prefix = commandFilter.replace(/-/g, "_");
    const groupMatch = all.filter((t) => t.name.startsWith(`kelpie_${prefix}`));
    if (groupMatch.length > 0) {
      return JSON.stringify(groupMatch.map(toolToHelp), null, 2);
    }
    return JSON.stringify({ error: `Unknown command: ${commandFilter}` });
  }

  // All commands
  const allHelp = [...browserTools, ...cliTools].map(toolToHelp).concat(Object.values(manualCommandHelp));
  return JSON.stringify(allHelp, null, 2);
}
