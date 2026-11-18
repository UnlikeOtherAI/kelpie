// CEF 120 returns CDP cookies; current Kelpie accepts whole-second/ISO expiry.
// Keep values in memory, and never include a cookie in an error or log.
export function normalizeCookies(cookies) {
  if (!Array.isArray(cookies)) throw new Error('The browser did not return a cookie list');
  return cookies.map(cookie => {
    if (cookie.partitionKey || cookie.partitionKeyOpaque) {
      throw new Error('Partitioned cookies require a migration API that preserves their partition key');
    }
    const expires = cookie.session || cookie.expires == null || cookie.expires === -1 ? null
      : typeof cookie.expires === 'number' ? Math.floor(cookie.expires)
        : Math.floor(Date.parse(cookie.expires) / 1000);
    if (expires !== null && (!Number.isSafeInteger(expires) || expires < 0)) {
      throw new Error('The browser returned an unsupported cookie expiry');
    }
    const result = {
      name: cookie.name, value: cookie.value, domain: cookie.domain, path: cookie.path,
      httpOnly: cookie.httpOnly, secure: cookie.secure,
      sameSite: cookie.sameSite || 'Unspecified', expires,
    };
    for (const field of ['name', 'value', 'domain', 'path']) {
      if (typeof result[field] !== 'string') throw new Error('The browser returned an invalid cookie');
    }
    return result;
  });
}

export function cookieKey(cookie) { return JSON.stringify([cookie.domain, cookie.path, cookie.name]); }

export function missingCookies(legacy, current) {
  const keys = new Set(current.map(cookieKey));
  return legacy.filter(cookie => !keys.has(cookieKey(cookie)));
}

export function verifyCookies(expected, actual, now = Date.now() / 1000) {
  const found = new Map(actual.map(cookie => [cookieKey(cookie), cookie]));
  for (const cookie of expected) {
    if (cookie.expires !== null && cookie.expires <= now) continue;
    const other = found.get(cookieKey(cookie));
    if (!other || Object.keys(cookie).some(key => cookie[key] !== other[key])) {
      throw new Error('Cookie read-back did not match; the original profile has not been replaced');
    }
  }
}
