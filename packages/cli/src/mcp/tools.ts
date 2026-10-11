import { BrowserMcpTools, sharedBrowserTools } from "@unlikeotherai/kelpie-shared";
import { aiAskTool, aiEndpointTools, aiLoadTool } from "./ai-endpoint-tools.js";
export { cliTools } from "@unlikeotherai/kelpie-shared";
export type { BrowserToolDef, CliToolDef } from "@unlikeotherai/kelpie-shared";

const order = new Map<string, number>(BrowserMcpTools.map((name, index) => [name, index]));
export const browserTools = [...sharedBrowserTools, aiLoadTool, aiAskTool, ...aiEndpointTools]
  .sort((left, right) => (order.get(left.name) ?? order.size) - (order.get(right.name) ?? order.size));
