#!/usr/bin/env node
// Run once outside the unit (--baseline), then inside the operator cgroup.
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createSocket } from "node:dgram";
import { createServer, createConnection } from "node:net";
const send = () => new Promise(resolve => {
  const socket = createSocket("udp4");
  const timer = setTimeout(() => { socket.close(); resolve("TIMEOUT"); }, 2000);
  socket.send(Buffer.from([0]), 9, "198.51.100.1", error => {
    clearTimeout(timer); socket.close(); resolve(error?.code ?? "ACCEPTED");
  });
});
const baseline = process.argv.includes("--baseline");
if (baseline) {
  const result = await send();
  console.log(JSON.stringify({ baseline: true, documentationAddressUDP: result }));
  assert.equal(result, "ACCEPTED", "No unfiltered baseline; cannot attribute denial to the worker boundary");
} else {
  const cgroup = (await readFile("/proc/self/cgroup", "utf8")).split("\n").find(line => line.startsWith("0::"))?.slice(3);
  assert.ok(cgroup?.startsWith("/") && !cgroup.includes(".."));
  const root = "/sys/fs/cgroup" + cgroup;
  const field = async name => (await readFile(root + "/" + name, "utf8")).trim();
  const memoryMax = await field("memory.max"), cpuMax = await field("cpu.max"), tasksMax = await field("pids.max");
  assert.equal(memoryMax, "2147483648"); assert.equal(tasksMax, "64");
  const [quota, period] = cpuMax.split(/\s+/).map(Number);
  assert.ok(Number.isFinite(quota) && quota > 0 && quota / period <= 1);
  const loopback = await new Promise((resolve, reject) => {
    const sockets = new Set();
    const server = createServer(socket => { sockets.add(socket); socket.on("close", () => sockets.delete(socket)); socket.end("owned-loopback"); });
    const timer = setTimeout(() => {
      for (const socket of sockets) socket.destroy(); server.close(); reject(new Error("Loopback deadline"));
    }, 3000);
    server.once("error", error => { clearTimeout(timer); reject(error); });
    server.listen(0, "127.0.0.1", () => {
      const client = createConnection(server.address().port, "127.0.0.1");
      let text = "";
      client.on("data", bytes => { text += bytes; });
      client.once("error", error => { clearTimeout(timer); client.destroy(); server.close(); reject(error); });
      client.once("end", () => { clearTimeout(timer); server.close(() => resolve(text)); });
    });
  });
  assert.equal(loopback, "owned-loopback");
  const denied = await send();
  assert.ok(denied === "EPERM" || denied === "EACCES", "Expected actual policy denial, got " + denied);
  console.log(JSON.stringify({ cgroup, memoryMax, cpuMax, tasksMax, loopback: true,
    documentationAddressUDP: denied, memoryPeak: await field("memory.peak"), cpu: await field("cpu.stat") }, null, 2));
}
