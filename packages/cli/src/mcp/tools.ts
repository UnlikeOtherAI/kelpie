import { sharedBrowserTools } from "@unlikeotherai/kelpie-shared";
import { aiAskTool, aiEndpointTools, aiLoadTool } from "./ai-endpoint-tools.js";
export { cliTools } from "@unlikeotherai/kelpie-shared";
export type { BrowserToolDef, CliToolDef } from "@unlikeotherai/kelpie-shared";

export const browserTools = [...sharedBrowserTools, aiLoadTool, aiAskTool, ...aiEndpointTools];
