import type { Readable } from "node:stream";

/** The pinned SDK transport does not close itself when stdin reaches EOF. */
export function closeWorkerTransportOnEof(
  input: Pick<Readable, "once" | "off">,
  transport: { close(): Promise<void> },
  onFailure: () => void,
): () => void {
  const onEnd = (): void => { void transport.close().catch(onFailure); };
  input.once("end", onEnd);
  return () => { input.off("end", onEnd); };
}

export function reportWorkerCleanupFailure(): void {
  process.stderr.write("Worker cleanup failed.\n");
  process.exitCode = 1;
}
