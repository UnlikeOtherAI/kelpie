import { z } from "zod";
import { BrowserControlRequestSchema, browserControlMutates } from "./protocol.js";
import type { BrowserControlRequest, BrowserControlResponse, BrowserControlTransport } from "./protocol.js";
const response = z.discriminatedUnion("ok", [
  z.object({ version: z.literal(1), ok: z.literal(true), value: z.unknown() }).strict(),
  z.object({ version: z.literal(1), ok: z.literal(false), error: z.object({ code: z.string().max(256), message: z.string().max(4096), mayHaveCompleted: z.boolean() }).strict() }).strict(),
]);
/** Forward to an already authorized native gateway. Native owns refs and semantics; no raw-endpoint adapter or retries. */
export function createNativeBrowserTransport(send: (request: BrowserControlRequest) => Promise<unknown>): BrowserControlTransport {
  let tail: Promise<unknown> = Promise.resolve();
  const execute = async (input: BrowserControlRequest): Promise<BrowserControlResponse> => {
    const request = BrowserControlRequestSchema.safeParse(input);
    if (!request.success) return failure("INVALID_ARGUMENTS", false);
    try {
      const answer = response.safeParse(await send(request.data));
      return answer.success ? answer.data : failure("COMMAND_FAILED", browserControlMutates(request.data.method));
    } catch { return failure("COMMAND_FAILED", browserControlMutates(request.data.method)); }
  };
  return { call(input) { const next = tail.then(() => execute(input)); tail = next.catch(() => undefined); return next; } };
}
const failure = (code: string, mayHaveCompleted: boolean): BrowserControlResponse => ({ version: 1, ok: false, error: { code, message: "The native browser request failed. Observe before continuing.", mayHaveCompleted } });
