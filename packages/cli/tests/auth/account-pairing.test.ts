import { afterEach, describe, expect, it, vi } from "vitest";
import { pair } from "../../src/auth/pairing.js";

const challenge = "c".repeat(43), token = "t".repeat(43);
const ctx = { host: "192.168.1.42", port: 8420, clientId: "client", clientName: "Client",
  accountAccessToken: async () => "UOA-spendable-credential" };
function responses(values: { status: number; body: object }[]) {
  const calls: { url: string; init: RequestInit }[] = [];
  vi.stubGlobal("fetch", vi.fn(async (url: string, init: RequestInit) => {
    calls.push({ url, init });
    const next = values.shift();
    if (!next) throw new Error("Unexpected request");
    return new Response(JSON.stringify(next.body), { status: next.status });
  }));
  return calls;
}
const offered = () => ({ status: 202, body: { status: "account_challenge", requestId: challenge, expiresAt: Date.now() + 120_000 } });
const approved = () => ({ status: 200, body: { status: "approved", scope: "session", token, expiresAt: Date.now() + 60_000 } });

describe("same-account pairing", () => {
  afterEach(() => { vi.unstubAllGlobals(); vi.unstubAllEnvs(); });

  it("skips approval and sends the account credential only to the fixed UOA origin", async () => {
    const calls = responses([offered(), { status: 200, body: { pairing_ticket: "narrow-ticket" } }, approved()]);
    const prompt = vi.fn();
    expect(await pair({ ...ctx, onApprovalRequired: prompt })).toEqual({ status: "approved", scope: "session", token, requestId: challenge });
    expect(prompt).not.toHaveBeenCalled();
    expect(calls.map(c => c.url)).toEqual(["http://192.168.1.42:8420/v1/pair",
      "https://authentication.unlikeotherai.com/oauth/kelpie/pair", "http://192.168.1.42:8420/v1/pair"]);
    expect(new Headers(calls[1].init.headers).get("Authorization")).toBe("Bearer UOA-spendable-credential");
    for (const call of [calls[0], calls[2]]) {
      expect(JSON.stringify(call.init)).not.toContain("UOA-spendable-credential");
      expect(call.init.redirect).toBe("error");
    }
    expect(JSON.parse(calls[2].init.body as string)).toEqual({ account: true, clientId: "client", clientName: "Client",
      requestId: challenge, accountTicket: "narrow-ticket" });
  });

  it("supports an existing authenticated application's ticket provider without a spendable token", async () => {
    const calls = responses([offered(), approved()]);
    const mint = vi.fn(async () => "application-issued-ticket");
    expect((await pair({ ...ctx, accountAccessToken: async () => undefined, accountPairingTicket: mint })).status).toBe("approved");
    expect(mint).toHaveBeenCalledWith(challenge, "client");
    expect(calls).toHaveLength(2);
  });

  it.each([
    { status: 403, body: { error: { code: "ACCOUNT_AUTH_FAILED", message: "secret" } } },
    { status: 200, body: { status: "approved", scope: "persistent", token } },
    { status: 200, body: { status: "approved", scope: "session", token, expiresAt: Date.now() - 1 } },
  ])("refuses invalid grants without downgrading to manual approval", async refused => {
    const calls = responses([offered(), { status: 200, body: { pairing_ticket: "ticket" } }, refused]);
    const prompt = vi.fn();
    const result = await pair({ ...ctx, onApprovalRequired: prompt });
    expect(result.status).toBe("error");
    expect(JSON.stringify(result)).not.toContain("secret");
    expect(prompt).not.toHaveBeenCalled();
    expect(calls).toHaveLength(3);
  });

  it("does not send the account credential after an expired or malformed LAN challenge", async () => {
    const calls = responses([{ status: 202, body: { status: "account_challenge", requestId: "forged", expiresAt: Date.now() + 600_000 } }]);
    expect((await pair(ctx)).status).toBe("error");
    expect(calls).toHaveLength(1);
  });

  it("preserves manual pairing when the caller has no account", async () => {
    vi.stubEnv("KELPIE_UOA_ACCESS_TOKEN", "");
    const calls = responses([{ status: 202, body: { status: "pending", requestId: "manual", expiresAt: Date.now() + 300_000 } },
      { status: 200, body: { status: "approved", scope: "persistent", token } }]);
    const prompt = vi.fn();
    const result = await pair({ ...ctx, accountAccessToken: async () => undefined, onApprovalRequired: prompt });
    expect(result.status).toBe("approved");
    expect(prompt).toHaveBeenCalledOnce();
    expect(calls.every(c => !c.url.includes("authentication"))).toBe(true);
    expect(JSON.parse(calls[0].init.body as string)).not.toHaveProperty("account");
  });

  it("redacts provider failures instead of reporting credentials", async () => {
    const result = await pair({ ...ctx, accountAccessToken: async () => { throw new Error("credential-secret"); } });
    expect(result.status).toBe("error");
    expect(JSON.stringify(result)).not.toContain("credential-secret");
  });
});
