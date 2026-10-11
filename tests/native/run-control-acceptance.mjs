import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createServer } from "node:net";
import { startFixtureServer } from "../windows/lib/fixture.mjs";
import { control, rawRequest, bearerHeaders } from "../windows/lib/http.mjs";
import { runCanonicalAcceptance } from "../windows/lib/canonical-browser.mjs";
import { startBrowser, stopBrowser, waitForReadiness, runCommand } from "../windows/lib/process.mjs";

const executable = resolve(process.argv[2]);
const fallback = process.argv.includes("--fallback");
const profile = await mkdtemp(join(tmpdir(), "kelpie-native-contract-"));
const readinessPath = join(profile, "readiness.json");
const fixture = await startFixtureServer();
const reservation = createServer();
await new Promise(resolve => reservation.listen(0, "127.0.0.1", resolve));
const port = reservation.address().port;
await new Promise(resolve => reservation.close(resolve));
const browser = startBrowser(executable, ["--profile-dir", profile, "--readiness-file", readinessPath,
  "--port", String(port), "--url", fixture.baseUrl, ...(process.platform === "linux" ? ["--headless"] : [])]);
let readiness;
try {
  readiness = await waitForReadiness(readinessPath, 45000);
  assert.equal((await fetch(`http://127.0.0.1:${readiness.port}/health`)).status, 200);
  const sdk = await runCommand(process.execPath, [fileURLToPath(new URL("./mcp-client-journey.mjs", import.meta.url)), readinessPath]);
  assert.equal(sdk.code, 0, sdk.stderr);
  console.log(sdk.stdout.trim());
  if (fallback) {
    const response = await rawRequest({ port: readiness.port, path: "/v1/browser-control", headers: bearerHeaders(readiness.token),
      body: JSON.stringify({ version: 1, method: "tab.snapshot", tabId: "stub" }) });
    assert.equal(response.json.error.code, "UNSUPPORTED");
    assert.equal(response.json.error.mayHaveCompleted, false);
    console.log("Fallback refuses DOM capabilities before dispatch");
  } else await runCanonicalAcceptance(readiness, fixture.baseUrl);
} finally {
  try { await stopBrowser(browser, { gracefulClose: readiness ? () => control(readiness, "close-browser") : undefined }); }
  finally {
    await fixture.close();
    await rm(profile, { recursive: true, force: true, maxRetries: 20, retryDelay: 250 });
  }
}
