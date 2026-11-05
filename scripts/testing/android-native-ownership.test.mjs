import { strict as assert } from 'node:assert';
import { spawnSync } from 'node:child_process';
import { createServer } from 'node:net';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { availablePort, hostedRunner, ownsProcess } from './android-native-ownership.mjs';

test('hosted guard rejects local and self-hosted execution before device operations', () => {
  assert.equal(hostedRunner({}), false);
  assert.equal(hostedRunner({ GITHUB_ACTIONS: 'true', RUNNER_ENVIRONMENT: 'self-hosted', RUNNER_OS: 'Linux' }), false);
  const environment = { GITHUB_ACTIONS: 'true', RUNNER_ENVIRONMENT: 'github-hosted', RUNNER_OS: 'Linux' };
  assert.equal(hostedRunner(environment), true);
  const result = spawnSync(process.execPath, [fileURLToPath(new URL('./android-native-ownership.mjs', import.meta.url)), 'hosted'],
    { env: { ...process.env, ...environment, RUNNER_ENVIRONMENT: 'self-hosted' }, encoding: 'utf8' });
  assert.equal(result.status, 2);
  assert.match(result.stderr, /HOSTED_LINUX_RUNNER_REQUIRED/);
});
test('cleanup requires exact spawned process generation, SDK binary, AVD and port', () => {
  const expected = { started: '1234', sdk: resolve('sdk'), avd: 'task-avd', port: 5584 };
  const actual = { started: '1234', executable: resolve('sdk/emulator/qemu/engine'),
    args: ['engine', '-avd', 'task-avd', '-port', '5584'] };
  assert.equal(ownsProcess(actual, expected), true);
  for (const changed of [
    { started: '4321' }, { executable: resolve('sdk/emulator-other/engine') },
    { args: ['engine', '-avd', 'other-owner', '-port', '5584'] },
    { args: ['engine', '-avd', 'task-avd', '-port', '5586'] },
    { args: ['engine', 'task-avd', '5584'] },
  ]) assert.equal(ownsProcess({ ...actual, ...changed }, expected), false);
  assert.equal(ownsProcess(actual, { ...expected, started: '' }), false);
});
test('occupied proposed port is refused without terminating or changing its owner', async () => {
  const server = createServer();
  await new Promise(resolveListen => server.listen(0, '127.0.0.1', resolveListen));
  const port = server.address().port;
  try {
    assert.equal(await availablePort(port), false);
    assert.equal(server.listening, true);
  } finally {
    await new Promise(resolveClose => server.close(resolveClose));
  }
  assert.equal(await availablePort(port), true);
});