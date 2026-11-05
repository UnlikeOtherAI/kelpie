import { strict as assert } from 'node:assert';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { summarize } from './android-native-report.mjs';

test('adb success cannot hide JUnit failure or missing tablet, and exports have hashes', () => {
  const root = mkdtempSync(join(tmpdir(), 'android-native-report-'));
  try {
    writeFileSync(join(root, 'source-revision.txt'), 'frozen-revision\n');
    const phone = join(root, 'phone');
    mkdirSync(join(phone, 'script-acceptance'), { recursive: true });
    writeFileSync(join(phone, 'instrumentation.log'), 'FAILURES!!!\nTests run: 1, Failures: 1\n');
    writeFileSync(join(phone, 'instrumentation-exit.txt'), '0\n');
    writeFileSync(join(phone, 'script-acceptance', 'frame.png'), 'fixture');
    const failed = summarize(root);
    assert.equal(failed.profiles[0].passed, false);
    assert.equal(failed.profiles[1].passed, false);
    assert.match(failed.profiles[0].exports[0].sha256, /^[a-f0-9]{64}$/);
    writeFileSync(join(phone, 'instrumentation.log'), 'OK (19 tests)\n');
    writeFileSync(join(phone, 'cli-report.json'), JSON.stringify({ success: true }));
    writeFileSync(join(phone, 'cli-exit.txt'), '0');
    writeFileSync(join(phone, 'cli-instrumentation.log'), 'OK (1 test)');
    assert.equal(summarize(root).profiles[0].passed, true);
    writeFileSync(join(phone, 'instrumentation-exit.txt'), '124\n');
    assert.equal(summarize(root).profiles[0].passed, false);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});