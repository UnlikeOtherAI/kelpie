import { BrowserControlError } from "./protocol.js";

/** Trusted-host continuation only; public transports serialize fixed error fields. */
export class RetainedCleanupError extends BrowserControlError {
  constructor(readonly retryCleanup: () => Promise<void>) {
    super("CLEANUP_PENDING", "Resource cleanup is still owned and will retry.");
  }
}

interface CleanupTask {
  dispose(): Promise<void>;
  running?: Promise<void>;
  timer?: ReturnType<typeof setTimeout>;
  attempts: number;
}
export interface CleanupOwner {
  close(key: string, dispose: () => Promise<void>): Promise<void>;
  pending(): number;
  drain(): Promise<void>;
}

/**
 * A failed cleanup remains owned and retries while the host lives. A caller sees
 * CLEANUP_PENDING instead of a successful release or a silently abandoned handle.
 */
export function createCleanupOwner(retryMs = 1000): CleanupOwner {
  const tasks = new Map<string, CleanupTask>();
  const run = (key: string, task: CleanupTask): Promise<void> => {
    if (tasks.get(key) !== task) return Promise.resolve();
    if (task.running) return task.running;
    if (task.timer !== undefined) { clearTimeout(task.timer); task.timer = undefined; }
    task.running = Promise.resolve().then(() => task.dispose()).then(() => {
      tasks.delete(key);
    }, () => {
      task.attempts++;
      task.running = undefined;
      task.timer = setTimeout(() => { void run(key, task).catch(() => undefined); }, Math.min(30_000, retryMs * 2 ** Math.min(task.attempts - 1, 5)));
      const timer = task.timer as unknown as { unref?: () => void };
      timer.unref?.();
      throw new RetainedCleanupError(() => run(key, task));
    });
    return task.running;
  };
  return {
    close(key, dispose) {
      const task = tasks.get(key) ?? { dispose, attempts: 0 };
      tasks.set(key, task);
      return run(key, task);
    },
    pending() { return tasks.size; },
    async drain() {
      const results = await Promise.allSettled([...tasks].map(([key, task]) => run(key, task)));
      if (results.some((result) => result.status === "rejected")) throw new BrowserControlError("CLEANUP_PENDING", "Resource cleanup remains owned and will retry.");
    },
  };
}
