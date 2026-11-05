import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
const caller = await readFile(new URL("../../.github/workflows/lint.yml", import.meta.url), "utf8");
const callee = await readFile(new URL("../../.github/workflows/linux-native.yml", import.meta.url), "utf8");
test("Linux candidate is explicit dispatch-only and disabled by default", () => {
  assert.match(caller, /workflow_dispatch:\s*\n    inputs:\s*\n      linux_native_candidate:\s*\n        description:[^\n]+\n        type: boolean\s*\n        default: false/);
  assert.match(caller, /if: github\.event_name == 'workflow_dispatch' && inputs\.linux_native_candidate/);
  assert.match(caller, /  pull_request:\s*\n  push:\s*\n    branches:\s*\n      - main/);
});
test("same-ref reusable owns recipe and candidate cannot publish or inherit secrets", () => {
  const wrapper = caller.slice(caller.indexOf("  linux-native-candidate:"), caller.indexOf("  lint:"));
  assert.match(wrapper, /uses: \.\/\.github\/workflows\/linux-native\.yml/);
  assert.match(wrapper, /permissions:\s*\n      contents: read/);
  assert.match(wrapper, /force_build: true/); assert.match(wrapper, /release_tag: ''/);
  assert.match(wrapper, /artifact_prefix: linux-native-candidate/);
  assert.doesNotMatch(wrapper, /steps:|runs-on:|secrets:|write|run:|@/);
  assert.match(callee, /  workflow_call:/);
  assert.match(callee, /max-parallel: 1/);
});
test("default lint job stays a portable lint job", () => {
  const lint = caller.slice(caller.indexOf("  lint:"));
  assert.match(lint, /runs-on: ubuntu-latest/);
  assert.match(lint, /run: pnpm install --frozen-lockfile/);
  assert.match(lint, /run: pnpm lint/);
  assert.doesNotMatch(lint, /linux_native_candidate|force_build|docker|release_tag/);
});
