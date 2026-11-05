import { strict as assert } from 'node:assert';
import { createHash } from 'node:crypto';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { startG08Fixture, g08Workflow, mapG08Scene } from '../../tests/capture/g08-fixture.mjs';

const execute = promisify(execFile);

/** Acquire a real default or explicit-control run; analysis must use actual pixels and PTS. */
export async function runAndroidFastPointer({ command, folder, tabId, durationMs, capture, beforePlay = async () => {} }) {
  assert.ok(durationMs === undefined || durationMs === 500);
  assert.equal(typeof capture, 'boolean');
  await execute('ffprobe', ['-version'], { timeout: 10000, maxBuffer: 1048576 });
  const fixture = await startG08Fixture();
  try {
    const deviceUrl = fixture.url.replace('127.0.0.1', '10.0.2.2');
    assert.equal((await command('fast-navigate', ['navigate', deviceUrl])).success, true);
    let ready = false;
    const deadline = Date.now() + 60000;
    while (!ready && Date.now() < deadline) {
      const state = await command('fast-ready', ['browser-control', JSON.stringify({
        version: 1, method: 'tab.ready', tabId, params: { selector: '#finish', state: 'complete' },
      })]);
      ready = state.ok === true && state.value.ready === true;
      if (!ready) await new Promise(resolveReady => setTimeout(resolveReady, 50));
    }
    assert.equal(ready, true);
    const script = g08Workflow(tabId, 'c');
    if (durationMs === undefined) delete script.pointer.durationMs;
    else script.pointer.durationMs = durationMs;
    if (!capture) delete script.capture;
    assert.equal(Object.hasOwn(script.pointer, 'durationMs'), durationMs !== undefined);
    const scriptFile = join(folder, 'fast-script.json');
    await writeFile(scriptFile, JSON.stringify(script, null, 2));
    await beforePlay();
    const run = await command('fast-run', ['script', 'run', scriptFile]);
    assert.equal(run.success, true);
    let facts;
    const eventDeadline = Date.now() + 5000;
    do {
      const response = await fetch(fixture.url.replace('/g08', '/events'));
      assert.equal(response.status, 200);
      facts = await response.json();
      if (facts.events.length < 4) await new Promise(resolveEvents => setTimeout(resolveEvents, 50));
    } while (facts.events.length < 4 && Date.now() < eventDeadline);
    assert.equal(facts.dropped, 0);
    const scene = mapG08Scene(facts.events);
    const artifacts = [];
    if (capture) {
      for (const mime of ['image/gif', 'video/mp4']) {
        const item = run.artifacts.find(entry => entry.mimeType === mime);
        assert.ok(item);
        const ext = mime === 'image/gif' ? 'gif' : 'mp4';
        const file = join(folder, 'fast.' + ext);
        await command('fast-' + ext + '-download', ['script', 'download', run.runId, item.id, file]);
        const bytes = await readFile(file);
        assert.equal(bytes.length, item.byteLength);
        assert.equal(createHash('sha256').update(bytes).digest('hex'), item.sha256);
        const probe = await execute('ffprobe', ['-v', 'error', '-select_streams', 'v:0',
          '-show_frames', '-show_entries', 'frame=best_effort_timestamp_time:stream=width,height',
          '-of', 'json', file], { timeout: 30000, maxBuffer: 1048576 });
        artifacts.push({ ...item, file, timestamps: JSON.parse(probe.stdout).frames.map(frame => Number(frame.best_effort_timestamp_time)) });
      }
    } else {
      assert.ok(!run.artifacts?.length, 'Capture-disabled run returned artifacts');
    }
    const receipt = { fixtureUrl: fixture.url, durationMs: durationMs ?? null, durationOmitted: durationMs === undefined, capture, scene, artifacts };
    await writeFile(join(folder, 'fast-receipt.json'), JSON.stringify(receipt, null, 2));
    return receipt;
  } finally {
    await fixture.close();
  }
}