const UOA_ORIGIN = "https://authentication.unlikeotherai.com";

export interface AccountPairContext {
  host: string;
  port: number;
  clientId: string;
  clientName: string;
  perRequestTimeoutMs?: number;
  /** Existing authorized session; spendable tokens are sent only to the fixed TLS UOA origin. */
  accountAccessToken?: () => Promise<string | undefined>;
  /** Authorized integrations can mint the narrow ticket using their own existing UOA session. */
  accountPairingTicket?: (challenge: string, clientId: string) => Promise<string>;
}

export type AccountPairResult =
  | { status: "approved"; scope: "session"; token: string; requestId: string }
  | { status: "error"; code: string; message: string };

function failure(code = "ACCOUNT_AUTH_FAILED"): AccountPairResult {
  return { status: "error", code, message: "Account pairing could not be verified" };
}

async function post(url: string, body: object, timeoutMs: number, token?: string): Promise<{ status: number; data: Record<string, unknown> }> {
  const response = await fetch(url, {
    method: "POST",
    redirect: "error",
    cache: "no-store",
    headers: { "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(timeoutMs),
  });
  const data: unknown = await response.json();
  return { status: response.status, data: data && typeof data === "object" && !Array.isArray(data) ? data as Record<string, unknown> : {} };
}

/** No approval prompt or credential forwarding. Failure never silently downgrades account authentication. */
export async function pairAccount(ctx: AccountPairContext): Promise<AccountPairResult | undefined> {
  let accessToken: string | undefined;
  try { accessToken = ctx.accountAccessToken ? await ctx.accountAccessToken() : process.env.KELPIE_UOA_ACCESS_TOKEN; }
  catch { return failure(); }
  if (!accessToken && !ctx.accountPairingTicket) return undefined;
  const host = ctx.host.includes(":") && !ctx.host.startsWith("[") ? `[${ctx.host}]` : ctx.host;
  const target = `http://${host}:${ctx.port}/v1/pair`;
  const timeout = ctx.perRequestTimeoutMs ?? 10_000;
  const identity = { clientId: ctx.clientId, clientName: ctx.clientName, account: true };
  try {
    const challenge = await post(target, identity, timeout);
    if (challenge.status !== 202 || challenge.data.status !== "account_challenge"
      || typeof challenge.data.requestId !== "string" || !/^[A-Za-z0-9_-]{43}$/.test(challenge.data.requestId)
      || typeof challenge.data.expiresAt !== "number" || challenge.data.expiresAt <= Date.now()
      || challenge.data.expiresAt > Date.now() + 120_000) return failure();
    const requestId = challenge.data.requestId;
    const issued = ctx.accountPairingTicket ? { status: 200, data: { pairing_ticket: await ctx.accountPairingTicket(requestId, ctx.clientId) } }
      : await post(`${UOA_ORIGIN}/oauth/kelpie/pair`, { challenge: requestId, clientId: ctx.clientId }, timeout, accessToken);
    if (issued.status !== 200 || typeof issued.data.pairing_ticket !== "string"
      || !issued.data.pairing_ticket || issued.data.pairing_ticket.length > 8192) return failure();
    const result = await post(target, { ...identity, requestId, accountTicket: issued.data.pairing_ticket }, timeout);
    if (result.status !== 200 || result.data.status !== "approved" || result.data.scope !== "session"
      || typeof result.data.token !== "string" || !/^[A-Za-z0-9_-]{43}$/.test(result.data.token)
      || typeof result.data.expiresAt !== "number" || result.data.expiresAt <= Date.now()
      || result.data.expiresAt > challenge.data.expiresAt) return failure();
    return { status: "approved", scope: "session", token: result.data.token, requestId };
  } catch { return failure(); }
}
