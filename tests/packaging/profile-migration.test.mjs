import test from 'node:test';
import assert from 'node:assert/strict';
import { missingCookies, normalizeCookies, verifyCookies } from '../../scripts/profile-migration/cookies.mjs';

const fixture = { name: 'probe', value: 'test-only', domain: '127.0.0.1', path: '/', secure: false,
  httpOnly: true, expires: 2_000_000_000.75, sameSite: 'Lax' };

test('legacy CDP expiry becomes whole seconds and modern ISO cookies compare equally', () => {
  const legacy = normalizeCookies([fixture]);
  const modern = normalizeCookies([{ ...fixture, expires: '2033-05-18T03:33:20Z' }]);
  assert.equal(legacy[0].expires, 2_000_000_000);
  verifyCookies(legacy, modern);
  assert.equal(normalizeCookies([{ ...fixture, session: true, expires: -1 }])[0].expires, null);
  assert.equal(normalizeCookies([{ ...fixture, sameSite: undefined }])[0].sameSite, 'Unspecified');
});

test('existing modern cookies win by domain, path and name without dropping other paths', () => {
  const old = normalizeCookies([fixture, { ...fixture, path: '/other' }]);
  const modern = normalizeCookies([{ ...fixture, value: 'newer-test-only' }]);
  assert.deepEqual(missingCookies(old, modern), [old[1]]);
});

test('verification checks values and security flags without disclosing cookie contents', () => {
  const expected = normalizeCookies([fixture]);
  for (const difference of [{ value: 'changed-secret' }, { secure: true }, { httpOnly: false }, { sameSite: 'Strict' }]) {
    assert.throws(() => verifyCookies(expected, normalizeCookies([{ ...fixture, ...difference }])), error => {
      assert.doesNotMatch(error.message, /test-only|changed-secret|127\.0\.0\.1|probe/);
      return /read-back did not match/.test(error.message);
    });
  }
  assert.throws(() => verifyCookies(expected, []), /read-back did not match/);
  verifyCookies(normalizeCookies([{ ...fixture, expires: 1 }]), []);
});

test('unsupported partition keys and malformed expiry fail before import', () => {
  assert.throws(() => normalizeCookies([{ ...fixture, partitionKey: { topLevelSite: 'https://example.com' } }]), /Partitioned cookies/);
  assert.throws(() => normalizeCookies([{ ...fixture, expires: 'invalid' }]), /unsupported cookie expiry/);
});
