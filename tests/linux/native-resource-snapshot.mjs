import { readdir, readFile, readlink, statfs } from "node:fs/promises";

const NS_PER_MS = 1000000n;
// Cooperative bounds do not interrupt an in-flight filesystem operation.
export function createSnapshotBudget({ now = () => process.hrtime.bigint(), milliseconds = 500,
  processes = 2048, fds = 8192 } = {}) {
  const deadline = now() + BigInt(milliseconds) * NS_PER_MS;
  const used = { processes: 0, fds: 0 };
  const exhausted = { time: false, processes: false, fds: false };
  function take(kind) {
    if (now() >= deadline) exhausted.time = true;
    if (kind && used[kind] >= (kind === "processes" ? processes : fds)) exhausted[kind] = true;
    if (Object.values(exhausted).some(Boolean)) return false;
    if (kind) used[kind]++;
    return true;
  }
  return { take, exhausted };
}
export function parseProcStat(text) {
  const end = text.lastIndexOf(")");
  if (end < 0) return null;
  const f = text.slice(end + 2).trim().split(/\s+/);
  const ppid = Number(f[1]), threads = Number(f[17]), startTicks = f[19];
  return Number.isSafeInteger(ppid) && ppid >= 0 && Number.isSafeInteger(threads) &&
    threads >= 0 && /^\d+$/.test(startTicks ?? "") ? { ppid, threads, startTicks } : null;
}
async function procStat(pid) {
  try { return parseProcStat(await readFile(`/proc/${pid}/stat`, "utf8")); }
  catch { return null; }
}
export async function nativeProcessStartTicks(pid) {
  if (!Number.isSafeInteger(pid) || pid < 1) throw new TypeError("invalid PID");
  return (await procStat(pid))?.startTicks ?? null;
}
async function counts(pid, expected, budget) {
  const out = { threads: expected.threads, fds: null, sockets: null,
    nofileSoft: null, nofileHard: null, complete: true };
  try {
    if (!budget.take()) return { ...out, complete: false };
    const m = /^Max open files\s+(\S+)\s+(\S+)/m.exec(await readFile(`/proc/${pid}/limits`, "utf8"));
    const num = x => /^\d+$/.test(x ?? "") && Number.isSafeInteger(Number(x)) ? Number(x) : null;
    out.nofileSoft = num(m?.[1]); out.nofileHard = num(m?.[2]);
    if (out.nofileSoft === null || out.nofileHard === null) out.complete = false;
  } catch { out.complete = false; }
  try {
    if (!budget.take()) return { ...out, complete: false };
    const path = `/proc/${pid}/fd`, list = await readdir(path);
    out.fds = list.length; out.sockets = 0;
    for (const fd of list) {
      if (!budget.take("fds")) { out.complete = false; break; }
      try { if ((await readlink(`${path}/${fd}`)).startsWith("socket:[")) out.sockets++; }
      catch { out.complete = false; }
    }
  } catch { out.complete = false; }
  if (budget.take()) {
    const after = await procStat(pid);
    if (!after || after.startTicks !== expected.startTicks || after.ppid !== expected.ppid) out.complete = false;
  } else out.complete = false;
  return out;
}
// Fixed numeric counts only; never emits process names, paths, or environment.
export async function snapshotNativeResources({ pid, startTicks, sequence },
  { budget = createSnapshotBudget(), getRootStat = procStat } = {}) {
  if (!Number.isSafeInteger(pid) || pid < 1 || !/^\d+$/.test(startTicks ?? "") ||
      !Number.isSafeInteger(sequence) || sequence < 0) throw new TypeError("invalid snapshot identity");
  const monotonicNs = process.hrtime.bigint().toString();
  const root = await getRootStat(pid);
  if (!root || root.startTicks !== startTicks)
    return { pid, startTicks, sequence, monotonicNs, identityValid: false, complete: false,
      budgetExhausted: budget.exhausted };
  let names = [], complete = true, vanishedOrUnreadable = 0;
  try {
    if (budget.take()) names = (await readdir("/proc")).filter(x => /^\d+$/.test(x));
    else complete = false;
  } catch { complete = false; }
  const table = new Map();
  for (const name of names) {
    if (!budget.take("processes")) { complete = false; break; }
    const stat = await procStat(name);
    if (stat) table.set(Number(name), stat);
    else vanishedOrUnreadable++;
  }
  const children = new Map();
  for (const [child, stat] of table) {
    if (!budget.take()) { complete = false; break; }
    const group = children.get(stat.ppid) ?? [];
    group.push(child); children.set(stat.ppid, group);
  }
  const tree = [pid], seen = new Set(tree);
  for (let i = 0; i < tree.length && budget.take(); i++)
    for (const child of children.get(tree[i]) ?? [])
      if (!seen.has(child)) { seen.add(child); tree.push(child); }
  let threads = 0, fds = 0, sockets = 0, maxFds = 0, maxThreads = 0;
  let rootNofileSoft = null, rootNofileHard = null;
  for (const child of tree) {
    if (!budget.take()) { complete = false; break; }
    const stat = table.get(child);
    if (!stat) { complete = false; continue; }
    const c = await counts(child, stat, budget);
    if (!c.complete) complete = false;
    threads += c.threads; fds += c.fds ?? 0; sockets += c.sockets ?? 0;
    maxFds = Math.max(maxFds, c.fds ?? 0); maxThreads = Math.max(maxThreads, c.threads);
    if (child === pid) { rootNofileSoft = c.nofileSoft; rootNofileHard = c.nofileHard; }
  }
  let shmBytes = null, shmAvailableBytes = null;
  try {
    if (budget.take()) {
      const s = await statfs(`/proc/${pid}/root/dev/shm`, { bigint: true });
      shmBytes = (s.blocks * s.bsize).toString();
      shmAvailableBytes = (s.bavail * s.bsize).toString();
    } else complete = false;
  } catch { complete = false; }
  // Always revalidate the owned PID, including on budget exhaustion.
  const finalRoot = await getRootStat(pid);
  const identityValid = !!finalRoot && finalRoot.startTicks === startTicks;
  return { pid, startTicks, sequence, monotonicNs, identityValid,
    complete: complete && identityValid && vanishedOrUnreadable === 0 &&
      !Object.values(budget.exhausted).some(Boolean), budgetExhausted: budget.exhausted,
    processCount: tree.length, vanishedOrUnreadable, threads, maxThreads, fds, maxFds, sockets,
    rootNofileSoft, rootNofileHard, shmBytes, shmAvailableBytes };
}
