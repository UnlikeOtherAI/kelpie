# Direct UOA account for the macOS avatar

Kelpie connects directly to https://authentication.unlikeotherai.com as a public native OAuth client. No product authentication backend, embedded domain bearer, local password account, duplicate profile store, or user-configuration store is introduced. Future configuration storage belongs to UOA.

## Current integration gaps

Live RFC 8414 discovery returns 404. UOA intentionally disables the public OAuth profile in its deployment workflow. Its existing /oauth routes support dynamic public-client registration, exact redirect validation and PKCE S256 code exchange. They currently offer password login only; enrolled 2FA users cannot finish this public flow. Profile and avatar endpoints currently require confidential product credentials and cannot be called by Kelpie.

## Required UOA changes

Extend the existing public profile rather than reusing administrator login or weakening the confidential /auth boundary. Complete public 2FA continuations with exact client, redirect, state, scope, resource, PKCE and immutable credential-epoch binding; recheck expiration after user locks and use existing replay-safe TOTP verification and signature gates. Preserve required enrollment, current policy, ban and revocation checks. Public tokens need the issue-time credential epoch and strict current-user validation before profile disclosure. Add a subject-only profile/avatar read surface that checks RS256 signature, issuer, exact UOA audience, registered client, dedicated public domain, expiration, scopes and current credential epoch. Reuse UOA avatar resolution; never let a user ID in a request select another person's profile. Keep the application and administrator token classes separate.

Enable production only with a dedicated first-party domain, the existing public signing key, bounded scopes/resources, rate limiting and passing security regression tests. Enabling a signing key alone must still not enable the public routes. Keep discovery and /api and /llm contracts accurate, including the actual grant and login methods available. Complete provider login or communicate supported methods explicitly rather than presenting broken social/reset paths in the hosted login screen.

## Native client

Use ASWebAuthenticationSession for UOA-hosted credentials and 2FA. Generate random state and a fresh S256 verifier per attempt. Validate an exact registered callback, exactly one matching state and one code, then exchange over HTTPS directly with UOA. Do not follow token/profile redirects to other origins. Use an ephemeral URLSession with no disk cache or shared cookie store. Keep access credentials, profile and avatar in memory only; refresh profile on account-popup access with a short freshness bound and clear all state on expiry, rejection or sign-out. Only the public client registration identifier may persist. No Keychain.

The AppKit-backed circular avatar sits between History and More. Signed out, it uses a neutral person icon and a Sign in action. Signed in, it displays UOA's avatar and profile in an anchored account popup with Sign out. Opening the popup does not leak credentials into the normal browser renderer, automation API, logs or page scripts. Cancel and retry preserve a clean signed-out state. No photo is fabricated or copied from the design.

## Validation and delivery

Native tests cover PKCE/state/callback parsing, cancellation, expiration, bounded profile freshness, rejection cleanup, and no disk persistence. UOA tests cover scope/audience/client confusion, missing or stale credential epoch, disabled public profile, 2FA replay and expiry while blocked on locks, and foreign-subject disclosure. Render the signed-out avatar, hosted login, cancelled flow and signed-in account with a consented test account. A real user completes their own authentication. Deploy UOA, verify the live public contract, then publish/install the matching macOS release.

## Cross-provider review

The cross-provider review rule was removed from AGENTS.md and CLAUDE.md at the user’s request. No external review is claimed. Implementation uses focused tests and code review without a provider gate.

## Implemented direct account flow

The native app now uses public registration, ASWebAuthenticationSession, exact callback
and state validation, and S256 PKCE against UOA. No Kelpie backend is introduced. UOA's
hosted password flow completes replay-protected TOTP or context-bound required setup,
then retains the existing signature gate. Scoped `/oauth/me` profile/avatar and
`/oauth/me/settings/:namespace/:key` endpoints validate current authority. Settings
writes use conditional versions and the existing per-user quota transaction.

Kelpie's account button uses AppKit hit testing, as do its popup actions. Account data
is memory-only, and account favourites are separate from local signed-out favourites.
A serialized mutation queue retries conflicts against the latest server list and
suppresses stale responses after logout. Public sessions currently expire without a
refresh token; the hosted native profile supports password and authenticator login.
