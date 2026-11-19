import { z } from "zod";
import { BrowserControlRequestSchema, browserControlMutates } from "./protocol.js";
import type { BrowserControlRequest, BrowserControlResponse } from "./protocol.js";
const response = z.discriminatedUnion("ok", [
  z.object({ version: z.literal(1), ok: z.literal(true), value: z.unknown() }).strict(),
  z.object({ version: z.literal(1), ok: z.literal(false), error: z.object({ code: z.string().max(256), message: z.string().max(4096), mayHaveCompleted: z.boolean() }).strict() }).strict(),
]);
/** Forward to an already authorized native gateway. Native owns refs and semantics; no raw-endpoint adapter or retries. */
export function createNativeBrowserTransport<Context = undefined>(send: (request: BrowserControlRequest, context?: Context) => Promise<unknown>) {
  let tail: Promise<unknown> = Promise.resolve();
  const execute = async (input: BrowserControlRequest, context?: Context): Promise<BrowserControlResponse> => {
    const request = BrowserControlRequestSchema.safeParse(input);
    if (!request.success) return failure("INVALID_ARGUMENTS", false);
    try {
      const answer = response.safeParse(await send(request.data, context));
      return answer.success ? answer.data : failure("COMMAND_FAILED", (browserControlMutates(request.data.method) || request.data.tabId !== undefined));
    } catch { return failure("COMMAND_FAILED", (browserControlMutates(request.data.method) || request.data.tabId !== undefined)); }
  };
  return {
    call(input: BrowserControlRequest, context?: Context) {
      const next = tail.then(() => execute(input, context));
      tail = next.catch(() => undefined);
      return next;
    },
  };
}
const failure = (code: string, mayHaveCompleted: boolean): BrowserControlResponse => ({ version: 1, ok: false, error: { code, message: "The native browser request failed. Observe before continuing.", mayHaveCompleted } });
