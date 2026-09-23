import { execFile, spawn } from "node:child_process";
import { createServer } from "node:net";
import { promisify } from "node:util";

import { delay } from "./process.mjs";

const execFileAsync = promisify(execFile);

/**
 * Holds a loopback port with a Node listener. libuv binds it with default
 * options, so Windows already refuses a SO_REUSEADDR bind of the same address.
 */
export async function holdNodeLoopbackPort() {
  const server = createServer();
  await new Promise((resolvePromise, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolvePromise);
  });
  const address = server.address();
  if (address === null || typeof address === "string") throw new Error("Node port holder did not expose a TCP port");
  return {
    description: "a Node listener",
    port: address.port,
    pid: process.pid,
    close: () => new Promise((resolvePromise, reject) => server.close(error => error ? reject(error) : resolvePromise())),
  };
}

/**
 * Holds a loopback port with SO_REUSEADDR set, which is what cpp-httplib's
 * default options leave on Windows and so what an unfixed Kelpie holds. A
 * second SO_REUSEADDR socket can bind that address, so this is the holder
 * that exposes a shareable control listener.
 */
export async function holdReusableLoopbackPort(timeoutMs = 20_000) {
  const script = [
    "$socket = New-Object System.Net.Sockets.Socket([System.Net.Sockets.AddressFamily]::InterNetwork, [System.Net.Sockets.SocketType]::Stream, [System.Net.Sockets.ProtocolType]::Tcp)",
    "$socket.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::Socket, [System.Net.Sockets.SocketOptionName]::ReuseAddress, $true)",
    "$socket.Bind((New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Loopback, 0)))",
    "$socket.Listen(16)",
    "[Console]::Out.WriteLine($socket.LocalEndPoint.Port)",
    "[Console]::Out.Flush()",
    // Windows PowerShell does not reliably block on a piped stdin read, so the
    // holder sleeps until the runner ends its exact process.
    "while ($true) { Start-Sleep -Seconds 1 }",
  ].join("; ");
  const child = spawn("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", script], {
    stdio: ["ignore", "pipe", "pipe"],
    windowsHide: true,
  });
  const exited = new Promise(resolvePromise => child.once("exit", code => resolvePromise(code)));
  let stdout = "";
  let stderr = "";
  child.stdout.setEncoding("utf8");
  child.stderr.setEncoding("utf8");
  child.stdout.on("data", chunk => { stdout += chunk; });
  child.stderr.on("data", chunk => { stderr += chunk; });
  const deadline = Date.now() + timeoutMs;
  while (!/^\d+\r?\n/.test(stdout)) {
    if (child.exitCode !== null || Date.now() > deadline) {
      child.kill();
      throw new Error(`SO_REUSEADDR port holder did not start: ${stderr || stdout || "no output"}`);
    }
    await delay(50);
  }
  return {
    description: "a SO_REUSEADDR listener",
    port: Number(stdout.trim()),
    pid: child.pid,
    close: async () => {
      if (child.exitCode === null) child.kill();
      await Promise.race([exited, delay(5_000)]);
    },
  };
}

/** PIDs that own a LISTENING TCP socket on the given local port. */
export async function listeningPids(port) {
  // runCommand keeps only the tail of its output, and a busy machine's full
  // netstat table is larger than that, so read the whole table here.
  const { stdout } = await execFileAsync("netstat.exe", ["-ano", "-p", "TCP"], {
    windowsHide: true,
    maxBuffer: 16 * 1024 * 1024,
    timeout: 20_000,
  });
  const pids = [];
  for (const line of stdout.split(/\r?\n/)) {
    const columns = line.trim().split(/\s+/);
    if (columns.length !== 5 || columns[0] !== "TCP" || columns[3] !== "LISTENING") continue;
    if (columns[1].endsWith(`:${port}`)) pids.push(Number(columns[4]));
  }
  return pids;
}
