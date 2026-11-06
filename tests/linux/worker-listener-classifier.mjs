// Retain only fixed listener-proof categories, never paths or raw errors.
export function classifyListenerFailure(error) {
 const names = {
  ENGINE_IDENTITY_UNAVAILABLE: 'identity-unavailable', ENGINE_IDENTITY_CHANGED: 'identity-changed',
  ENGINE_LISTENER_MISSING: 'listener-missing', ENGINE_LISTENER_NOT_OWNED: 'listener-not-owned',
  ENGINE_FD_LIMIT: 'fd-limit',
 };
 if (typeof error?.message === 'string' && Object.hasOwn(names, error.message)) return names[error.message];
 const codes = { EACCES: 'access-denied', EPERM: 'access-denied', ENOENT: 'not-found', EMFILE: 'fd-exhausted', ENFILE: 'fd-exhausted' };
 if (typeof error?.code === 'string' && Object.hasOwn(codes, error.code)) return codes[error.code];
 return 'other';
}
