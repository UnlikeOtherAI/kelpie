import assert from 'node:assert/strict';
import { resolve } from 'node:path';
import test from 'node:test';
import { signingArguments, signingPlan, validateSigner } from '../../scripts/sign-macos-app.mjs';

const identity = 'Developer ID Application: UnlikeOtherAI s.r.o. (23B7GTLBN7)';
const app = resolve('artifacts/Kelpie.app');

test('rejects ad-hoc, development and mismatched identities before signing', () => {
  assert.doesNotThrow(() => validateSigner(identity, '23B7GTLBN7'));
  for (const invalid of ['-', 'Apple Development: Example', identity.replace('23B7GTLBN7', 'OTHER')]) {
    assert.throws(() => validateSigner(invalid, '23B7GTLBN7'));
  }
});

test('seals Mach-O children and their bundles before the containing app', () => {
  const framework = app + '/Contents/Frameworks/CEF.framework';
  const binary = framework + '/Versions/A/CEF';
  const plan = signingPlan(app, [{ path: framework, kind: 'bundle' }, { path: binary, kind: 'macho' }]);
  assert.deepEqual(plan.map(entry => entry.path), [resolve(binary), resolve(framework), app]);
  assert.throws(() => signingPlan(app, [{ path: resolve('unrelated.exe'), kind: 'macho' }]));
});

test('keeps Chromium helper exceptions out of the main app and signs with a timestamp', () => {
  const helper = { path: app + '/Contents/Frameworks/Kelpie Helper (Renderer).app', kind: 'bundle' };
  assert(signingArguments(helper, identity, 'helper.plist', 'app.plist').includes('helper.plist'));
  const main = signingArguments({ path: app, kind: 'bundle' }, identity, 'helper.plist', 'app.plist');
  assert(main.includes('app.plist'));
  assert(!main.includes('helper.plist'));
  assert(main.includes('runtime'));
  assert(main.includes('--timestamp'));
  assert(!main.includes('--deep'));
});
