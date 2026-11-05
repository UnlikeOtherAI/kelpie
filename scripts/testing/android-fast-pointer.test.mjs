import { strict as assert } from 'node:assert';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { runAndroidFastPointer } from './android-fast-pointer.mjs';

for (const [name, durationMs, capture] of [
  ['omitted with capture', undefined, true],
  ['500 ms control', 500, true],
  ['omitted without capture', undefined, false],
]) {
  test(name + ' reaches the pre-play gate with the exact request', async () => {
    const folder = await mkdtemp(join(tmpdir(), 'kelpie-fast-pointer-'));
    const commands = [];
    try {
      await assert.rejects(runAndroidFastPointer({
        folder, tabId: 'owned-tab', durationMs, capture,
        command: async (label) => {
          commands.push(label);
          if (label === 'fast-navigate') return { success: true };
          if (label === 'fast-ready') return { ok: true, value: { ready: true } };
          throw Error('Unexpected command ' + label);
        },
        beforePlay: async () => {
          const request = JSON.parse(await readFile(join(folder, 'fast-script.json'), 'utf8'));
          assert.equal(Object.hasOwn(request.pointer, 'durationMs'), durationMs !== undefined);
          if (durationMs !== undefined) assert.equal(request.pointer.durationMs, durationMs);
          assert.equal(Object.hasOwn(request, 'capture'), capture);
          throw Error('TEST_GATE');
        },
      }), /TEST_GATE/);
      assert.deepEqual(commands, ['fast-navigate', 'fast-ready']);
    } finally {
      await rm(folder, { recursive: true, force: true });
    }
  });
}