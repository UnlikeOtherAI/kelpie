import { execFile } from 'node:child_process';
import { open, readdir } from 'node:fs/promises';
import { dirname, isAbsolute, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

const run = promisify(execFile);
const repository = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const machoMagic = new Set(['feedface', 'cefaedfe', 'feedfacf', 'cffaedfe', 'cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca']);

export function validateSigner(identity, team) {
  if (!identity?.startsWith('Developer ID Application: ') || !team || !identity.endsWith('(' + team + ')')) {
    throw new Error('Use the existing Developer ID Application identity and its matching team.');
  }
}

export function signingPlan(app, entries) {
  const root = resolve(app);
  if (!root.endsWith('.app')) throw new Error('The signing target must be an app bundle.');
  const plan = entries.map(entry => {
    const path = resolve(entry.path);
    const child = relative(root, path);
    if (!child || child === '..' || child.startsWith('..' + sep) || isAbsolute(child)) {
      throw new Error('Signing inputs must be inside the selected app bundle.');
    }
    return { ...entry, path };
  });
  plan.sort((left, right) => right.path.split(sep).length - left.path.split(sep).length);
  return [...plan, { path: root, kind: 'bundle' }];
}

export function signingArguments(target, identity, helperEntitlements, appEntitlements) {
  const args = ['--force', '--options', 'runtime', '--timestamp', '--sign', identity];
  if (target.kind === 'bundle' && target.path.endsWith('.app')) {
    args.push('--entitlements', target.path.includes('Kelpie Helper') || target.path.includes('KelpieGeckoHelper')
      ? helperEntitlements : appEntitlements);
  }
  return [...args, target.path];
}

async function discover(directory) {
  const targets = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isSymbolicLink()) continue;
    if (entry.isDirectory()) {
      targets.push(...await discover(path));
      if (/\.(app|framework|bundle)$/.test(entry.name)) targets.push({ path, kind: 'bundle' });
    } else if (entry.isFile()) {
      const file = await open(path, 'r');
      try {
        const bytes = Buffer.alloc(4);
        const { bytesRead } = await file.read(bytes, 0, 4, 0);
        if (bytesRead === 4 && machoMagic.has(bytes.toString('hex'))) targets.push({ path, kind: 'macho' });
      } finally {
        await file.close();
      }
    }
  }
  return targets;
}

async function main() {
  const options = new Map();
  for (let index = 2; index < process.argv.length; index += 2) {
    options.set(process.argv[index], process.argv[index + 1]);
  }
  const app = options.get('--app');
  const identity = options.get('--identity');
  const team = options.get('--team');
  validateSigner(identity, team);
  if (process.platform !== 'darwin' || !app) throw new Error('Run on macOS with --app, --identity and --team.');
  const targets = signingPlan(app, await discover(resolve(app)));
  const helperEntitlements = join(repository, 'core/apple/Helpers/KelpieHelper.entitlements');
  const appEntitlements = join(repository, 'apps/macos/Kelpie/Kelpie.entitlements');
  for (const target of targets) {
    await run('codesign', signingArguments(target, identity, helperEntitlements, appEntitlements));
  }
  await run('codesign', ['--verify', '--deep', '--strict', '--verbose=2', app]);
  const { stderr } = await run('codesign', ['-dvv', app]);
  if (!stderr.includes('Authority=' + identity) || !stderr.includes('TeamIdentifier=' + team)
      || !stderr.includes('runtime') || !stderr.includes('Timestamp=')) {
    throw new Error('The final app lacks the requested Developer ID, hardened runtime or secure timestamp.');
  }
  process.stdout.write('Verified Developer ID signature, hardened runtime and timestamp.\n');
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
