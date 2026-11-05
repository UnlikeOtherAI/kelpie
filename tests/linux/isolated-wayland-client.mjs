import assert from "node:assert/strict";
import { readFile, realpath, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { readNativeIdentity } from "./native-lifecycle.mjs";
const [binary, cli, output] = process.argv.slice(2);
assert.equal(process.platform, "linux");
assert.equal(await realpath("/proc/" + process.ppid + "/exe"), await realpath("/usr/bin/weston"));
const identity = await readNativeIdentity(process.ppid);
assert.ok(identity);
identity.sha256 = createHash("sha256").update(await readFile("/proc/" + identity.pid + "/exe")).digest("hex");
assert.ok(process.env.WAYLAND_DISPLAY && process.env.DBUS_SESSION_BUS_ADDRESS);
assert.ok(!process.env.DBUS_SESSION_BUS_ADDRESS.includes("/run/user/1000/bus"));
const env = { ...process.env, GDK_BACKEND: "wayland", KELPIE_ISOLATED_WAYLAND: "1",
  KELPIE_PRIVATE_WESTON_IDENTITY: JSON.stringify(identity) };
await writeFile(join(output, "private-compositor.json"), JSON.stringify({ identity,
  display: env.DISPLAY ?? null, waylandSocket: env.WAYLAND_DISPLAY, privateDBus: true }, null, 2));
const driver = fileURLToPath(new URL("./run-native-alias-acceptance.mjs", import.meta.url));
let outcome;
try {
  await promisify(execFile)(process.execPath, [driver, binary, cli, join(output, "windowed"), "windowed"],
    { env, timeout: 150000, maxBuffer: 2097152 });
  outcome = { success: true };
} catch (error) {
  outcome = { success: false, message: error.message.slice(0, 16384) };
  throw error;
} finally {
  await writeFile(join(output, "client-result.json"), JSON.stringify(outcome, null, 2));
}
