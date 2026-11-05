# Approve a computer once

## Problem and root cause

Apple and Android approvals belong to a client UUID and bearer token. A new
client, lost session token, or another CLI process can therefore ask again even
when the user already approved that computer. Concurrent requests from one
address replace each other's pending challenges. Windows and Linux instead
have a loopback-only listener and a per-launch capability, with no LAN approval
flow. These models cannot deliver the requested computer-level permission.

## Decision

- Trust actual loopback socket peers automatically, without a token or prompt.
- A single **Allow computer** decision trusts the remote socket IP persistently.
  It permits all browser API/MCP operations and clients from that address across
  app restarts and browser sessions, until revoked in Settings.
- Trust belongs to the app installation, not an individual browser profile.
- Use parsed numeric socket addresses only. Normalize IPv4, IPv6, and IPv4-mapped
  IPv6 consistently; retain IPv6 interface scopes. Never use forwarded headers,
  Host, client UUID/name, DNS resolution, or an asserted signature as identity.
- This is IP-based permission, as requested. HTTP exposes no host public key.
  Address changes require another approval; another computer using the approved
  address inherits its permission. Do not claim SSH-style key pinning.
- Keep UOA identity and account grants separate. An explicit manual host approval
  is a product permission, not a duplicate human identity store. Account-only
  grants must never create durable host trust or survive their existing expiry.

## Request and storage behavior

All platforms use one native core-state implementation for numeric address
normalization and durable host permissions. A separate address-keyed store avoids
mixing host authority with caller-selected client UUIDs. Apple/Android keep legacy
tokens readable without inferring host trust. New manual records bind tokens to
their source and require that source's host approval. UOA session records retain
their existing bounds; manual UI offers Deny and Allow computer only. Trusted
sources bypass token requirements after request safety checks.

The existing `/v1/pair` and `/v1/pair/status` handshake stays compatible. Pending
manual prompts coalesce by canonical address while callers keep independent
challenges and token issuances. One decision resolves all manual waiters only.
Already trusted sources complete without another prompt. A response may include
`approvalRequired: false` so current clients can suppress misleading guidance.
Revoking an address invalidates its approvals and pending issuances immediately.

Windows and Linux share a small native peer-approval store and the same pairing
handshake. Native owner loops display pending requests without blocking HTTP
workers. Both listeners accept LAN connections; no remote API/MCP dispatch occurs
until the socket address is trusted. Persist permissions atomically in the
app's user data directory, shared by profiles. An interprocess lock protects each
reload-modify-atomic-write transaction. Unreadable/corrupt stores fail closed;
failed writes must not report persistent success. Reload permissions before
authorization so new processes see approvals and revocations. GUI Settings lists
addresses with revoke actions. Headless operation can use existing trust but
cannot approve a new address without the native UI.

Loopback trust does not authorize a webpage. Before peer authorization, reject
browser Origin, non-JSON control POSTs, ambiguous framing and duplicate security
headers. Validate Host as a numeric local endpoint or localhost, preventing DNS
rebinding. Discovery remains public and side-effect free. Socket addresses, not
the Host header, decide permission. Preserve MCP negotiation and shutdown gates.

## Verification and delivery

Cover address normalization, localhost without credentials, unknown LAN denial,
concurrent clients sharing one prompt, approve/restart/reuse without tokens,
different-address denial, revocation, legacy records, UOA non-escalation, browser
request rejection, and HTTP/MCP dispatch. Exercise native dialogs and Settings
through the actual apps on each available platform; report inaccessible hardware
or hosts precisely. Capture matching base/final screenshots only for changed
approval and Settings states. Run platform checks on their owning hosts, publish
affected versions in one release, install published artifacts, and verify them.

## Cross-Provider Review

Claude and an independent Codex reviewer reviewed the design before code changes.

Accepted: separate prompt coalescing from per-caller challenges; keep account
challenges out of manual batching; use address-keyed host records rather than
client UUIDs; lock shared-store transactions across processes; fail closed on
storage failure; cover the Linux fallback listener; update capability metadata;
bound pending requests and denial suppression; preserve browser safety checks
before trust; return explicit approval-unavailable in headless mode. Shared native
storage/parsing removes normalization drift. Keep manual pairing compatible with
the CLI account-first path by advertising account pairing unavailable on desktops
that do not implement the narrow UOA challenge protocol, allowing the existing
explicit manual path to proceed. Account-only calls never downgrade.

Not adopted: rejecting globally routable IPs (the requested authority is the
explicitly approved address, not a private-address allowlist); /64-wide approval
coalescing (different IPv6 addresses are distinct permissions); treating own LAN
addresses as localhost (loopback has an unambiguous socket definition); pretending
proxy headers can detect SSH tunnels (they cannot). Document that loopback proxies
and same-IP reuse share the chosen permission. Existing legacy bearer grants
remain independently revocable during migration. Per-request authorization
honors revocation for subsequent operations; already dispatched effects cannot be
undone. No new streaming transport is introduced.

## Implementation review

The implementation review found and corrected cross-platform gaps: caller IDs
are no longer interpreted as computer authority; account issuances survive an
independent computer revocation; mapped addresses share denial suppression;
corrupt files remain denied until a fresh explicit approval archives the corrupt
file and grants only that address. Unsupported newer schemas remain untouched.
The C response uses the existing `new[]` / `kelpie_free_string` ownership contract.

Pending requests allow 32 independent callers per source and eight source
addresses, so one source cannot consume every computer's queue. Desktop listeners
retain default socket options, accept IPv4 and IPv6, and fall back to IPv4 when
dual-stack binding is unavailable. The Linux fallback now uses the same HTTP
server rather than a second parser. A total request-read deadline, bounded worker
queue and payload limit bound slow headers and bodies without timing out browser
operations after dispatch.

Existing account-session equality checks already prevented hidden UOA challenges
from receiving a manual persistent grant; regression tests exercise that guard
before any host approval exists. Test assertions were already enabled explicitly
in Release builds. Legacy bearer authorization retains its custom-hostname path;
implicit computer permission requires safe Host and browser-request checks.

The CLI recognizes device-reported computer permission without sending a token
or starting pairing. Its account-first path falls back only for the explicit
unsupported-account response; account-only calls do not request manual approval.
