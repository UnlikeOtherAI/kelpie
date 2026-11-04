import { automationSessionOptionsSchema } from "@unlikeotherai/kelpie-shared";
import type { AutomationSessionOptions, AutomationSessionDescription } from "@unlikeotherai/kelpie-shared";
import { BrowserControlError } from "@unlikeotherai/kelpie-shared/browser-control";
import type { BrowserControlRequest, BrowserControlResponse, ManagedBrowserSession } from "@unlikeotherai/kelpie-shared/browser-control";

export interface ManagedSessionRegistryOptions {
  /** Bound by the trusted transport host, never chosen by tool arguments. */
  owner: string;
  authorize(owner: string): Promise<void> | void;
  allocate(options: AutomationSessionOptions): Promise<ManagedBrowserSession>;
  maxSessions?: number;
}
export interface ManagedSessionRegistry {
  create(options: AutomationSessionOptions): Promise<AutomationSessionDescription>;
  list(): Promise<AutomationSessionDescription[]>;
  describe(sessionId: string): Promise<AutomationSessionDescription>;
  call(sessionId: string, request: BrowserControlRequest): Promise<BrowserControlResponse>;
  close(sessionId: string): Promise<void>;
  dispose(): Promise<void>;
}

/** A registry belongs to one already authorized transport session, not to all CDP pages. */
export function createManagedSessionRegistry(options: ManagedSessionRegistryOptions): ManagedSessionRegistry {
  const owner = options.owner;
  const maxSessions = options.maxSessions ?? 4;
  if (!owner || owner.length > 256 || !Number.isInteger(maxSessions) || maxSessions < 1 || maxSessions > 16) {
    throw new BrowserControlError("INVALID_ARGUMENTS", "Invalid session registry ownership or limit.");
  }
  const sessions = new Map<string, ManagedBrowserSession>();
  let allocating = 0;
  let disposed = false;
  const active = (): void => {
    if (disposed) throw new BrowserControlError("SESSION_CLOSED", "The worker transport session is closed.");
  };
  const admit = async (): Promise<void> => {
    active();
    await options.authorize(owner);
    active();
  };
  const get = (sessionId: string): ManagedBrowserSession => {
    const session = sessions.get(sessionId);
    if (!session) throw new BrowserControlError("SESSION_NOT_FOUND", "The automation session is not owned by this transport.");
    return session;
  };
  const prune = async (): Promise<void> => {
    for (const [id, session] of sessions) {
      try { session.describe(); }
      catch (error) {
        if (!(error instanceof BrowserControlError) || error.code !== "SESSION_CLOSED") throw error;
        // Keep failed cleanup reachable for later retries; never restore access.
        await session.close();
        sessions.delete(id);
      }
    }
  };
  return {
    async create(input) {
      const parsed = automationSessionOptionsSchema.parse(input);
      await admit();
      await prune();
      if (sessions.size + allocating >= maxSessions) throw new BrowserControlError("RESOURCE_LIMIT", "The worker session limit has been reached.");
      allocating++;
      let session: ManagedBrowserSession | undefined;
      try {
        session = await options.allocate(parsed);
        await admit();
        const description = session.describe();
        if (sessions.has(description.sessionId)) throw new BrowserControlError("SESSION_CONFLICT", "The allocator returned a duplicate session identifier.");
        sessions.set(description.sessionId, session);
        return description;
      } catch (error) {
        if (session) await session.close().catch(() => undefined);
        throw error;
      } finally { allocating--; }
    },
    async list() { await admit(); await prune(); return [...sessions.values()].map((session) => session.describe()); },
    async describe(sessionId) { await admit(); return get(sessionId).describe(); },
    async call(sessionId, request) { await admit(); return get(sessionId).transport.call(request); },
    async close(sessionId) { await admit(); const session = get(sessionId); await session.close(); sessions.delete(sessionId); },
    async dispose() {
      disposed = true;
      const results = await Promise.allSettled([...sessions].map(async ([id, session]) => { await session.close(); sessions.delete(id); }));
      if (results.some((result) => result.status === "rejected")) throw new BrowserControlError("CLEANUP_FAILED", "Some worker sessions could not be closed.");
    },
  };
}
