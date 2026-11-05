import { strict as assert } from 'node:assert';
import { createHash } from 'node:crypto';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { startG08Fixture, g08Workflow, mapG08Scene } from '../../tests/capture/g08-fixture.mjs';

const execute = promisify(execFile);

// Uses the same paired CLI and app-owned test bridge as the other hosted flow.
export async function runG08({ command, folder, tabId, profile, revision, binarySHA256 }) {
  // Fail before navigation or playback when required media tools are absent.
  await execute("ffprobe", ["-version"], { timeout: 10000, maxBuffer: 1048576 });
  await execute("ffmpeg", ["-version"], { timeout: 10000, maxBuffer: 1048576 });
  const cases = [];
  let eventsDropped = 0;
  for (const curve of ['c', 's']) {
    const fixture = await startG08Fixture();
    try {
      const deviceUrl = fixture.url.replace('127.0.0.1', '10.0.2.2');
      assert.equal((await command('g08-' + curve + '-navigate', ['navigate', deviceUrl])).success, true);
      const deadline = Date.now() + 60000;
      let ready = false;
      while (!ready && Date.now() < deadline) {
        const state = await command('g08-' + curve + '-ready', ['browser-control', JSON.stringify({
          version: 1, method: 'tab.ready', tabId, params: { selector: '#finish', state: 'complete' },
        })]);
        ready = state.ok === true && state.value.ready === true;
        if (!ready) await new Promise(resolveReady => setTimeout(resolveReady, 50));
      }
      assert.equal(ready, true, 'G08 document must be ready');
      const scriptFile = join(folder, 'g08-' + curve + '-script.json');
      await writeFile(scriptFile, JSON.stringify(g08Workflow(tabId, curve)));
      const run = await command('g08-' + curve + '-run', ['script', 'run', scriptFile]);
      assert.equal(run.success, true);
      let facts;
      const eventDeadline = Date.now() + 5000;
      do {
        const eventsResponse = await fetch(fixture.url.replace('/g08', '/events'));
        assert.equal(eventsResponse.status, 200);
        facts = await eventsResponse.json();
        if (facts.events.length < 4) await new Promise(resolveEvents => setTimeout(resolveEvents, 50));
      } while (facts.events.length < 4 && Date.now() < eventDeadline);
      await writeFile(join(folder, 'g08-' + curve + '-events.json'), JSON.stringify(facts, null, 2));
      eventsDropped += facts.dropped;
      assert.equal(facts.events.length, 4);
      const artifacts = [];
      for (const mime of ['image/gif', 'video/mp4']) {
        const item = run.artifacts.find(entry => entry.mimeType === mime);
        assert.ok(item, 'Missing ' + mime);
        const file = join(folder, 'script-acceptance', 'g08-' + curve + (mime === 'image/gif' ? '.gif' : '.mp4'));
        await command('g08-' + curve + '-' + (mime === 'image/gif' ? 'gif' : 'mp4') + '-download',
          ['script', 'download', run.runId, item.id, file]);
        const bytes = await readFile(file);
        assert.equal(bytes.length, item.byteLength);
        assert.equal(createHash('sha256').update(bytes).digest('hex'), item.sha256);
        const probe = await execute('ffprobe', ['-v', 'error', '-select_streams', 'v:0',
          '-show_frames', '-show_entries', 'frame=best_effort_timestamp_time:stream=width,height',
          '-of', 'json', file], { timeout: 30000, maxBuffer: 1048576 });
        const metadata = JSON.parse(probe.stdout);
        artifacts.push({ ...item, file, timestamps: metadata.frames.map(frame => Number(frame.best_effort_timestamp_time)) });
      }
      cases.push({ curve, scene: mapG08Scene(facts.events), artifacts });
    } finally {
      await fixture.close();
    }
  }
  const input = { source: revision, binarySHA256, runtime: 'android-' + profile + '-chromium', eventsDropped, cases };
  const inputFile = join(folder, 'g08-input.json');
  await writeFile(inputFile, JSON.stringify(input, null, 2));
  try {
    const verify = await execute(process.execPath, ['tests/capture/g08-verify.mjs', inputFile, join(folder, 'g08-output.json')],
      { timeout: 300000, maxBuffer: 1048576 });
    await writeFile(join(folder, 'g08-verifier.log'), verify.stdout + verify.stderr);
  } catch (error) {
    await writeFile(join(folder, 'g08-verifier.log'), String(error.stdout ?? '') + String(error.stderr ?? '') + String(error.message));
    throw error;
  }
}
