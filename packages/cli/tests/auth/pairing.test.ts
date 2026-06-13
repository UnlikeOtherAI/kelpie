import { describe, it, expect, vi, afterEach } from "vitest";
import {
  pair,
  pollPairStatus,
  redact,
  redactObject,
  requestPair,
} from "../../src/auth/pairing.js";

const baseCtx = {
  host: "192.168.1.42",
  port: 8420,
  clientId: "client-1",
  clientName: "alice@thinkpad",
  pollIntervalMs: 1,
  overallTimeoutMs: 25,
  perRequestTimeoutMs: 50,
};

function mockFetchSequence(
  responses: { status: number; body: unknown; ok?: boolean }[],
): { calls: { url: string; init?: RequestInit }[]; restore: () => void } {
  const original = globalThis.fetch;
  const calls: { url: string; init?: RequestInit }[] = [];
  let i = 0;
  globalThis.fetch = vi.fn(async (url: string | URL | Request, init?: RequestInit) => {
    calls.push({ url: url as string, init });
    const r = responses[Math.min(i, responses.length - 1)];
    i += 1;
    return new Response(JSON.stringify(r.body), {
      status: r.status,
      headers: { "Content-Type": "application/json" },
    });
  }) as typeof fetch;
  return {
    calls,
    restore: () => {
      globalThis.fetch = original;
    },
  };
}

describe("requestPair", () => {
  afterEach(() => vi.restoreAllMocks());

  it("issues POST /v1/pair with the expected body", async () => {
    const m = mockFetchSequence([
      { status: 202, body: { status: "pending", requestId: "r1", expiresAt: 1, sourceAddress: "ip" } },
    ]);
    const result = await requestPair(baseCtx);
    m.restore();

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.pending.requestId).toBe("r1");
    }
    expect(m.calls[0].url).toBe("http://192.168.1.42:8420/v1/pair");
    expect(m.calls[0].init?.method).toBe("POST");
    const body = JSON.parse(m.calls[0].init?.body as string);
    expect(body).toEqual({ clientId: "client-1", clientName: "alice@thinkpad" });
  });

  it("returns DENIED on a 403 response", async () => {
    const m = mockFetchSequence([
      { status: 403, body: { success: false, error: { code: "DENIED", message: "Suppressed" } } },
    ]);
    const result = await requestPair(baseCtx);
    m.restore();
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe("DENIED");
    }
  });
});

describe("pollPairStatus", () => {
  afterEach(() => vi.restoreAllMocks());

  it("returns approved + token + scope when status transitions", async () => {
    const m = mockFetchSequence([
      { status: 200, body: { status: "pending" } },
      { status: 200, body: { status: "approved", scope: "persistent", token: "tok-1" } },
    ]);
    const result = await pollPairStatus(baseCtx, "r1");
    m.restore();
    expect(result.status).toBe("approved");
    if (result.status === "approved") {
      expect(result.scope).toBe("persistent");
      expect(result.token).toBe("tok-1");
    }
  });

  it("surfaces denied terminal state", async () => {
    const m = mockFetchSequence([{ status: 200, body: { status: "denied" } }]);
    const result = await pollPairStatus(baseCtx, "r1");
    m.restore();
    expect(result.status).toBe("denied");
  });

  it("returns expired when the overall timeout fires", async () => {
    const m = mockFetchSequence([
      { status: 200, body: { status: "pending" } },
      { status: 200, body: { status: "pending" } },
      { status: 200, body: { status: "pending" } },
    ]);
    const result = await pollPairStatus({ ...baseCtx, overallTimeoutMs: 3, pollIntervalMs: 1 }, "r1");
    m.restore();
    expect(["expired", "pending"]).toContain(result.status);
  });
});

describe("pair (issue + poll)", () => {
  afterEach(() => vi.restoreAllMocks());

  it("walks POST then status to approved", async () => {
    const m = mockFetchSequence([
      { status: 202, body: { status: "pending", requestId: "r1", expiresAt: 1, sourceAddress: "ip" } },
      { status: 200, body: { status: "approved", scope: "session", token: "tok-x" } },
    ]);
    const result = await pair(baseCtx);
    m.restore();
    expect(result.status).toBe("approved");
    if (result.status === "approved") {
      expect(result.scope).toBe("session");
      expect(result.token).toBe("tok-x");
    }
  });

  it("surfaces a POST failure as an error result", async () => {
    const m = mockFetchSequence([
      { status: 500, body: { success: false, error: { code: "WTF", message: "boom" } } },
    ]);
    const result = await pair(baseCtx);
    m.restore();
    expect(result.status).toBe("error");
  });
});

describe("redact", () => {
  it("replaces Authorization header bearer values", () => {
    expect(redact("Authorization: Bearer abcdef.ghijkl-MNOP")).toContain("[redacted]");
  });

  it("masks JSON token field values", () => {
    expect(redact('{"token":"abc-xyz_DEF"}')).toContain('"token":"[redacted]"');
  });

  it("masks bare bearer-shaped strings", () => {
    const masked = redact("found token AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA in log");
    expect(masked).toContain("[redacted]");
  });
});

describe("redactObject", () => {
  it("masks token/bearer keys recursively", () => {
    const out = redactObject({
      ok: true,
      token: "secret-1",
      nested: { bearer: "secret-2", other: "value" },
    }) as { token: string; nested: { bearer: string; other: string } };
    expect(out.token).toBe("[redacted]");
    expect(out.nested.bearer).toBe("[redacted]");
    expect(out.nested.other).toBe("value");
  });

  it("masks bearer-shaped strings inside string fields", () => {
    const out = redactObject({ message: "token AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA seen" }) as {
      message: string;
    };
    expect(out.message).toContain("[redacted]");
  });
});
