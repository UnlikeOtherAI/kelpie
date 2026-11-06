import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { runSelectedG08 } from "./osr-g08-selected.mjs";

test("selected OSR keeps eight independent format outcomes and validated media", async () => {
  const root = await mkdtemp(join(tmpdir(), "kelpie-osr-g08-"));
  const oldSource = process.env.KELPIE_CAPTURE_SOURCE, oldTest = process.env.KELPIE_TEST_REVISION;
  process.env.KELPIE_CAPTURE_SOURCE = "a".repeat(40); process.env.KELPIE_TEST_REVISION = "b".repeat(40);
  try {
    const binary = join(root, "binary"); await writeFile(binary, "binary");
    const invoke = async (_node, args) => {
      if (args[0] === "tests/linux/run-g08.mjs") {
        const dir = args[3]; await mkdir(dir);
        const cases = [];
        for (const curve of ["c", "s"]) {
          const artifacts = [];
          for (const mimeType of ["image/gif", "video/mp4"]) {
            const bytes = Buffer.from(curve + mimeType), file = join(dir, curve + (mimeType === "image/gif" ? ".gif" : ".mp4"));
            await writeFile(file, bytes);
            artifacts.push({ mimeType, file, width: 640, height: 450, timestamps: [0, 0.05], byteLength: bytes.length, sha256: createHash("sha256").update(bytes).digest("hex") });
          }
          const event = { timeMs: 1, center: { x: 2, y: 3 }, viewport: { width: 640, height: 450 }, trusted: true, documentId: "same" };
          cases.push({ curve, artifacts, scene: { warmup: event, calibration: event, start: event, finish: event } });
        }
        await writeFile(join(dir, "input.json"), JSON.stringify({ source: "a".repeat(40), testSource: "b".repeat(40), binarySHA256: createHash("sha256").update("binary").digest("hex"), runtime: "linux-osr-cef", profile: args[5], eventsDropped: 0, cases }));
      } else {
        const input = JSON.parse(await readFile(args[1], "utf8"));
        const results = input.cases.flatMap(item => item.artifacts.map(artifact => ({
          curve: item.curve, mimeType: artifact.mimeType, sha256: artifact.sha256, droppedFrames: 3,
          passed: artifact.mimeType === "image/gif", error: "FAST_INSUFFICIENT_SAMPLES private-canary",
        })));
        await writeFile(args[2], JSON.stringify({ results }));
      }
    };
    const result = await runSelectedG08({ readiness: "private", binary, output: root, signal: new AbortController().signal, invoke });
    assert.equal(result.results.length, 8);
    assert.equal(result.results.filter(row => row.status === "passed").length, 4);
    assert.equal(result.results.filter(row => row.status === "insufficient").length, 4);
    assert.ok(result.results.every(row => row.droppedFrames === 3));
    assert.doesNotMatch(JSON.stringify(result), /private-canary|private/);
    assert.equal((await readFile(join(root, "dense", "published", "c.gif"))).toString(), "cimage/gif");
  } finally {
    if (oldSource === undefined) delete process.env.KELPIE_CAPTURE_SOURCE; else process.env.KELPIE_CAPTURE_SOURCE = oldSource;
    if (oldTest === undefined) delete process.env.KELPIE_TEST_REVISION; else process.env.KELPIE_TEST_REVISION = oldTest;
    await rm(root, { recursive: true, force: true });
  }
});

test("hosted selection is opt-in, Fedora scoped and retains cleanup gates", async () => {
  const lint = await readFile(".github/workflows/lint.yml", "utf8");
  const workflow = await readFile(".github/workflows/linux-native.yml", "utf8");
  const smoke = await readFile("scripts/ci/linux-installed-smoke.sh", "utf8");
  assert.match(lint, /linux_native_osr_g08:[\s\S]*?default: false/);
  assert.match(workflow, /!inputs\.osr_g08 \|\| matrix\.distro\.name == 'fedora-44'/);
  assert.match(workflow, /KELPIE_INSTALLED_OSR_G08=/);
  for (const name of ["Diagnose failed installed candidate namespaces", "Replay failed installed candidate without tracing"]) {
    const section = workflow.split("      - name: " + name)[1].split("\n      - ")[0];
    assert.match(section, /failure\(\) && !inputs\.osr_g08/);
  }
  assert.match(workflow, /no-new-privileges=true/);
  assert.match(workflow, /seccomp=\$\{RUNNER_TEMP\}/);
  assert.match(smoke, /osr-g08-failed/);
  assert.match(smoke, /run-native-alias-acceptance\.mjs/);
  assert.match(smoke, /unshare --user --map-root-user/);
  assert.doesNotMatch(smoke, /--no-sandbox/);
});

test("missing or untrusted document facts publish no partial media", async () => {
  for (const invalid of ["missing-document", "untrusted"]) {
    const root = await mkdtemp(join(tmpdir(), "kelpie-osr-refusal-"));
    const oldSource = process.env.KELPIE_CAPTURE_SOURCE, oldTest = process.env.KELPIE_TEST_REVISION;
    process.env.KELPIE_CAPTURE_SOURCE = "a".repeat(40); process.env.KELPIE_TEST_REVISION = "b".repeat(40);
    try {
      const binary = join(root, "binary"); await writeFile(binary, "binary");
      const invoke = async (_node, args) => {
        if (args[0] === "tests/linux/run-g08.mjs") {
          const dir = args[3]; await mkdir(dir);
          const cases = [];
          for (const curve of ["c", "s"]) {
            const artifacts = [];
            for (const mimeType of ["image/gif", "video/mp4"]) {
              const bytes = Buffer.from(curve + mimeType), file = join(dir, curve + (mimeType === "image/gif" ? ".gif" : ".mp4"));
              await writeFile(file, bytes);
              artifacts.push({ mimeType, file, width: 640, height: 450, timestamps: [0, 0.05], byteLength: bytes.length,
                sha256: createHash("sha256").update(bytes).digest("hex") });
            }
            const event = { timeMs: 1, center: { x: 2, y: 3 }, viewport: { width: 640, height: 450 },
              trusted: invalid !== "untrusted", documentId: invalid === "missing-document" ? "" : "same" };
            cases.push({ curve, artifacts, scene: { warmup: event, calibration: event, start: event, finish: event } });
          }
          await writeFile(join(dir, "input.json"), JSON.stringify({ source: "a".repeat(40), testSource: "b".repeat(40),
            binarySHA256: createHash("sha256").update("binary").digest("hex"), runtime: "linux-osr-cef",
            profile: args[5], eventsDropped: 0, cases }));
        } else {
          const input = JSON.parse(await readFile(args[1], "utf8"));
          const results = input.cases.flatMap(item => item.artifacts.map(artifact => ({
            curve: item.curve, mimeType: artifact.mimeType, sha256: artifact.sha256, passed: true,
          })));
          await writeFile(args[2], JSON.stringify({ results }));
        }
      };
      const result = await runSelectedG08({ readiness: "private", binary, output: root, signal: new AbortController().signal, invoke });
      assert.ok(result.results.every(row => row.status === "failed"));
      for (const profile of ["dense", "default"]) await assert.rejects(readFile(join(root, profile, "published", "c.gif")));
    } finally {
      if (oldSource === undefined) delete process.env.KELPIE_CAPTURE_SOURCE; else process.env.KELPIE_CAPTURE_SOURCE = oldSource;
      if (oldTest === undefined) delete process.env.KELPIE_TEST_REVISION; else process.env.KELPIE_TEST_REVISION = oldTest;
      await rm(root, { recursive: true, force: true });
    }
  }
});
test("phase budget leaves time for startup and cleanup within wrapper", async () => {
  const text = await readFile("tests/linux/osr-g08-selected.mjs", "utf8");
  assert.match(text, /timeout: 120000/);
  assert.match(text, /timeout: 240000/);
  assert.ok(2 * (120 + 240) + 30 + 15 < 900);
});
