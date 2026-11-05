import { readFileSync, readlinkSync, realpathSync } from 'node:fs';
import { createServer } from 'node:net';
import { resolve, sep } from 'node:path';
import { pathToFileURL } from 'node:url';

export function hostedRunner(environment) {
  return environment.GITHUB_ACTIONS === 'true' &&
    environment.RUNNER_ENVIRONMENT === 'github-hosted' && environment.RUNNER_OS === 'Linux';
}
export function ownsProcess(actual, expected) {
  if (!expected.started || actual.started !== expected.started) return false;
  const emulatorRoot = resolve(expected.sdk, 'emulator') + sep;
  if (!actual.executable.startsWith(emulatorRoot)) return false;
  const option = name => actual.args[actual.args.indexOf(name) + 1];
  return actual.args.includes('-avd') && option('-avd') === expected.avd &&
    actual.args.includes('-port') && option('-port') === String(expected.port);
}
export async function availablePort(port) {
  if (!Number.isInteger(port) || port < 1024 || port > 65535) return false;
  return new Promise(resolveResult => {
    const server = createServer();
    server.once('error', () => resolveResult(false));
    server.listen({ port, host: '127.0.0.1', exclusive: true }, () => server.close(() => resolveResult(true)));
  });
}
function snapshot(pid) {
  if (!/^[1-9][0-9]*$/.test(pid)) throw new Error('INVALID_PID');
  const stat = readFileSync('/proc/' + pid + '/stat', 'utf8');
  return { started: stat.slice(stat.lastIndexOf(') ') + 2).split(' ')[19],
    executable: realpathSync(readlinkSync('/proc/' + pid + '/exe')),
    args: readFileSync('/proc/' + pid + '/cmdline', 'utf8').split('\0').filter(Boolean) };
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [operation, ...args] = process.argv.slice(2);
  if (operation === 'hosted') {
    if (!hostedRunner(process.env)) { console.error('HOSTED_LINUX_RUNNER_REQUIRED'); process.exitCode = 2; }
  } else if (operation === 'ports') {
    if (!(await availablePort(Number(args[0]))) || !(await availablePort(Number(args[1])))) {
      console.error('PROPOSED_EMULATOR_PORT_IN_USE'); process.exitCode = 2;
    }
  } else if (operation === 'capture' || operation === 'verify') {
    try {
      const [pid, avd, port, sdk, started] = args;
      const actual = snapshot(pid);
      const expected = { avd, port, sdk: realpathSync(sdk), started: operation === 'capture' ? actual.started : started };
      if (!ownsProcess(actual, expected)) process.exitCode = 2;
      else if (operation === 'capture') console.log(actual.started);
    } catch {
      process.exitCode = 2;
    }
  } else {
    console.error('INVALID_OWNERSHIP_OPERATION'); process.exitCode = 2;
  }
}