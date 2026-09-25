# Handover: finish native UOA signup and approved-app login

This document is for the next LLM continuing the Kelpie/UOA account work. It describes the shipped baseline, what is still missing, and the intended product direction:

- The user signs in on UnlikeOtherAuthenticator (UOA), not in a Kelpie auth backend.
- The UOA hosted page should look like a normal website login: UOA logo, app logo/name, email/password, and **Continue with Google**.
- Native products should appear in an approved-app list. Each approved app gets only the scopes it needs, especially the limited personal-settings API used by Kelpie favourites.

Do not investigate Chromium for this work. The browser engine is out of scope.

## What is already shipped

### Kelpie

- Kelpie PR [#149](https://github.com/UnlikeOtherAI/kelpie/pull/149) is merged at `34e3392dde39ea308db2483781abb99add903708`.
- Release [Kelpie macOS 0.1.17](https://github.com/UnlikeOtherAI/kelpie/releases/tag/release/2026-09-25.3) is published and installed at `/Applications/Kelpie.app`.
- The installed binary is build 16 and is running from `/Applications/Kelpie.app`.
- The account button is between History and More. It is AppKit-backed so WebView focus cannot steal clicks.
- The account popup has signed-out, signing-in, signed-in, error, refresh-favourites, and sign-out states.
- Kelpie starts `ASWebAuthenticationSession` against UOA with a fresh state and S256 PKCE verifier.
- The callback is `com.unlikeotherai.kelpie://oauth/callback`.
- Tokens, profile, avatar, and signed-in favourites stay in memory. The public client registration id may persist in `UserDefaults`; it is not a credential.
- Signed-out favourites remain local. Signing in switches to UOA's `browser/bookmarks` setting; signing out restores the local list.
- Bookmark saves are serialized, use `If-Match`, retry bounded 409 conflicts, preserve fields written by other UOA clients, and do not report success before the server write completes.
- Stale async responses are ignored after logout/account change.
- Native tests cover PKCE callback rejection, conflict retry, failed-save handling, account/local separation, and invalidation.

Relevant Kelpie files:

- `apps/macos/Kelpie/Account/UOAAccount.swift`
- `apps/macos/Kelpie/Account/UOAAuthorization.swift`
- `apps/macos/Kelpie/Account/UOATransport.swift`
- `apps/macos/Kelpie/Account/AccountBookmarks.swift`
- `apps/macos/Kelpie/Views/AccountButton.swift`
- `apps/macos/Kelpie/Browser/BookmarkStore.swift`
- `apps/macos/Kelpie/Handlers/BookmarkHandler.swift`
- `apps/macos/Tests/UOAAccountTests.swift`

### UOA

- UOA PR [#56](https://github.com/UnlikeOtherAI/UnlikeOtherAuthenticator/pull/56) is merged at `477ec39b246cd436ceda469dd12f23654b5626ad`.
- Production deployment for that merge succeeded.
- Live discovery is `https://authentication.unlikeotherai.com/.well-known/oauth-authorization-server`.
- Live metadata currently advertises:

  `openid profile email settings.read settings.write`

  and only the `authorization_code` grant with S256 PKCE and no client secret.
- Live `/oauth/me` and `/oauth/me/settings/browser/bookmarks` return 401 without a token.
- The live authorization page renders the login form and consent text.
- Public access tokens are RS256, `typ=at+jwt`, `token_use=public_oauth`, issuer/audience-bound, scope-bound, and carry the credential epoch (`tv`).
- UOA checks current credential epoch and current second-factor policy on profile/avatar/settings calls.
- UOA's public flow supports email/password plus enrolled TOTP and required TOTP enrollment. Required enrollment is bound to the complete OAuth request.
- Settings use the same `user_settings` table, quotas, and subject authority as PR #55. Kelpie uses namespace `browser`, key `bookmarks`.
- Public setting writes are conditional: GET returns an opaque ETag and PUT requires `If-Match`; stale writes return 409 and missing preconditions return 428.
- Public refresh tokens are intentionally not advertised. Expired sessions repeat hosted sign-in.

Relevant UOA files:

- `API/src/routes/oauth/authorize.ts`
- `API/src/routes/oauth/login.ts`
- `API/src/routes/oauth/token.ts`
- `API/src/routes/oauth/account.ts`
- `API/src/services/oauth/access-token.service.ts`
- `API/src/services/oauth/oauth-code.service.ts`
- `API/src/services/oauth/second-factor.service.ts`
- `API/src/services/oauth/account.service.ts`
- `API/src/services/user-settings.service.ts`
- `Auth/src/components/form/LoginForm.tsx`
- `Docs/Auth/native-accounts.md`
- `Docs/Auth/user-settings.md`

The UOA public profile is enabled in `.github/workflows/deploy-main.yml` with the dedicated non-admin logical domain `native.authentication.unlikeotherai.com`. UOA remains the only identity/profile/org authority. Do not add a Kelpie user table, copied avatar/email/name, local password, or Keychain credential.

## The remaining product gap

The current public profile is functional for password/TOTP, but it is not yet the finished signup experience. The next implementation must make the hosted UOA page look and behave like a first-party website login:

1. Show UOA branding consistently: UOA logo, wordmark, favicon, accessible alt text, and a polished card/page shell.
2. Show the relying app's identity: app logo, app name, and a concise statement such as “Kelpie wants to use your UOA account and save browser favourites.”
3. Add **Continue with Google** to the public flow. The Google button must complete through UOA's existing Google/OIDC provider implementation and then resume the exact public OAuth request with the same client, redirect URI, state, PKCE challenge, requested scopes, resource, and signature/2FA gates.
4. Make the first-time user path explicit. A person who chooses Google and has no UOA account should see the normal UOA account-creation/verification path, then return to the same authorization request. Do not create a product-local account.
5. Replace arbitrary public dynamic registration as the product-facing approval model with an approved-app registry, or make dynamic registration create a pending app that cannot authorize until UOA approves it.
6. Give each approved app a limited scope allowlist. Kelpie needs `openid profile email settings.read settings.write`; it must not receive admin, organisation, billing, or broad internal API scopes.

## Recommended approved-app model

The existing OAuth client row is currently enough for redirect URI and scope checks, but it needs explicit approval and branding metadata. Extend it with the minimum product-owned fields:

```text
OAuthClient
  clientId             stable public identifier
  clientName           human-readable app name
  logoUrl              optional HTTPS URL or UOA-hosted asset reference
  publisherName        optional publisher label
  approvalStatus       PENDING | APPROVED | DISABLED
  allowedScopes        existing scopes array; server-enforced upper bound
  redirectUris         exact match only
  approvedAt           nullable timestamp
  disabledAt           nullable timestamp
```

Do not store a user identity in this row. It is an application registration, not an account.

Use these rules:

- A native product can ship with a pre-approved client id, or register once and wait for approval.
- `/oauth/authorize`, `/oauth/login`, and `/oauth/token` reject `PENDING` and `DISABLED` clients with the same generic OAuth failure.
- Requested scopes must be a subset of both the UOA server-supported scopes and the approved client's `allowedScopes`.
- Redirect URI matching remains exact. Custom native schemes are allowed only for the approved client record.
- The hosted consent page reads app name/logo from the validated client record, never from untrusted query parameters.
- App logos must be HTTPS, size-limited, and protected from SSRF. Prefer UOA-hosted or prevalidated assets. Never fetch a caller-controlled logo during a sensitive login render without an allowlist/cache policy.
- Approval is an operator action in UOA. It should be auditable and reversible by setting `DISABLED`.
- Public client secrets are not introduced. PKCE is the native-client proof.

For the limited settings API, keep scopes coarse and explicit:

| Scope | Allows |
| --- | --- |
| `openid` | Authorization request and subject identity basis |
| `profile` | `GET /oauth/me` and `GET /oauth/me/avatar` |
| `email` | Permission to return the UOA email claim |
| `settings.read` | Read the authenticated subject's personal settings |
| `settings.write` | Replace/delete the authenticated subject's personal settings with ETag/CAS |

Do not add a `kelpie.bookmarks` scope unless there is a demonstrated need for per-app isolation. The current requirement is the shared UOA personal settings store, with Kelpie using only `browser/bookmarks`.

## Google login design

UOA already has Google provider configuration for the normal auth flow. Reuse the provider and callback/CSRF/state machinery rather than adding a second Google integration in Kelpie.

The public flow should be:

```text
Kelpie
  -> /oauth/authorize?client_id=...&redirect_uri=...&scope=...&code_challenge=...
UOA hosted page
  -> shows UOA branding + approved Kelpie branding + Continue with Google
UOA Google start
  -> UOA-generated state/nonce, PKCE request context, exact public OAuth context bound server-side
Google
  -> callback to UOA
UOA
  -> find or create UOA user, verify email/provider result, apply TOTP/signature policy
  -> issue the same one-use public authorization code
Kelpie
  -> exact callback/state check, exchange code with verifier
  -> /oauth/me and /oauth/me/avatar, then browser/bookmarks sync
```

Required security properties:

- Google state and nonce are one-use, expiry-bound, and bound to the public OAuth context digest.
- The Google callback cannot change `client_id`, redirect URI, scopes, resource, or PKCE challenge.
- The Google identity is linked to UOA's user authority only. Do not persist a second provider user in Kelpie.
- Email verification and account creation follow existing UOA policy. Do not silently auto-link a Google account to an existing password account unless the existing UOA linking policy explicitly permits it.
- If UOA policy requires TOTP, Google login enters the same public `twofa_required`/enrollment path before issuing the code.
- The Google button is omitted when the approved client or UOA public profile does not allow it; never render a fake provider button.
- Error and denial responses remain generic and must not reveal whether an email or Google identity exists.

## Hosted-login visual requirements

Update `Auth/src/components/form/LoginForm.tsx` and the surrounding auth shell, but keep the existing typed popup/query contract. The page should have:

- UOA logo at the top, with a safe fallback if the logo asset cannot load.
- Approved app logo/name beside or below “Sign in to [app]”.
- Email and password fields.
- A primary “Sign in” button.
- A divider labelled “or”.
- “Continue with Google” with the real Google mark and accessible label.
- Forgot-password and create-account links only when the corresponding UOA policy allows them.
- Consent text that names the approved app and requested scopes in plain language.
- No client-controlled HTML, inline SVG, or arbitrary remote image injection.
- Responsive layout for the system authentication browser and normal desktop browser widths.

The app-logo metadata should be passed through the validated server config/client record. Do not let `client_name` or `logo_uri` from an unapproved query string become trusted branding.

## Implementation order

1. Add the approved-app/branding schema and migration in UOA. Preserve existing registered clients by migrating them to `APPROVED` only where deployment policy explicitly says they are trusted; otherwise use `PENDING` and approve Kelpie explicitly.
2. Add service-level approval/status/scope checks and unit tests for disabled/pending clients, scope widening, redirect mismatch, and logo validation.
3. Add a bounded public authorization context store or signed continuation that carries the exact client/redirect/state/scope/resource/PKCE context through Google. Reuse existing UOA login continuation primitives where possible.
4. Add public Google start/callback routes that resume the existing public signature/2FA/code issuer. Keep the routes thin and put identity/provider decisions in services.
5. Update the hosted login UI with UOA/app logos, approved-app consent, and the real Google button. Add SSR/interaction tests for password, Google, denied consent, and no-provider cases.
6. Configure the public production profile to advertise Google only after the callback path and tests are green. Do not flip the UI flag first.
7. Update the native-account docs, API schema, `/llm` output, and Kelpie plan. Explain that Google is hosted by UOA and that Kelpie never sees Google credentials.
8. Run DB-less unit tests, Postgres integration tests, Auth tests, OpenAPI lint, SwiftLint, macOS tests/build, and the live discovery/unauthenticated endpoint probes.
9. Deploy UOA, verify the live metadata and hosted login page, then release/install the next Kelpie build if native changes are needed.

## Tests the next LLM must add

UOA:

- Approved client status: pending/disabled clients cannot authorize, login, or redeem codes.
- App branding: only validated approved metadata reaches rendered HTML; invalid logo URLs fail closed or use the UOA fallback.
- Scope: requested scopes cannot exceed server-supported or client-approved scopes.
- Google state/nonce/context binding, replay, expiry, wrong redirect, wrong client, wrong PKCE, and callback error paths.
- Google-created user uses the existing UOA identity authority and does not duplicate a local product user.
- Google + enrolled TOTP and Google + required enrollment both complete before code issuance.
- Provider denial returns a generic OAuth error without account-existence disclosure.
- Existing password/TOTP public flow remains green.

Kelpie:

- The system-auth browser URL contains the approved client id, exact callback, requested limited scopes, fresh state, and S256 challenge.
- The native client rejects callback duplicates, wrong state, wrong scheme/host/path, errors, and fragments.
- The account popup uses a neutral signed-out avatar, then the actual UOA avatar after `/oauth/me/avatar` succeeds.
- No Google credential or hosted-page cookie is copied into Kelpie or the renderer.
- Account favourites remain isolated from local favourites, preserve foreign metadata, retry conflicts, and stop applying responses after logout.

## Operational handoff

- Repository for the UOA side: `/Volumes/External/Projects/UnlikeOtherAuthenticator`.
- Repository for Kelpie: `/Volumes/External/Projects/kelpie`.
- UOA production service deploys from `main` via `.github/workflows/deploy-main.yml`.
- Existing production signing key secret: `MCP_OAUTH_ACCESS_TOKEN_PRIVATE_JWK`.
- Do not print or commit secrets. Do not add a new native backend or Keychain storage.
- Keep the dedicated public OAuth domain separate from `ADMIN_AUTH_DOMAIN`.
- Before claiming completion, distinguish local tests, CI, deployment, live discovery, hosted login rendering, and an actual user sign-in. An actual Google/password sign-in requires the user to complete their own credentials in the hosted window.

## Definition of done

The work is complete when an approved Kelpie client opens a polished UOA page showing the UOA logo, Kelpie identity, and a real “Continue with Google” option; password and Google flows both create or authenticate the UOA account; the exact OAuth request survives provider redirects and 2FA; only the approved profile/email/settings scopes are issued; the returned avatar/profile and conditional `browser/bookmarks` settings work in the installed Kelpie release; and production discovery, CI, deployment, and installed-binary checks are recorded.
