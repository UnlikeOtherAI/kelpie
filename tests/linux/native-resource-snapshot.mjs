import { readdir, readFile, readlink, statfs } from "node:fs/promises";
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
async function counts(pid, expected) {
  const out = { threads: expected.threads, fds: null, sockets: null,
    nofileSoft: null, nofileHard: null, complete: true };
  try {
    const m = /^Max open files\s+(\S+)\s+(\S+)/m.exec(await readFile(`/proc/${pid}/limits`, "utf8"));
    const num = x => /^\d+$/.test(x ?? "") && Number.isSafeInteger(Number(x)) ? Number(x) : null;
    out.nofileSoft = num(m?.[1]); out.nofileHard = num(m?.[2]);
    if (out.nofileSoft === null || out.nofileHard === null) out.complete = false;
  } catch { out.complete = false; }
  try {
    const path = `/proc/${pid}/fd`, list = await readdir(path);
    if (list.length > 65536) throw new Error("fd bound");
    out.fds = list.length; out.sockets = 0;
    for (const fd of list) {
      try { if ((await readlink(`${path}/${fd}`)).startsWith("socket:[")) out.sockets++; }
      catch { out.complete = false; }
    }
  } catch { out.complete = false; }
  const after = await procStat(pid);
  if (!after || after.startTicks !== expected.startTicks || after.ppid !== expected.ppid) out.complete = false;
  return out;
}
// Fixed numeric counts only; never emits process names, paths, or environment.
export async function snapshotNativeResources({ pid, startTicks, sequence }) {
  if (!Number.isSafeInteger(pid) || pid < 1 || !/^\d+$/.test(startTicks ?? "") ||
      !Number.isSafeInteger(sequence) || sequence < 0) throw new TypeError("invalid snapshot identity");
  const monotonicNs = process.hrtime.bigint().toString(), root = await procStat(pid);
  if (!root || root.startTicks !== startTicks)
    return { pid, startTicks, sequence, monotonicNs, identityValid: false, complete: false };
  let names;
  try { names = (await readdir("/proc")).filter(x => /^\d+$/.test(x)); }
  catch { return { pid, startTicks, sequence, monotonicNs, identityValid: true, complete: false }; }
  if (names.length > 8192) return { pid, startTicks, sequence, monotonicNs, identityValid: true, complete: false };
  const table = new Map();
  let vanishedOrUnreadable = 0;
  for (const name of names) {
    const stat = await procStat(name);
    if (stat) table.set(Number(name), stat);
    else vanishedOrUnreadable++;
  }
  const tree = [pid];
  for (let i = 0; i < tree.length; i++)
    for (const [child, stat] of table)
      if (child !== pid && stat.ppid === tree[i] && !tree.includes(child)) tree.push(child);
  let complete = vanishedOrUnreadable === 0, threads = 0, fds = 0, sockets = 0, maxFds = 0, maxThreads = 0;
  let rootNofileSoft = null, rootNofileHard = null;
  for (const child of tree) {
    const stat = table.get(child);
    if (!stat) { complete = false; continue; }
    const c = await counts(child, stat);
    if (!c.complete) complete = false;
    threads += c.threads; fds += c.fds ?? 0; sockets += c.sockets ?? 0;
    maxFds = Math.max(maxFds, c.fds ?? 0); maxThreads = Math.max(maxThreads, c.threads);
    if (child === pid) { rootNofileSoft = c.nofileSoft; rootNofileHard = c.nofileHard; }
  }
  let shmBytes = null, shmAvailableBytes = null;
  try {
    const s = await statfs(`/proc/${pid}/root/dev/shm`, { bigint: true });
    shmBytes = (s.blocks * s.bsize).toString();
    shmAvailableBytes = (s.bavail * s.bsize).toString();
  } catch { complete = false; }
  const finalRoot = await procStat(pid);
  const identityValid = !!finalRoot && finalRoot.startTicks === startTicks;
  return { pid, startTicks, sequence, monotonicNs, identityValid, complete: complete && identityValid,
    processCount: tree.length, vanishedOrUnreadable, threads, maxThreads, fds, maxFds, sockets,
    rootNofileSoft, rootNofileHard, shmBytes, shmAvailableBytes };
}
