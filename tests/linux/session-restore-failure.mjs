#!/usr/bin/env node
// Exercise the real desktop engine with an unavailable named store, then remove
// only the injected fault and verify that the unchanged session recovers.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdir, mkdtemp, readFile, unlink, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { control, waitFor } from '../windows/lib/http.mjs';
import { fileExists, waitForReadiness } from '../windows/lib/process.mjs';

const exe = resolve(process.argv[2]);
let requests = 0;
const server = createServer((_request, response) => {
  requests++;
  response.end('<title>Isolated restoration fixture</title>');
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const url = `http://127.0.0.1:${server.address().port}/`;
try {
  for (const isolatedFirst of [true, false]) {
    const profile = await mkdtemp(join(tmpdir(), 'kelpie-restore-failure-'));
    const cache = join(profile, 'cef-cache');
    await mkdir(cache);
    const fault = join(cache, 'partition-blocked');
    await writeFile(fault, 'A file prevents creation of the named profile directory.');
    const isolated = { id: 'tab-1', url, active: true, partition: 'blocked' };
    const ordinary = { id: 'tab-2', url, active: false };
    const tabs = isolatedFirst ? [isolated, ordinary] : [ordinary, isolated];
    const snapshot = JSON.stringify({ nextTabId: 3, tabs });
    const session = join(profile, 'session.json');
    const readinessFile = join(profile, 'readiness.json');
    await writeFile(session, snapshot);
    function launch() {
      return spawn(exe, ['--headless', '--profile-dir', profile, '--port', '0'], { stdio: 'ignore' });
    }
    let child = launch();
    const previousRequests = requests;
    try {
      await waitFor(() => child.exitCode !== null || child.signalCode !== null, 'failed store rejection', 20000);
      assert.equal(child.signalCode, null);
      assert.notEqual(child.exitCode, 0);
      assert.equal(requests, previousRequests, 'No restored page may load with an unresolved identity');
      assert.equal(await fileExists(readinessFile), false);
      assert.equal(await readFile(session, 'utf8'), snapshot, 'Failed startup must preserve the saved tabs');

      await unlink(fault);
      child = launch();
      const readiness = await waitForReadiness(readinessFile, 30000);
      const restored = (await control(readiness, 'get-tabs', {})).tabs;
      assert.equal(restored.length, 2);
      assert.equal(restored.find(tab => tab.id === isolated.id).partition, 'blocked');
      assert.equal(restored.find(tab => tab.id === ordinary.id).partition, undefined);
      await waitFor(() => requests > previousRequests, 'restored page load');
      await control(readiness, 'close-browser', {});
      await waitFor(() => child.exitCode !== null, 'recovered browser shutdown', 15000);
      assert.equal(child.exitCode, 0);
    } finally {
      if (child.exitCode === null && child.signalCode === null) child.kill('SIGTERM');
    }
  }
  console.log('PASS: unavailable first/later isolated stores fail closed, preserve the session and recover after the injected fault is removed');
} finally {
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
}
