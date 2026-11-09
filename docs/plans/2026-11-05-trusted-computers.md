# Trust a computer once

## Root cause

The released gate remembers one bearer for one caller-selected client UUID.
Re-pairing the same UUID replaces the old bearer. A new CLI, lost token, changed
browser socket or concurrent client can therefore ask again from the same computer.
The unfinished branch used IP permission, which does not survive an address change
and can give authority to a different computer reusing that address.

## Contract

The computer's Ed25519 public key is the durable product permission. The CLI keeps
one private key per computer OS user in its protected `.kelpie` directory and
shares it across CLI and MCP invocations. It is independent of discovery sockets,
IP addresses, browser profiles and self-reported names. IP is displayed only.

Remote manual pairing uses a random five-minute server challenge and a signature
bound to that challenge and key. The server verifies possession before prompting.
One Allow computer decision resolves all proven callers for that key. Reconnection
with a trusted key never prompts; another key at the same IP does. Revocation removes
the key and its bearer hashes. Account-only UOA grants retain their separate live
checks and never create permanent computer permission. Localhost programs are
implicitly allowed after browser-request and framing checks.

## Implementation and verification

One shared native verifier, queue and atomic, locked store serves all platforms.
The existing pairing endpoints and native dialog are retained. Legacy bearer
grants stay readable without inferring computer trust. IP-only stored grants do
not authorize signing keys. CMake fetches and hash-verifies the pinned Ed25519
implementation and compiles it into the existing state library.

Verify signatures, replay, expiry, concurrent tools, changed IP/port, app restarts,
another key at the same IP, storage failure, revocation and UOA non-escalation.
Exercise real HTTP/MCP control, native approval and Settings. Publish affected
versions, then install and verify the published app and CLI on Mac, Minis and Maxis.
