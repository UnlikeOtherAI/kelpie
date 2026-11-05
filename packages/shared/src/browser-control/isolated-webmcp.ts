import type { CDPSession, Page } from "playwright-core";
import { BrowserControlError } from "./protocol.js";
import { webMcpPageExpression } from "./webmcp-reader.js";
import type { WebMcpPageInput } from "./webmcp-reader.js";
import type { WebMcpIdentity } from "./webmcp-schema.js";

export interface IsolatedWebMcpPage {
  identity(sessionId: string): Promise<WebMcpIdentity>;
  evaluate(input: WebMcpPageInput): Promise<unknown>;
  dispose(): Promise<void>;
}

/** Private main-frame world reached only through an already owned Page. */
export function createIsolatedWebMcpPage(page: Page): IsolatedWebMcpPage {
  const worldName = "kelpie.webmcp." + crypto.randomUUID();
  const contexts = new Map<number, string>();
  let sessionPromise: Promise<CDPSession> | undefined;
  let enabled = false;
  let disposed = false;
  const session = async (): Promise<CDPSession> => {
    if (disposed || page.isClosed()) throw new BrowserControlError("TAB_NOT_FOUND", "The owned site tool renderer is closed.");
    sessionPromise ??= page.context().newCDPSession(page).then(value => {
        value.on("Runtime.executionContextCreated", (event: { context: { id: number; uniqueId?: string } }) => {
          contexts.set(event.context.id, event.context.uniqueId ?? crypto.randomUUID());
        });
        value.on("Runtime.executionContextDestroyed", (event: { executionContextId: number }) => { contexts.delete(event.executionContextId); });
        value.on("Runtime.executionContextsCleared", () => { contexts.clear(); });
        return value;
      }).catch((error: unknown) => { sessionPromise = undefined; throw error; });
    const value = await sessionPromise;
    if (!enabled) { await value.send("Runtime.enable"); enabled = true; }
    return value;
  };
  const world = async (): Promise<{ session: CDPSession; contextId: number; origin: string; generation: string }> => {
    const connection = await session();
    const tree = await connection.send("Page.getFrameTree");
    const frame = tree.frameTree.frame;
    const created = await connection.send("Page.createIsolatedWorld", { frameId: frame.id, worldName, grantUniveralAccess: false });
    const id = created.executionContextId;
    if (!Number.isInteger(id) || id <= 0) throw new BrowserControlError("UNSUPPORTED", "The browser did not provide a private site tool world.");
    let generation = contexts.get(id);
    if (!generation) { generation = crypto.randomUUID(); contexts.set(id, generation); }
    if (disposed || page.isClosed()) throw new BrowserControlError("TAB_NOT_FOUND", "The owned site tool renderer closed during inspection.");
    return { session: connection, contextId: id, origin: new URL(frame.url).origin, generation };
  };
  return {
    async identity(sessionId) {
      const value = await world();
      return { sessionId, origin: value.origin, documentGeneration: value.generation };
    },
    async evaluate(input) {
      const value = await world();
      if (value.origin !== input.identity.origin || value.generation !== input.identity.documentGeneration) {
        throw new BrowserControlError("STALE_DOCUMENT", "The authorized site tool execution context changed.");
      }
      const response = await value.session.send("Runtime.evaluate", {
        expression: webMcpPageExpression(input), contextId: value.contextId, awaitPromise: true, returnByValue: true,
      });
      if (response.exceptionDetails) throw new BrowserControlError("WEBMCP_FAILED", "The fixed site tool operation failed.", input.operation === "call");
      const result: unknown = response.result.value;
      return result;
    },
    async dispose() {
      disposed = true;
      contexts.clear();
      if (sessionPromise) await (await sessionPromise).detach();
    },
  };
}
