// Snapshot the owned candidate's mapped GIF/compositor libraries during a native run.
import assert from "node:assert/strict";
import { readFile, readlink, realpath, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { dirname, join, resolve } from "node:path";

const digest = bytes => createHash("sha256").update(bytes).digest("hex");
const fileHash = async file => digest(await readFile(file));
export async function writeGifRuntimeEvidence(pid, executable, source, output) {
  assert.ok(Number.isInteger(pid) && pid > 0);
  assert.match(source, /^[a-f0-9]{40}$/);
  const actual = await realpath(await readlink("/proc/" + pid + "/exe"));
  const expected = await realpath(executable);
  assert.equal(actual, expected, "Observed process is not the candidate");
  // Inspect names only; never write environment values into the evidence.
  const environment = await readFile("/proc/" + pid + "/environ", "utf8");
  const names = environment.split("\0").filter(Boolean).map(entry=>entry.split("=",1)[0]);
  for (const name of ["LD_PRELOAD","LD_AUDIT","LD_LIBRARY_PATH"])
    assert.ok(!names.includes(name), "Candidate has a loader override: " + name);
  const maps = await readFile("/proc/" + pid + "/maps", "utf8");
  await writeFile(output + ".maps.txt", maps, {flag:"wx"});
  const paths = new Set();
  for (const line of maps.split("\n")) {
    const path = line.match(/\s(\/[^\n]+)$/)?.[1];
    if (path && /\/(?:libgif|libcairo|libpixman|libz\.so)/.test(path)) {
      assert.ok(!path.endsWith(" (deleted)"));
      paths.add(await realpath(path));
    }
  }
  assert.ok([...paths].some(path=>/\/libgif/.test(path)));
  assert.ok([...paths].some(path=>/\/libcairo/.test(path)));
  assert.ok([...paths].some(path=>/\/libpixman/.test(path)));
  const dependencies = [];
  for (const path of [...paths].sort()) dependencies.push({path,sha256:await fileHash(path)});
  const objects = join(dirname(resolve(executable)),"CMakeFiles/kelpie_linux_script_media.dir/src");
  const mediaObjectSHA256 = {
    compositor:await fileHash(join(objects,"script_frame_compositor.cpp.o")),
    gif:await fileHash(join(objects,"script_media_gif.cpp.o")),
    encoder:await fileHash(join(objects,"script_media_encoder.cpp.o")),
  };
  await writeFile(output, JSON.stringify({version:1,source,pid,binaryPath:actual,
    binarySHA256:await fileHash(actual),mapsSHA256:digest(maps),loaderOverridesAbsent:true,mediaObjectSHA256,
    mediaArchiveSHA256:await fileHash(join(dirname(resolve(executable)),"libkelpie_linux_script_media.a")),
    candidateLinkMapSHA256:await fileHash(join(dirname(resolve(executable)),"kelpie-linux-link.map")),
    dependencies},null,2), {flag:"wx"});
}
