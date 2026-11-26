import { execFile } from 'node:child_process';
import { mkdtemp, open, readdir, rm } from 'node:fs/promises';
import { homedir, tmpdir } from 'node:os';
import { dirname, isAbsolute, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

const run = promisify(execFile);
const repository = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const machoMagic = new Set(['feedface', 'cefaedfe', 'feedfacf', 'cffaedfe', 'cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca']);

export function validateSigner(identity, team) {
  if (team !== '23B7GTLBN7' || !identity?.startsWith('Developer ID Application: ') || !identity.endsWith('(' + team + ')')) {
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

export function signingArguments(target, identity, helperEntitlements, appEntitlements, providerEntitlements, root = target.path) {
  const args = ['--force', '--options', 'runtime', '--timestamp', '--sign', identity];
  if (target.kind === 'bundle') {
    if (resolve(target.path) === resolve(root, 'Contents/PlugIns/KelpieAutoFill.appex')) args.push('--entitlements', providerEntitlements);
    else if (/Kelpie(?: Helper.*|GeckoHelper)\.app$/.test(target.path)) args.push('--entitlements', helperEntitlements);
    else if (target.path === root && root.endsWith('.app')) args.push('--entitlements', appEntitlements);
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
      if (/\.(app|appex|framework|bundle)$/.test(entry.name)) targets.push({ path, kind: 'bundle' });
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
  const profileDirectory = join(homedir(), '.config/unlikeotherai/signing/kelpie-autofill');
  const hostProfile = options.get('--host-profile') ?? join(profileDirectory, 'MAC_APP_DIRECT-host.provisionprofile');
  const providerProfile = options.get('--provider-profile') ?? join(profileDirectory, 'MAC_APP_DIRECT-provider.provisionprofile');
  const scratch = await mkdtemp(join(tmpdir(), 'kelpie-autofill-sign-'));
  try {
    const profiles = await run('python3', [join(repository, 'scripts/macos_autofill_signing.py'),
      '--app', app, '--host-profile', hostProfile, '--provider-profile', providerProfile, '--scratch', scratch]);
    const allowed = new Set(profiles.stdout.trim().split(/\s+/));
    const identities = await run('security', ['find-identity', '-v', '-p', 'codesigning']);
    const match = identities.stdout.split('\n').map(line => line.match(/\b([A-F0-9]{40}) "([^"]+)"/))
      .find(entry => entry && entry[2] === identity && allowed.has(entry[1]));
    if (!match) throw new Error('The selected Developer ID identity must be permitted by both profiles.');
    for (const target of targets) {
      await run('codesign', signingArguments(target, match[1], helperEntitlements,
        join(scratch, 'host.plist'), join(scratch, 'provider.plist'), resolve(app)));
    }
  } finally {
    await rm(scratch, { recursive: true, force: true });
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
