import { spawn, spawnSync } from "node:child_process";
import { access, readFile, rm } from "node:fs/promises";

const MAX_LOG_BYTES = 32_768;

function capture(stream) {
  let text = "";
  stream?.setEncoding("utf8");
  stream?.on("data", chunk => {
    text = (text + chunk).slice(-MAX_LOG_BYTES);
  });
  return () => text;
}

export async function fileExists(path) {
  try {
    await access(path);
    return true;
  } catch {
    return false;
  }
}

export async function waitForReadiness(path, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  let lastError = "file was never created";
  while (Date.now() < deadline) {
    try {
      const value = JSON.parse(await readFile(path, "utf8"));
      if (typeof value.port === "number" && typeof value.token === "string" && value.token.length > 0) {
        return value;
      }
      lastError = "file did not contain port and token";
    } catch (error) {
      lastError = error instanceof Error ? error.message : String(error);
    }
    await delay(100);
  }
  throw new Error(`Timed out waiting for readiness file ${path}: ${lastError}`);
}

export function delay(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Starts an owned browser, hidden unless `visible`. A hidden launch that fails
 * startup exits at once; only a visible one keeps its window open to show the
 * failed stage.
 */
export function startBrowser(executable, args, { visible = false } = {}) {
  const child = spawn(executable, args, { stdio: ["ignore", "pipe", "pipe"], windowsHide: !visible });
  const stdout = capture(child.stdout);
  const stderr = capture(child.stderr);
  const exited = new Promise(resolve => {
    child.once("exit", (code, signal) => resolve({ code, signal, error: undefined }));
    child.once("error", error => resolve({ code: null, signal: null, error }));
  });
  return { child, exited, logs: () => ({ stdout: stdout(), stderr: stderr() }) };
}

/** Runs an owned short-lived command with bounded output and a hard timeout. */
export async function runCommand(executable, args, { env, timeoutMs = 20_000 } = {}) {
  const child = spawn(executable, args, {
    env: env === undefined ? process.env : { ...process.env, ...env },
    stdio: ["ignore", "pipe", "pipe"],
    windowsHide: true,
  });
  const stdout = capture(child.stdout);
  const stderr = capture(child.stderr);
  const exited = new Promise((resolve, reject) => {
    child.once("error", reject);
    child.once("exit", (code, signal) => resolve({ code, signal }));
  });
  const outcome = await Promise.race([
    exited,
    delay(timeoutMs).then(() => null),
  ]);
  if (outcome === null) {
    if (process.platform === "win32" && child.pid !== undefined) {
      spawnSync("taskkill.exe", ["/pid", String(child.pid), "/t", "/f"], { windowsHide: true });
    } else {
      child.kill("SIGKILL");
    }
    await exited.catch(() => undefined);
    throw new Error(`Command timed out: ${executable} ${args.join(" ")}`);
  }
  return { ...outcome, stdout: stdout(), stderr: stderr() };
}

async function waitForExit(child, timeoutMs) {
  if (child.exitCode !== null || child.signalCode !== null) return true;
  return Promise.race([
    new Promise(resolve => child.once("exit", () => resolve(true))),
    delay(timeoutMs).then(() => false),
  ]);
}

/**
 * Uses the authenticated control route for a clean close. If that route cannot
 * stop this owned child, termination is limited to its exact PID tree.
 */
export async function stopBrowser(browser, { gracefulClose, timeoutMs = 10_000 } = {}) {
  if (browser.child.exitCode !== null) return;
  let gracefulError;
  if (gracefulClose !== undefined) {
    try { await gracefulClose(); } catch (error) { gracefulError = error; }
  }
  if (gracefulClose !== undefined && await waitForExit(browser.child, timeoutMs)) return;
  if (process.platform === "win32" && browser.child.pid !== undefined) {
    spawnSync("taskkill.exe", ["/pid", String(browser.child.pid), "/t", "/f"], { windowsHide: true });
  } else {
    browser.child.kill("SIGKILL");
  }
  await waitForExit(browser.child, 5_000);
  if (gracefulError !== undefined) {
    throw new Error(`Authenticated browser close failed: ${gracefulError instanceof Error ? gracefulError.message : String(gracefulError)}`);
  }
  if (gracefulClose !== undefined) {
    throw new Error("Authenticated browser close did not exit before forced termination");
  }
}

/**
 * Proves the owned CEF renderer is actually restricted. This reads process
 * tokens only; it never trusts a readiness field or a browser command line.
 */
export async function assertSandboxedRenderer(browser, timeoutMs = 10_000) {
  if (process.platform !== "win32" || browser.child.pid === undefined) {
    throw new Error("Renderer sandbox verification requires an owned Windows browser process");
  }
  const pid = Number(browser.child.pid);
  if (!Number.isSafeInteger(pid) || pid < 1) throw new Error("Browser PID is invalid");
  const script = [
    "Add-Type @'",
    "using System; using System.Runtime.InteropServices;",
    "public static class KelpieToken {",
    " [DllImport(\"kernel32.dll\", SetLastError=true)] public static extern IntPtr OpenProcess(uint a, bool i, uint p);",
    " [DllImport(\"advapi32.dll\", SetLastError=true)] public static extern bool OpenProcessToken(IntPtr p, uint a, out IntPtr t);",
    " [DllImport(\"advapi32.dll\", SetLastError=true)] public static extern bool GetTokenInformation(IntPtr t, int c, IntPtr b, int n, out int r);",
    " [DllImport(\"advapi32.dll\", SetLastError=true)] public static extern IntPtr GetSidSubAuthorityCount(IntPtr s);",
    " [DllImport(\"advapi32.dll\", SetLastError=true)] public static extern IntPtr GetSidSubAuthority(IntPtr s, uint n);",
    " [DllImport(\"kernel32.dll\")] public static extern bool CloseHandle(IntPtr h);",
    "}",
    "'@",
    `$root = [uint32]${pid}; $all = @(Get-CimInstance Win32_Process | Select-Object ProcessId,ParentProcessId,CommandLine); $frontier = @($root); $descendants = @()`,
    "while($frontier.Count -gt 0){ $children=@($all | Where-Object { $frontier -contains [uint32]$_.ParentProcessId }); $descendants += $children; $frontier=@($children | ForEach-Object { [uint32]$_.ProcessId }) }",
    "$renderers=@($descendants | Where-Object { $_.CommandLine -match '(^|\\s)--type=renderer(\\s|$)' }); $records=@()",
    "foreach($p in $renderers){ $process=[KelpieToken]::OpenProcess(0x1000,$false,[uint32]$p.ProcessId); $token=[IntPtr]::Zero; $rid=$null; $tokenError=$null; if($process -eq [IntPtr]::Zero){$tokenError='OpenProcess:'+[Runtime.InteropServices.Marshal]::GetLastWin32Error()} elseif(-not [KelpieToken]::OpenProcessToken($process,0x0008,[ref]$token)){$tokenError='OpenProcessToken:'+[Runtime.InteropServices.Marshal]::GetLastWin32Error()} else { $needed=0; [KelpieToken]::GetTokenInformation($token,25,[IntPtr]::Zero,0,[ref]$needed)|Out-Null; $buffer=[Runtime.InteropServices.Marshal]::AllocHGlobal($needed); try { if(-not [KelpieToken]::GetTokenInformation($token,25,$buffer,$needed,[ref]$needed)){$tokenError='GetTokenInformation:'+[Runtime.InteropServices.Marshal]::GetLastWin32Error()} else {$sid=[Runtime.InteropServices.Marshal]::ReadIntPtr($buffer); $count=[Runtime.InteropServices.Marshal]::ReadByte([KelpieToken]::GetSidSubAuthorityCount($sid)); if($count -lt 1){$tokenError='MandatoryLabelSid has no authority'} else {$rid=[Runtime.InteropServices.Marshal]::ReadInt32([KelpieToken]::GetSidSubAuthority($sid,[uint32]($count-1)))}} } finally {[Runtime.InteropServices.Marshal]::FreeHGlobal($buffer)} }; if($token -ne [IntPtr]::Zero){[KelpieToken]::CloseHandle($token)|Out-Null}; if($process -ne [IntPtr]::Zero){[KelpieToken]::CloseHandle($process)|Out-Null}; $records += [pscustomobject]@{pid=[int]$p.ProcessId;integrityRid=$rid;error=$tokenError} }",
    "$records | ConvertTo-Json -Compress",
  ].join("\n");
  const probe = await runCommand("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", script], { timeoutMs });
  if (probe.code !== 0) throw new Error(`Renderer sandbox probe failed: ${probe.stderr || probe.stdout}`);
  let records;
  try { records = JSON.parse(probe.stdout.trim() || "[]"); } catch { throw new Error(`Renderer sandbox probe returned invalid JSON: ${probe.stdout}`); }
  const values = Array.isArray(records) ? records : [records];
  if (values.length === 0) throw new Error("CEF did not create an owned renderer process");
  if (values.some(record => !Number.isInteger(record.integrityRid))) {
    throw new Error(`Could not read renderer integrity token: ${JSON.stringify(values)}`);
  }
  if (values.some(record => record.integrityRid >= 0x2000)) {
    throw new Error(`An owned CEF renderer is not sandboxed below medium integrity: ${JSON.stringify(values)}`);
  }
}

export async function removeIfPresent(path) {
  await rm(path, { force: true });
}
