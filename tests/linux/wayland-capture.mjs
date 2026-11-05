import assert from "node:assert/strict";
import { readFile, realpath, lstat, readdir, mkdir, writeFile } from "node:fs/promises";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { createHash } from "node:crypto";
import { join, resolve } from "node:path";
import { readNativeIdentity } from "./native-lifecycle.mjs";
const execute = promisify(execFile);

/** Standard compositor capture, only inside the test-owned isolated Weston. */
export async function captureIsolatedWayland({ identity, binary, hash, output, env, signal }) {
  assert.equal(env.KELPIE_ISOLATED_WAYLAND, "1");
  const runtime = resolve(env.XDG_RUNTIME_DIR);
  assert.ok(runtime.startsWith("/tmp/kelpie-wayland-"));
  const directory = await lstat(runtime);
  assert.ok(directory.isDirectory() && !directory.isSymbolicLink());
  assert.equal(directory.uid, process.getuid()); assert.equal(directory.mode & 0o777, 0o700);
  assert.ok(env.DBUS_SESSION_BUS_ADDRESS && !env.DBUS_SESSION_BUS_ADDRESS.includes("/run/user/1000/bus"));
  const socket = await lstat(join(runtime, env.WAYLAND_DISPLAY));
  assert.ok(socket.isSocket()); assert.equal(socket.uid, process.getuid());
  const weston = JSON.parse(env.KELPIE_PRIVATE_WESTON_IDENTITY);
  const pin = async () => {
    for (const [expected, executable, digest] of [[identity, binary, hash], [weston, "/usr/bin/weston", weston.sha256]]) {
      const current = await readNativeIdentity(expected.pid);
      assert.equal(current?.startTicks, expected.startTicks);
      assert.equal(await realpath("/proc/" + expected.pid + "/exe"), await realpath(executable));
      assert.equal(createHash("sha256").update(await readFile("/proc/" + expected.pid + "/exe")).digest("hex"), digest);
    }
  };
  const scene = async () => {
    await pin();
    const { stdout } = await execute("/usr/bin/weston-debug", ["scene-graph"], { env, signal, timeout: 3000, maxBuffer: 262144 });
    const views = [...stdout.matchAll(/View \d+ \(role ([^,]+), PID (\d+), surface ID (\d+),/g)]
      .map(match => ({ role: match[1], pid: Number(match[2]), surface: Number(match[3]) }));
    assert.ok(views.length > 0 && views.length <= 32, "No bounded Weston surface inventory");
    assert.ok(views.some(view => view.pid === identity.pid), "Owned GTK surface absent");
    assert.ok(views.every(view => view.pid === 0 || view.pid === identity.pid), "Foreign compositor surface: capture refused");
    return { text: stdout, views };
  };
  const target = join(output, "isolated-wayland-recording"); await mkdir(target, { mode: 0o700 });
  const before = await scene();
  const capture = await execute("/usr/bin/weston-screenshooter", [], { cwd: target, env, signal, timeout: 5000, maxBuffer: 65536 });
  const after = await scene();
  assert.deepEqual(after.views, before.views, "Surface ownership changed during capture");
  await pin();
  const names = await readdir(target); assert.equal(names.length, 1);
  assert.ok(names[0].endsWith(".png"));
  const file = join(target, names[0]), stat = await lstat(file);
  assert.ok(stat.isFile() && !stat.isSymbolicLink() && stat.uid === process.getuid() && stat.size <= 16777216);
  const bytes = await readFile(file); assert.equal(bytes.subarray(0, 8).toString("hex"), "89504e470d0a1a0a");
  const report = { scope: "ISOLATED_WAYLAND", app: identity, compositor: weston, views: before.views,
    file, byteLength: bytes.length, sha256: createHash("sha256").update(bytes).digest("hex"),
    width: bytes.readUInt32BE(16), height: bytes.readUInt32BE(20), stdout: capture.stdout, stderr: capture.stderr };
  await writeFile(join(target, "scene-before.txt"), before.text);
  await writeFile(join(target, "scene-after.txt"), after.text);
  await writeFile(join(target, "receipt.json"), JSON.stringify(report, null, 2));
  return report;
}
