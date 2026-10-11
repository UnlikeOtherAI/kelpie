# Automatic local account access

The original pairing request carries only self-reported `clientId`/`clientName`;
it cannot prove account ownership, so it always needs a prompt. Account pairing
adds a live UOA decision to the same store and endpoint. The requester and signed-in
Kelpie must have the same UOA subject. Matching email, team membership, installation
metadata or unsigned account ids never authorize control.

## Wire contract

Both steps require the existing pairing CSRF/header gate and the same socket peer.
The native account must remain in the same session through the complete exchange.

1. `POST /v1/pair` with `{clientId, clientName, account:true}` returns
   `202 {status:"account_challenge", requestId, expiresAt}`. `requestId` is a
   32-byte CSPRNG nonce. It expires within 120 seconds and is hidden from the
   approval UI. Manual approval cannot consume it.
2. The authorized requester obtains a proof from UOA over TLS:
   `POST /oauth/kelpie/pair`, body `{challenge:requestId, clientId}`,
   using its existing UOA authorization. Response: `{pairing_ticket, expires_in}`.
3. `POST /v1/pair` with `{clientId, account:true, requestId, accountTicket:pairing_ticket}`
   makes the browser call UOA using its own current account session:
   `POST /oauth/kelpie/pair/validate`, body `{ticket, challenge:requestId, clientId}`.
   A matching live account returns HTTP 200 `{active:true, expires_at}`; epoch
   timestamps are milliseconds. Invalid requester proofs return `{active:false}`
   or a non-401 refusal. Only rejection of the receiving app's credential uses
   401, because that ends its native account session.
4. Valid proofs return `200 {status:"approved", scope:"session", token, expiresAt}`
   directly from the native pair endpoint. The challenge and token issuance are
   consumed once; no approval dialog or status polling is needed.

UOA must bind its signed proof's token use and audience to local pairing, the
challenge and client id, cap its lifetime at 120 seconds/the issuing authorization's
expiry, and recheck both accounts' current authority when validating it. Connection
tickets intended for Nessie's WSS audience cannot be reused as local pairing proofs.

## Access and client sessions

The existing pairing store keeps only the account grant and token hash in memory.
On each authenticated API/MCP request, UOA revalidates the proof and subject match;
the server then rechecks native account generation, local revocation and expiry
before dispatch. UOA downtime fails closed. No profile or duplicate identity rows
are stored. A logout followed by login to the same subject cannot revive an old grant.
Explicit local revocation suppresses new requests from the source for ten minutes.

The `@unlikeotherai/kelpie/auth` export provides `pair` and `PairContext`. It accepts an existing `accountAccessToken` provider or an
`accountPairingTicket(challenge,clientId)` provider from an authorized application.
Standalone CLI/MCP processes also accept `KELPIE_UOA_ACCESS_TOKEN` from their existing
session provider. The CLI does not persist it or copy a native app's credentials.
Spendable UOA credentials are sent only to the fixed TLS UOA origin, with redirects
refused. Only the narrow proof reaches the LAN device. Account failures never
silently fall back to manual approval; clients without account authorization retain
the existing manual flow and socket-pinned persistent tokens.

Windows/Linux's local readiness-token interface needs no pairing approval already.
The direct Nessie account connection is independent of this local interface.

## Delivery dependency

The two UOA endpoints and an existing authorized client session provider are required
for automatic LAN access. Until those endpoints are deployed, the account path refuses
access and manual pairing continues to work for callers without account authorization.
Mocked platform/client tests verify the local admission logic, not production UOA
issuance, live account revocation, or published native installation.

## Verification

On 2026-10-11, CLI lint/build passed on Maxis, with 626 tests passing and 64
native integration cases skipped. Transport tests exercise compact MCP account
authorization and ensure absent/invalid accounts never open a manual prompt.
The full Android Gradle build passed on Ubuntu. Swift lint passed; macOS and
iOS simulator builds and 22 focused account/pairing/connection tests each passed
on dictator. The iOS Settings UI test passed and its screenshot was inspected;
the rebuilt Mac app launched and its health endpoint answered. Apple builds
still emit existing project/dependency warnings.

[UOA PR #95](https://github.com/UnlikeOtherAI/UnlikeOtherAuthenticator/pull/95)
adds the authority endpoints. Sixteen server-side connection/pairing cases
passed against an isolated PostgreSQL schema on Minis, including mismatched
subjects, revocation, consent narrowing and proof class/binding/expiry misuse.
This evidence does not prove signed release installation or a production
account-to-native LAN pairing journey.
