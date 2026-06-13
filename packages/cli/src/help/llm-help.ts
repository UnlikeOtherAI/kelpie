import { browserTools, cliTools } from "../mcp/tools.js";
import { commandMetadata, type CommandHelp, type HelpField } from "./command-metadata.js";
import type { BrowserToolDef, CliToolDef } from "../mcp/tools.js";
import { errorDescriptions } from "./error-descriptions.js";

interface ShapeInfo {
  type: string;
  description?: string;
  values?: unknown[];
  default?: unknown;
  fields?: ParamInfo[];
  items?: ShapeInfo;
}

interface ParamInfo extends ShapeInfo {
  name: string;
  required: boolean;
}

interface ErrorInfo {
  code: string;
  description?: string;
}

interface CommandHelpOutput {
  command: string;
  purpose: string;
  when: string;
  explanation?: string;
  platforms?: string[];
  params: ParamInfo[];
  errors?: ErrorInfo[];
  related?: string[];
  response: HelpField[];
}

const defaultPlatforms = ["ios", "android", "macos", "linux", "windows"] as const;

const defaultResponse: HelpField[] = [
  { name: "success", type: "boolean", description: "true when the command succeeds" },
];

const manualCommandHelp: Record<string, CommandHelpOutput> = {
  browser: {
    command: "browser",
    purpose: "Manage local macOS browser aliases",
    when: "You need to register, launch, inspect, or remove named local Kelpie app instances",
    platforms: ["macos"],
    params: [],
    related: ["browser register", "browser launch", "browser list", "browser inspect", "browser remove"],
    response: defaultResponse,
  },
  "browser register": {
    command: "browser register",
    purpose: "Register a named local macOS browser alias",
    when: "You need a stable local identifier before launching a browser instance",
    platforms: ["macos"],
    params: [
      { name: "name", type: "string", required: true, description: "Browser alias name" },
      { name: "app", type: "string", required: false, description: "Optional path to Kelpie.app" },
    ],
    related: ["browser launch", "browser inspect", "browser remove"],
    response: defaultResponse,
  },
  "browser launch": {
    command: "browser launch",
    purpose: "Launch a named local macOS browser instance",
    when: "You want a fresh local Kelpie.app process for a saved alias",
    platforms: ["macos"],
    params: [
      { name: "name", type: "string", required: true, description: "Browser alias name" },
      { name: "port", type: "number", required: false, description: "Optional explicit HTTP port" },
      { name: "wait", type: "boolean", required: false, description: "Wait until the local browser becomes reachable" },
    ],
    errors: describeErrors(["BROWSER_NOT_REGISTERED", "APP_NOT_INSTALLED", "BROWSER_LAUNCH_FAILED"]),
    related: ["browser register", "browser list", "browser inspect"],
    response: defaultResponse,
  },
  "browser list": {
    command: "browser list",
    purpose: "List local macOS browser aliases",
    when: "You need to see saved aliases and their current runtime state",
    platforms: ["macos"],
    params: [],
    related: ["browser inspect", "browser launch"],
    response: defaultResponse,
  },
  "browser inspect": {
    command: "browser inspect",
    purpose: "Inspect one local macOS browser alias",
    when: "You need to inspect one saved alias and its live port",
    platforms: ["macos"],
    params: [{ name: "name", type: "string", required: true, description: "Browser alias name" }],
    related: ["browser list", "browser launch", "browser remove"],
    response: defaultResponse,
  },
  "browser remove": {
    command: "browser remove",
    purpose: "Remove a local macOS browser alias",
    when: "A saved alias is no longer needed",
    platforms: ["macos"],
    params: [{ name: "name", type: "string", required: true, description: "Browser alias name" }],
    related: ["browser list", "browser register"],
    response: defaultResponse,
  },
};

const reportingGuidance: CommandHelpOutput = {
  command: "reporting",
  purpose: "Report automation failures and missing capabilities",
  when: "A Kelpie command fails unexpectedly, platform behavior is inconsistent, or a missing capability blocks the task",
  explanation:
    "When Kelpie fails, include the command, parameters, device/platform, error, diagnostics, and expected behavior in a GitHub issue after checking for duplicates: https://github.com/UnlikeOtherAI/kelpie/issues",
  params: [],
  related: ["report-issue", "feedback-summary", "click", "tap", "get-capabilities"],
  response: defaultResponse,
};

const authenticationGuidance: CommandHelpOutput = {
  command: "authentication",
  purpose: "Start automation from an authenticated browser session",
  when: "A target app is behind a login and you need the browser in a signed-in state before navigating",
  explanation:
    "Kelpie owns the browser's auth state through its native cookie store, so you do not need an external proxy. " +
    "To authenticate from a known session cookie (including an httpOnly one), use `kelpie cookies set <name> <value> --domain <host> --path / --http-only --secure` " +
    "(MCP: kelpie_set_cookie). httpOnly cookies ARE supported on iOS, Android, and macOS — they are written to the platform cookie store (WKHTTPCookieStore / CookieManager), not via JavaScript. " +
    "Do NOT try to set a session cookie with `eval`/`document.cookie`: JavaScript cannot create httpOnly cookies, and reading `document.cookie` returns an empty string for them, so it looks like the cookie is missing even when it is set. " +
    "Use `kelpie cookies` (kelpie_get_cookies) to read cookies including httpOnly ones, and `kelpie cookies delete --all` to reset auth state. " +
    "For non-httpOnly token schemes, `kelpie storage set <key> <value>` (kelpie_set_storage) writes localStorage/sessionStorage. " +
    "Alternatively, complete an interactive login in the browser once (e.g. `kelpie safari-auth <url>` on macOS/iOS).",
  params: [],
  related: ["set-cookie", "get-cookies", "delete-cookies", "set-storage", "safari-auth"],
  response: defaultResponse,
};

const endpointToCliCommandAliases: Record<string, string> = {
  "get-current-url": "url",
  "get-dom": "dom",
  "query-selector": "query",
  "get-element-text": "text",
  "get-accessibility-tree": "a11y",
  "screenshot-annotated": "annotate",
  "click-annotation": "click-index",
  "fill-annotation": "fill-index",
  "get-visible-elements": "visible",
  "get-page-text": "page-text",
  "get-form-state": "form-state",
  "get-console-messages": "console",
  "get-js-errors": "errors",
  "get-network-log": "network",
  "get-resource-timeline": "timeline",
  "get-websockets": "websockets",
  "get-websocket-messages": "ws-messages",
  "wait-for-element": "wait",
  "wait-for-navigation": "wait-nav",
  "get-device-info": "info",
  "get-viewport": "viewport",
  "get-shadow-roots": "shadow-roots",
  "query-shadow-dom": "shadow-query",
  "set-home": "home set",
  "get-home": "home get",
  "get-debug-overlay": "debug-overlay get",
  "set-debug-overlay": "debug-overlay set",
  "get-dialog": "dialog check",
  "handle-dialog": "dialog accept",
  "set-dialog-auto-handler": "dialog auto",
  "get-tabs": "tabs",
  "new-tab": "tab new",
  "switch-tab": "tab switch",
  "close-tab": "tab close",
  "get-iframes": "iframes",
  "switch-to-iframe": "iframe enter",
  "switch-to-main": "iframe exit",
  "get-iframe-context": "iframe context",
  "get-cookies": "cookies",
  "set-cookie": "cookies set",
  "delete-cookies": "cookies delete",
  "get-storage": "storage",
  "set-storage": "storage set",
  "clear-storage": "storage clear",
  "get-clipboard": "clipboard",
  "set-clipboard": "clipboard set",
  "set-geolocation": "geo set",
  "clear-geolocation": "geo clear",
  "show-keyboard": "keyboard show",
  "hide-keyboard": "keyboard hide",
  "get-keyboard-state": "keyboard state",
  "resize-viewport": "keyboard resize",
  "reset-viewport": "keyboard resize-reset",
  "is-element-obscured": "keyboard obscured",
  "set-orientation": "orientation set",
  "get-orientation": "orientation get",
  "set-fullscreen": "fullscreen set",
  "get-fullscreen": "fullscreen get",
  "set-renderer": "renderer set",
  "get-renderer": "renderer get",
  "get-viewport-presets": "viewport-preset list",
  "set-viewport-preset": "viewport-preset set",
  "show-commentary": "commentary show",
  "hide-commentary": "commentary hide",
  highlight: "highlight show",
  "hide-highlight": "highlight hide",
  "play-script": "script run",
  "abort-script": "script abort",
  "get-script-status": "script status",
};

const cliToEndpointCommandAliases: Record<string, string> = {
  ...Object.fromEntries(
    Object.entries(endpointToCliCommandAliases).map(([endpoint, cli]) => [cli, endpoint]),
  ),
  "dialog dismiss": "handle-dialog",
};

interface ZodDef {
  typeName?: string;
  type?: unknown;
  description?: string;
  innerType?: unknown;
  values?: unknown[];
  entries?: Record<string, unknown>;
  valueType?: unknown;
  element?: unknown;
  shape?: (() => Record<string, unknown>) | Record<string, unknown>;
  options?: unknown[];
  defaultValue?: unknown;
}

interface ZodNode {
  _def?: ZodDef;
  description?: string;
}

function asZodNode(value: unknown): ZodNode {
  if (typeof value === "object" && value !== null) {
    return value as ZodNode;
  }
  return {};
}

function isZodDefaultFactory(value: unknown): value is () => unknown {
  return typeof value === "function";
}

function resolveZodDefault(rawDefault: ZodDef["defaultValue"]): unknown {
  if (isZodDefaultFactory(rawDefault)) {
    return rawDefault();
  }
  return rawDefault;
}

function getZodType(definition?: ZodDef): string {
  const rawType =
    typeof definition?.typeName === "string"
      ? definition.typeName
      : typeof definition?.type === "string"
        ? definition.type
        : "unknown";

  if (rawType.startsWith("Zod")) {
    return rawType.slice(3).toLowerCase();
  }

  return rawType.toLowerCase();
}

function getEnumValues(definition?: ZodDef): unknown[] | undefined {
  if (definition?.values) {
    return definition.values;
  }
  if (definition?.entries) {
    return Object.values(definition.entries);
  }
  return undefined;
}

function mcpToCommand(name: string): string {
  return name
    .replace(/^kelpie_/, "")
    .replace(/^group_/, "group ")
    .replace(/_/g, "-");
}

function describeParam(
  name: string,
  schema: unknown,
  defaultOverrides?: Record<string, unknown>,
): ParamInfo {
  const described = describeSchema(schema);
  return {
    name,
    required: described.required,
    type: described.type,
    description: described.description,
    values: described.values,
    default: described.default ?? defaultOverrides?.[name],
    fields: described.fields,
    items: described.items,
  };
}

function describeSchema(schema: unknown): ParamInfo {
  const zod = asZodNode(schema);
  const unwrapped = unwrapSchema(zod);
  const definition = unwrapped.schema._def;
  const typeName = getZodType(definition);
  const description = unwrapped.description;
  switch (typeName) {
    case "string":
      return { name: "", required: unwrapped.required, type: "string", description, default: unwrapped.defaultValue };
    case "number":
      return { name: "", required: unwrapped.required, type: "number", description, default: unwrapped.defaultValue };
    case "boolean":
      return { name: "", required: unwrapped.required, type: "boolean", description, default: unwrapped.defaultValue };
    case "enum":
      return {
        name: "",
        required: unwrapped.required,
        type: "enum",
        description,
        values: getEnumValues(definition),
        default: unwrapped.defaultValue,
      };
    case "array":
      return {
        name: "",
        required: unwrapped.required,
        type: "array",
        description,
        default: unwrapped.defaultValue,
        items: stripName(describeSchema(definition?.element ?? definition?.type)),
      };
    case "object": {
      const rawShape = definition?.shape;
      const shape = typeof rawShape === "function" ? rawShape() : (rawShape ?? {});
      return {
        name: "",
        required: unwrapped.required,
        type: "object",
        description,
        default: unwrapped.defaultValue,
        fields: Object.entries(shape).map(([fieldName, fieldSchema]) => describeParam(fieldName, fieldSchema)),
      };
    }
    case "record":
      return {
        name: "",
        required: unwrapped.required,
        type: "record",
        description,
        default: unwrapped.defaultValue,
        items: stripName(describeSchema(definition?.valueType)),
      };
    case "union":
      return {
        name: "",
        required: unwrapped.required,
        type: "union",
        description,
        values: (definition?.options ?? []).map((option) => describeSchema(option).type),
      };
    case "any":
      return { name: "", required: unwrapped.required, type: "any", description };
    case "unknown":
      return { name: "", required: unwrapped.required, type: "unknown", description };
    default:
      return {
        name: "",
        required: unwrapped.required,
        type: typeName,
        description,
        default: unwrapped.defaultValue,
      };
  }
}

function stripName(shape: ParamInfo): ShapeInfo {
  return {
    type: shape.type,
    description: shape.description,
    values: shape.values,
    default: shape.default,
    fields: shape.fields,
    items: shape.items,
  };
}

function unwrapSchema(schema: ZodNode): {
  schema: ZodNode;
  required: boolean;
  description?: string;
  defaultValue?: unknown;
} {
  let current = schema;
  let required = true;
  let description = current._def?.description ?? current.description;
  let defaultValue: unknown;

  while (current._def) {
    const typeName = getZodType(current._def);
    if (typeName === "optional" || typeName === "nullable") {
      required = false;
      current = asZodNode(current._def.innerType);
      description = description ?? current._def?.description ?? current.description;
      continue;
    }
    if (typeName === "default") {
      required = false;
      const rawDefault = current._def.defaultValue;
      defaultValue = resolveZodDefault(rawDefault);
      current = asZodNode(current._def.innerType);
      description = description ?? current._def?.description ?? current.description;
      continue;
    }
    break;
  }

  return { schema: current, required, description, defaultValue };
}

function extractParams(
  schema: Record<string, unknown>,
  meta?: CommandHelp,
): ParamInfo[] {
  return Object.entries(schema).map(([name, zodType]) => describeParam(name, zodType, meta?.paramDefaults));
}

function describeErrors(codes?: string[]): ErrorInfo[] | undefined {
  if (!codes || codes.length === 0) {
    return undefined;
  }
  return codes.map((code) => ({ code, description: errorDescriptions[code] }));
}

function toolToHelp(tool: BrowserToolDef | CliToolDef, displayCommand?: string): CommandHelpOutput {
  const command = mcpToCommand(tool.name);
  const meta =
    commandMetadata[command] ??
    commandMetadata[endpointToCliCommandAliases[command] ?? ""];

  return {
    command: displayCommand ?? command,
    purpose: meta?.purpose ?? tool.description,
    when: meta?.when ?? "",
    explanation: meta?.explanation,
    platforms: [...(meta?.platforms ?? tool.platforms ?? defaultPlatforms)],
    params: extractParams(tool.schema, meta),
    errors: describeErrors(meta?.errors),
    related: meta?.related,
    response: meta?.response ?? defaultResponse,
  };
}

export function generateLlmHelp(commandFilter?: string): string {
  if (commandFilter) {
    const manualMatch = manualCommandHelp[commandFilter];
    if (manualMatch) {
      return JSON.stringify(manualMatch, null, 2);
    }

    const allTools = [...browserTools, ...cliTools];
    const match = allTools.find((tool) => {
      const command = mcpToCommand(tool.name);
      return (
        command === commandFilter ||
        tool.name === commandFilter ||
        endpointToCliCommandAliases[command] === commandFilter ||
        cliToEndpointCommandAliases[commandFilter] === command
      );
    });
    if (match) {
      const command = mcpToCommand(match.name);
      const displayCommand = commandFilter === match.name ? command : commandFilter;
      return JSON.stringify(toolToHelp(match, displayCommand), null, 2);
    }

    const prefix = commandFilter.replace(/-/g, "_");
    const groupMatch = allTools.filter((tool) => tool.name.startsWith(`kelpie_${prefix}`));
    if (groupMatch.length > 0) {
      return JSON.stringify(groupMatch.map((tool) => toolToHelp(tool)), null, 2);
    }

    return JSON.stringify({ error: `Unknown command: ${commandFilter}` });
  }

  const allHelp = [authenticationGuidance, reportingGuidance]
    .concat([...browserTools, ...cliTools].map((tool) => toolToHelp(tool)))
    .concat(Object.values(manualCommandHelp));
  return JSON.stringify(allHelp, null, 2);
}
