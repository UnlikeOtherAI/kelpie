# Computer pairing

Kelpie's manual approval belongs to an Ed25519 public key. IP addresses, HTTP
ports, mDNS labels and client UUIDs do not identify a trusted computer. The
normal CLI handles the protocol and private-key storage automatically.

## Protocol

1. `POST /v1/pair` with JSON `{clientId, clientName, computerPublicKey}`. The
   public key is exactly 32 bytes encoded as 64 lowercase hexadecimal characters.
   The response is HTTP 202 with `status: "computer_challenge"`, a random
   `requestId`, `expiresAt`, `sourceAddress`, and `approvalRequired: false`.
   This phase never displays a prompt or grants authority.
2. Sign the UTF-8 bytes `kelpie-computer-pair-v1\n<requestId>\n<computerPublicKey>`
   with that computer's Ed25519 private key. There is no trailing newline.
   Post the original fields plus `requestId` and `computerSignature` to
   `/v1/pair`. The signature is 64 bytes encoded as 128 lowercase hex characters.
   Kelpie rejects expired, reused, wrong-key, wrong-source or invalid proofs.
3. The response is HTTP 202 with `status: "pending"`, `requestId`, `expiresAt`,
   `sourceAddress`, and `approvalRequired`. False means the proven key is already
   trusted; true means Kelpie displays **No / Allow computer**. The name is
   self-reported; the verified key identifies the computer. The IP is context.
4. Poll `GET /v1/pair/status?requestId=…` from the handshake's source. Pending
   requests become `approved` with `scope: "persistent"` and an opaque `token`,
   or `denied`/`not_found`. The token is returned once. Send it as
   `Authorization: Bearer <token>` on subsequent API and MCP requests.

Each unproven challenge expires after five minutes. Once the native gate displays
a verified computer, that decision stays answerable until the person allows or
denies it, including when an OS dialog covers Kelpie. Other abandoned requests
still expire. An approval gets a fresh five-minute token-collection window; if
the original CLI already timed out, its next command reconnects to the approved
key without another prompt. One approval resolves concurrent proven requests
for the same key. Denial suppresses that key for ten minutes.
The queue admits at most 32 requests per source and 256 in total, including
unverified challenges. Account challenges use their separate UOA protocol.

## Reconnection and revocation

After IP, port, mDNS or client-ID changes, sign a fresh challenge with the same
key. An approved computer does not prompt again. Bearers also remain usable
after the computer's source IP changes and after Kelpie restarts. The CLI pins
cached bearers to a browser endpoint and uses a fresh signed handshake rather
than forwarding credentials to a newly discovered socket.

Ordinary CLI commands, `browser-control`, and CLI MCP share this reconnection
flow. No separate `kelpie pair` step is required. A new computer receives one
native approval; existing computer permission reconnects silently.

The protected server store retains public keys and at most 64 token hashes per
key. Evicting an old bearer causes an automatic signed reconnection. Settings
revocation removes that key and all its bearer hashes; every request consults
current durable permission. Another key at the old IP receives no authority.
`DELETE /v1/pair` with a computer bearer revokes its key. Localhost callers
manage remote keys through Settings; localhost itself is implicitly allowed.

The CLI's key is `~/.kelpie/computer-key.pem`, shared by tools running as that
OS user. POSIX permissions are directory 0700 and key 0600. A damaged existing
key produces an error; it is never silently replaced. A new key requires a new
approval. Private-key copies share authority, so keys stay on their computer.

## Compatibility and request safety

`/v1/get-device-info` advertises `approvalMode: "computer-key"` and
`localhostTrusted: true`. `requiresPairing` is false for actual loopback peers;
remote discovery alone cannot prove key ownership. New remote manual pairing
without a public key returns `COMPUTER_KEY_REQUIRED`, asking for a CLI update.
Legacy client bearers and narrow UOA account grants retain their existing scope
and independent revocation. Neither is automatically converted to key trust.
Version-1 IP-only trust files never authorize a computer key.

Implicit localhost permission uses the actual socket peer. Forwarded headers,
Host, client names and asserted IDs never establish identity. Control traffic
rejects browser Origin, cross-site fetches, unsafe Host headers, non-JSON POSTs
and ambiguous framing before implicit permission. Headless desktop instances
can reconnect trusted keys; unknown keys receive `APPROVAL_UNAVAILABLE` until
the native UI is available.
