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

export function validateBluetoothUsage(plist) {
  const reason = plist.NSBluetoothAlwaysUsageDescription;
  if (typeof reason !== 'string' || !reason.trim()) {
    throw new Error('The Mac app needs a Bluetooth usage description for nearby sign-in devices.');
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
  const { stdout } = await run('plutil', ['-convert', 'json', '-o', '-', join(app, 'Contents', 'Info.plist')]);
  validateBluetoothUsage(JSON.parse(stdout));
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

/** Embed only Chromium's runtime and subprocesses. The containing app retains its own signer and entitlements. */
export async function embedSignedMacChromium({ app, source, identity, team }) {
  validateSigner(identity, team);
  const plist = join(app, 'Contents/Info.plist');
  const value = async key => (await run('/usr/libexec/PlistBuddy', ['-c', 'Print :' + key, plist])).stdout.trim();
  const identifier = await value('CFBundleIdentifier');
  const version = await value('CFBundleShortVersionString');
  const build = await value('CFBundleVersion');
  const helperEntitlements = join(repository, 'core/apple/Helpers/KelpieHelper.entitlements');
  const framework = 'Chromium Embedded Framework.framework';
  const helpers = ['Kelpie Helper', ...['Renderer', 'GPU', 'Plugin', 'Alerts'].map(role => 'Kelpie Helper (' + role + ')')];
  for (const name of [framework, ...helpers.map(helper => helper + '.app')]) {
    const destination = join(app, 'Contents/Frameworks', name);
    await run('ditto', [join(source, name), destination]);
    if (name !== framework) {
      const metadata = join(destination, 'Contents/Info.plist');
      const role = /\((\w+)\)/.exec(name)?.[1]?.toLowerCase();
      await run('plutil', ['-replace', 'CFBundleIdentifier', '-string', identifier + '.kelpie.helper' + (role ? '.' + role : ''), metadata]);
      await run('plutil', ['-replace', 'CFBundleVersion', '-string', build, metadata]);
      await run('plutil', ['-insert', 'CFBundleShortVersionString', '-string', version, metadata]);
    }
    const targets = await discover(destination);
    targets.push({ path: destination, kind: 'bundle' });
    for (const target of signingPlan(app, targets).slice(0, -1)) {
      await run('codesign', signingArguments(target, identity, helperEntitlements));
    }
    await run('codesign', ['--verify', '--deep', '--strict', destination]);
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
