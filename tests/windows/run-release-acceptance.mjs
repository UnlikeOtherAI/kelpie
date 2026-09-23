#!/usr/bin/env node
import assert from "node:assert/strict";
import { createServer } from "node:net";
import { mkdir, mkdtemp, rm } from "node:fs/promises";
import { dirname, isAbsolute, join, relative, resolve } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";

import { runLiveAcceptance, runNessieStdioClient } from "./lib/acceptance.mjs";
import { control, waitFor } from "./lib/http.mjs";
import { startFixtureServer } from "./lib/fixture.mjs";
import { holdNodeLoopbackPort, holdReusableLoopbackPort, listeningPids } from "./lib/ports.mjs";
import { assertSandboxedRenderer, delay, fileExists, runCommand, startBrowser, stopBrowser, waitForReadiness } from "./lib/process.mjs";
import { closeShellWindow, startupFailureText } from "./lib/window.mjs";

const DEFAULT_TIMEOUT_MS = 45_000;

function usage() {
  return `Usage: node tests/windows/run-release-acceptance.mjs --exe <kelpie.exe> [options]

Options:
  --profile-dir <absolute-empty-dir>  Isolated browser profile (default: owned Unicode temp directory)
  --readiness-file <absolute-path>    Readiness location (default: <profile>/readiness.json)
  --port <number>                     Requested loopback control port (default: an available temporary port)
  --cli <absolute-path>               Built Kelpie CLI entry script
  --nessie-root <path>                Built Nessie checkout for real @nessie/mcp-client validation
  --timeout-ms <number>               Startup timeout (default: ${DEFAULT_TIMEOUT_MS})
  --keep-artifacts                    Keep the owned profile after the run

The harness never kills processes by name. It requests authenticated graceful
shutdown, then treats forced termination of its exact owned PID tree as failure.`;
}

export function parseOptions(argv) {
  const value = { timeoutMs: DEFAULT_TIMEOUT_MS, keepArtifacts: false };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--keep-artifacts") {
      value.keepArtifacts = true;
      continue;
    }
    if (!argument.startsWith("--")) throw new Error(`Unexpected argument: ${argument}`);
    const key = argument.slice(2).replace(/-([a-z])/g, (_, letter) => letter.toUpperCase());
    const next = argv[index + 1];
    if (next === undefined || next.startsWith("--")) throw new Error(`${argument} requires a value`);
    value[key] = next;
    index += 1;
  }
  if (typeof value.exe !== "string" || !isAbsolute(value.exe)) throw new Error("--exe must be an absolute path");
  if (typeof value.cli !== "string" || !isAbsolute(value.cli)) throw new Error("--cli must be an absolute path");
  if (typeof value.nessieRoot !== "string" || !isAbsolute(value.nessieRoot)) throw new Error("--nessie-root must be an absolute path");
  if (value.profileDir !== undefined && (typeof value.profileDir !== "string" || !isAbsolute(value.profileDir))) {
    throw new Error("--profile-dir must be an absolute path");
  }
  if (value.readinessFile !== undefined && (typeof value.readinessFile !== "string" || !isAbsolute(value.readinessFile))) {
    throw new Error("--readiness-file must be an absolute path");
  }
  if (value.port !== undefined && (!/^\d+$/.test(value.port) || Number(value.port) < 1 || Number(value.port) > 65535)) {
    throw new Error("--port must be a TCP port between 1 and 65535");
  }
  if (!Number.isInteger(Number(value.timeoutMs)) || Number(value.timeoutMs) < 1_000) throw new Error("--timeout-ms must be at least 1000");
  return value;
}

async function reservePort() {
  const server = createServer();
  await new Promise((resolvePromise, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolvePromise);
  });
  const address = server.address();
  await new Promise((resolvePromise, reject) => server.close(error => error ? reject(error) : resolvePromise()));
  if (address === null || typeof address === "string") throw new Error("Could not reserve a local TCP port");
  return address.port;
}

async function createProfile(config) {
  if (config.profileDir === undefined) {
    return { path: await mkdtemp(join(tmpdir(), "kelpie-windows-ž-")), owned: true };
  }
  const path = resolve(config.profileDir);
  if (await fileExists(path)) throw new Error(`Refusing to use existing profile directory: ${path}`);
  await mkdir(path, { recursive: true });
  return { path, owned: true };
}

export function readinessPath(config, profilePath) {
  if (config.readinessFile === undefined) return join(profilePath, "readiness.json");
  const path = resolve(config.readinessFile);
  const pathWithinProfile = relative(profilePath, path);
  if (pathWithinProfile.length === 0 || pathWithinProfile === ".." || pathWithinProfile.startsWith(`..${path.includes("\\") ? "\\" : "/"}`) || isAbsolute(pathWithinProfile)) {
    throw new Error("--readiness-file must be inside the owned --profile-dir");
  }
  return path;
}

function browserArguments({ profile, readiness, port, fixtureUrl }) {
  const argumentsValue = [
    "--profile-dir", profile,
    "--readiness-file", readiness,
    "--port", String(port),
    "--width", "1280",
    "--height", "720",
  ];
  if (fixtureUrl !== undefined) argumentsValue.push("--url", fixtureUrl);
  return argumentsValue;
}

function assertReadiness(readiness) {
  assert.equal(readiness.version, 1, "readiness version must be 1");
  assert.equal(typeof readiness.launchId, "string", "readiness must have a launchId");
  assert.equal(typeof readiness.deviceId, "string", "readiness must have a deviceId");
  assert.equal(Number.isInteger(readiness.port), true, "readiness must report the actual bound port");
  assert.equal(readiness.controlMode, "loopback", "Windows control mode must be loopback");
  assert.equal(readiness.mcp?.http, true, "readiness must advertise HTTP MCP");
  assert.equal(readiness.mcp?.endpoint, "/mcp", "readiness must advertise /mcp");
  assert.equal(typeof readiness.token, "string", "readiness must contain a bearer capability");
  assert(readiness.token.length >= 32, "readiness capability is unexpectedly short");
}

async function launchAndRead(config, fixtureUrl, profile, readinessFile, port) {
  if (await fileExists(readinessFile)) throw new Error(`Refusing to replace existing readiness file: ${readinessFile}`);
  const browser = startBrowser(config.exe, browserArguments({ profile, readiness: readinessFile, port, fixtureUrl }));
  try {
    const readiness = await waitForReadiness(readinessFile, config.timeoutMs);
    assertReadiness(readiness);
    await waitFor(async () => {
      const health = await fetch(`http://127.0.0.1:${readiness.port}/health`, { signal: AbortSignal.timeout(2_000) });
      return health.ok;
    }, "browser health endpoint", config.timeoutMs);
    return { browser, readiness };
  } catch (error) {
    await stopBrowser(browser);
    const logs = browser.logs();
    throw new Error(`Browser failed before readiness: ${error instanceof Error ? error.message : String(error)}\n` +
      `stdout:\n${logs.stdout}\nstderr:\n${logs.stderr}`);
  }
}

async function verifyProfileLock(config, fixtureUrl, profile, primaryReadiness, port) {
  const secondaryReadiness = join(profile, "conflict-readiness.json");
  const contender = startBrowser(config.exe, browserArguments({ profile, readiness: secondaryReadiness, port: await reservePort(), fixtureUrl }));
  try {
    const outcome = await Promise.race([
      contender.exited,
      delay(8_000).then(() => null),
    ]);
    assert.notEqual(outcome, null, "second launch against an owned profile must fail promptly");
    assert.equal(await fileExists(secondaryReadiness), false, "profile-conflicted process must not publish readiness");
    assert.equal(await fileExists(primaryReadiness), true, "profile-conflicted process must not remove the owner readiness file");
  } finally {
    await stopBrowser(contender);
  }
}

/**
 * A launch on a port another process already listens on must stop at the
 * local control listener stage: it never shares the port, never publishes
 * readiness, and its window names that stage until a person closes it.
 */
async function verifyOccupiedPort(config, fixtureUrl, holder) {
  const profile = await mkdtemp(join(tmpdir(), "kelpie-windows-port-conflict-"));
  const readiness = join(profile, "readiness.json");
  const contender = startBrowser(config.exe, browserArguments({ profile, readiness, port: holder.port, fixtureUrl }));
  try {
    const deadline = Date.now() + config.timeoutMs;
    let failure;
    while (failure === undefined) {
      assert.equal(await fileExists(readiness), false, `launch against ${holder.description} published readiness, so it shares the port`);
      assert.equal(contender.child.exitCode, null, `launch against ${holder.description} exited instead of reporting its failure`);
      assert(Date.now() < deadline, `launch against ${holder.description} never reported a startup failure`);
      failure = await startupFailureText(contender.child.pid);
      if (failure === undefined) await delay(250);
    }
    assert.match(failure, /^Browser startup failed during local control listener: /,
      `launch against ${holder.description} must fail at the local control listener`);
    assert.equal(await fileExists(readiness), false, `launch against ${holder.description} must not publish readiness`);
    const listeners = await listeningPids(holder.port);
    assert.equal(listeners.includes(contender.child.pid), false, `launch against ${holder.description} must not share its port`);
    assert.equal(listeners.includes(holder.pid), true,
      `${holder.description} (PID ${holder.pid}) must keep port ${holder.port}; listening PIDs: ${JSON.stringify(listeners)}`);
    await holder.stillServes?.();
    await closeShellWindow(contender.child.pid);
    const outcome = await Promise.race([contender.exited, delay(config.timeoutMs).then(() => null)]);
    assert.notEqual(outcome, null, "a window that failed startup must close when asked");
    assert.equal(outcome.code, 1, "a failed startup must exit with a failure status");
  } finally {
    await stopBrowser(contender);
    // Chromium's helper processes can hold the contender's log for a moment
    // after the browser process itself has exited.
    await rm(profile, { recursive: true, force: true, maxRetries: 20, retryDelay: 250 });
  }
}

async function verifyOccupiedPorts(config, fixtureUrl, current, readinessFile) {
  // The SO_REUSEADDR holder goes first: it is the one a shareable listener
  // would bind beside, so it is the check that names that regression.
  for (const hold of [holdReusableLoopbackPort, holdNodeLoopbackPort]) {
    const holder = await hold();
    try {
      await verifyOccupiedPort(config, fixtureUrl, holder);
    } finally {
      await holder.close();
    }
  }
  await verifyOccupiedPort(config, fixtureUrl, {
    description: "the running kelpie.exe",
    port: current.readiness.port,
    pid: current.browser.child.pid,
    stillServes: async () => {
      assert.equal(await fileExists(readinessFile), true, "the running browser must keep its readiness file");
      await control(current.readiness, "get-current-url", {});
    },
  });
}

async function verifyRestoration(readiness, session) {
  await waitFor(async () => {
    const response = await control(readiness, "get-tabs", {});
    const value = response.result ?? response.value ?? response;
    if (!Array.isArray(value.tabs)) return false;
    const retained = value.tabs.find(tab => tab.id === session.retained.id);
    const other = value.tabs.find(tab => tab.id === session.other.id);
    return retained?.url === session.retained.url && retained.active === true &&
      other?.url === session.other.url &&
      !value.tabs.some(tab => tab.id === session.closed.id || tab.url === session.closed.url);
  }, "restored tab session", 15_000);
}

async function stopKnownBrowser(current, timeoutMs) {
  await stopBrowser(current.browser, {
    timeoutMs,
    gracefulClose: async () => control(current.readiness, "close-browser", {}),
  });
  await waitFor(async () => !(await fileExists(current.readinessFile)), "authenticated readiness cleanup", timeoutMs);
}

function parseCliResult(command, description) {
  if (command.code !== 0) {
    throw new Error(`${description} failed (${command.code}): ${command.stderr || command.stdout}`);
  }
  try {
    return JSON.parse(command.stdout.trim());
  } catch {
    throw new Error(`${description} did not emit one JSON result: ${command.stdout || command.stderr}`);
  }
}

function assertNoCapabilityLeak(command, readiness, description) {
  assert.equal(`${command.stdout}\n${command.stderr}`.includes(readiness.token), false,
    `${description} must not print the readiness capability`);
}

async function verifyCliAndStdio(config, fixtureUrl, port) {
  const profile = await mkdtemp(join(tmpdir(), "kelpie-windows-cli-profile-"));
  const cliHome = await mkdtemp(join(tmpdir(), "kelpie-windows-cli-home-"));
  const readinessFile = join(profile, "readiness.json");
  const alias = `acceptance-${process.pid}`;
  const environment = { KELPIE_HOME: cliHome };
  let launched = false;
  try {
    const registered = await runCommand(process.execPath, [config.cli, "browser", "register", alias,
      "--platform", "windows", "--app-path", config.exe, "--profile-dir", profile], { env: environment });
    assert.equal(parseCliResult(registered, "CLI browser register").success, true, "CLI must register an isolated Windows alias");

    // Without --port the CLI launches on 8420, which a developer's own Kelpie
    // usually holds; the run then fails at the listener instead of testing the CLI.
    const launchedCommand = await runCommand(process.execPath, [config.cli, "browser", "launch", alias, "--port", String(port)],
      { env: environment, timeoutMs: config.timeoutMs });
    const launch = parseCliResult(launchedCommand, "CLI browser launch");
    assert.equal(launch.success, true, "CLI must launch the registered Windows browser");
    const readiness = await waitForReadiness(readinessFile, config.timeoutMs);
    assertReadiness(readiness);
    assertNoCapabilityLeak(launchedCommand, readiness, "CLI browser launch");
    launched = true;

    const navigated = await runCommand(process.execPath, [config.cli, "--browser", alias, "navigate", fixtureUrl], { env: environment });
    assert.equal(parseCliResult(navigated, "CLI browser target").success, true, "CLI target command must use the saved readiness capability");
    assertNoCapabilityLeak(navigated, readiness, "CLI browser target");
    await waitFor(async () => (await control(readiness, "get-current-url", {})).url === fixtureUrl,
      "CLI-targeted navigation");

    await runNessieStdioClient({ cliPath: config.cli, cliHome, alias, fixtureUrl, nessieRoot: config.nessieRoot });

    const stopped = await runCommand(process.execPath, [config.cli, "browser", "stop", alias], { env: environment, timeoutMs: config.timeoutMs });
    assert.equal(parseCliResult(stopped, "CLI browser stop").success, true, "CLI must stop only its own launched browser");
    assertNoCapabilityLeak(stopped, readiness, "CLI browser stop");
    launched = false;
    await waitFor(async () => !(await fileExists(readinessFile)), "CLI graceful readiness cleanup", config.timeoutMs);

    const removed = await runCommand(process.execPath, [config.cli, "browser", "remove", alias], { env: environment });
    assert.equal(parseCliResult(removed, "CLI browser remove").success, true, "CLI must remove the isolated alias");
  } finally {
    if (launched) {
      await runCommand(process.execPath, [config.cli, "browser", "stop", alias], { env: environment, timeoutMs: config.timeoutMs }).catch(() => undefined);
    }
    await rm(profile, { recursive: true, force: true });
    await rm(cliHome, { recursive: true, force: true });
  }
}

async function main() {
  const config = parseOptions(process.argv.slice(2));
  const profile = await createProfile(config);
  const readiness = readinessPath(config, profile.path);
  const fixture = await startFixtureServer();
  let current;
  try {
    const port = config.port === undefined ? await reservePort() : Number(config.port);
    current = await launchAndRead(config, fixture.baseUrl, profile.path, readiness, port);
    await verifyProfileLock(config, fixture.baseUrl, profile.path, readiness, current.readiness.port);
    await verifyOccupiedPorts(config, fixture.baseUrl, current, readiness);
    const session = await runLiveAcceptance(current.readiness, fixture.baseUrl, config.nessieRoot);
    await assertSandboxedRenderer(current.browser, config.timeoutMs);
    const originalDeviceId = current.readiness.deviceId;
    await stopKnownBrowser({ ...current, readinessFile: readiness }, config.timeoutMs);
    current = undefined;
    await verifyCliAndStdio(config, fixture.baseUrl, port);
    current = await launchAndRead(config, undefined, profile.path, readiness, port);
    assert.equal(current.readiness.deviceId, originalDeviceId, "device identity must survive clean restart");
    await verifyRestoration(current.readiness, session);
    console.log(JSON.stringify({ success: true, profile: profile.path, port: current.readiness.port, deviceId: current.readiness.deviceId }));
  } finally {
    if (current !== undefined) await stopKnownBrowser({ ...current, readinessFile: readiness }, config.timeoutMs);
    await fixture.close();
    if (profile.owned && !config.keepArtifacts) await rm(profile.path, { recursive: true, force: true });
  }
}

if (process.argv[1] !== undefined && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(error => {
    console.error(`Windows release acceptance failed: ${error instanceof Error ? error.stack ?? error.message : String(error)}`);
    console.error(usage());
    process.exitCode = 1;
  });
}
