import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createConnection } from "node:net";

export async function readNativeIdentity(pid) {
  assert.ok(Number.isInteger(pid) && pid > 1);
  try {
    const stat = await readFile("/proc/" + pid + "/stat", "utf8");
    const fields = stat.slice(stat.lastIndexOf(")") + 2).split(" ");
    assert.match(fields[19], /^[0-9]+$/);
    return { pid, state: fields[0], startTicks: fields[19] };
  } catch (error) {
    if (error.code === "ENOENT" || error.code === "ESRCH") return undefined;
    throw error;
  }
}

/** Observe natural retirement; never signal, clear state or treat a zombie as absence. */
export async function waitForNativeRetirement(identity, timeoutMs = 8000) {
  assert.ok(Number.isInteger(timeoutMs) && timeoutMs >= 100 && timeoutMs <= 10000);
  const began = performance.now();
  while (performance.now() - began < timeoutMs) {
    const current = await readNativeIdentity(identity.pid);
    if (!current || current.startTicks !== identity.startTicks)
      return { state: current ? "recycled" : "absent", elapsedMs: performance.now() - began };
    await new Promise(resolve => setTimeout(resolve, 40));
  }
  throw Error("The exact native process did not retire naturally before the deadline");
}

/** Connect without credentials; a new listener must never receive the retired grant. */
export async function verifyClosedSocket(port) {
  assert.ok(Number.isInteger(port) && port > 0 && port <= 65535);
  const result = await new Promise(resolve => {
    let done = false;
    const socket = createConnection({ host: "127.0.0.1", port });
    const finish = state => { if (done) return; done = true; socket.setTimeout(0); socket.destroy(); resolve(state); };
    socket.once("connect", () => finish("listening"));
    socket.once("error", error => finish(error.code === "ECONNREFUSED" ? "refused" : error.code));
    socket.setTimeout(1000, () => finish("timeout"));
  });
  assert.equal(result, "refused", "The retired native socket was not demonstrably closed");
  return { state: result };
}
