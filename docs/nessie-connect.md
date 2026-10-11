# Nessie account connection

Signed-in native Kelpie connects outbound to `wss://api.nessie.works/api/kelpie/connect`.
The connection never exposes the local HTTP listener or needs LAN pairing or an executor.
UOA remains the sole identity authority. Native OAuth requests `kelpie.connect` alongside
the existing account scopes. An older grant needs a new sign-in to grant that scope.

The native account sends its existing UOA access token only to UOA:
`POST /oauth/kelpie/connect`, body
`{"resource":"https://api.nessie.works/api/kelpie/connect"}`. UOA returns a
120-second `connection_ticket`, `token_type: "Bearer"`, `expires_in`, and
`gateway_url`. Only that scoped ticket reaches Nessie. Reconnect obtains a fresh ticket;
the live socket renews every 60 seconds. The default gateway is exact and TLS-only.
Development overrides must explicitly trust both the UOA-approved resource and gateway.

## Version 1 frames

First frame: `hello` with `protocol: 1`, `ticket`, random install UUID
`installationId`, bounded `label`, `platform`, `capabilities`, `lifecycle` and
`modelInstalled`, `modelReady`, `modelCapabilities: ["text"]`, and
`delegatedBrowsing: false`. Installation metadata never establishes identity. Capabilities list only
implemented actions. Lifecycle is `ready`, `paused`, or `signed_out`; a background
mobile WebView is paused. Installed model, loaded model readiness and text/tool support
are distinct. Embedded GGUF supports text extraction, not a delegated browser tool loop.

`welcome` returns `protocol`, `deviceId`, random socket `generation`, `heartbeatMs`
and `maxFrameBytes`. Every later frame contains this `generation`.
`auth` renews `ticket`; `heartbeat` carries current `lifecycle` and all four model fields.

`command` carries UUID `jobId`, UUID `attemptId`, positive `seq`, ISO `deadline`,
`operation`, `tabId`, `tabVersion` and object `input`. Operations are `tabs`, `open`,
`navigate`, `snapshot`, `click`, `type`, `scroll`, `back`, `forward`, `reload`, `extract`.
`tabs` and `open` are unbound (`tabId`/`tabVersion` null). Every other operation requires
a matching existing tab and current document version. Changing or reloading the document
invalidates its version, even when the URL is unchanged. Native execution makes the
authorized tab visible; unrelated tabs, cookies, account endpoints and arbitrary script
execution are outside this operation allowlist.

`event` carries job/attempt/seq and `state` (`accepted`, `progress`, `completed`,
`failed`, `cancelled`), optional object `output` and bounded `error`.
`ack` acknowledges that exact job/attempt/seq. `cancel` cancels the attempt.
Event sequences are independent of command sequences: accepted is event 1 and the
terminal result is event 2. A late acknowledgement of event 1 cannot discard event 2.
Frames are at most 1 MiB and terminal output at most 768 KiB.

## Shared native ledger

`native/core-connect` owns validation, generation checks, idempotency and the result
outbox. Its C ABI is `kelpie/connect.h`; platform calls are serialized. `create` takes
previous journal JSON and a stable UOA account reference (never copied profile data).
`execute` takes `receive`, `complete`, or `replay` plus a JSON object and returns
`{decision,state}`. The platform must encrypt and synchronously atomically persist
`state` before executing a `command` decision or sending its frames. Storage failure
closes the connection and dispatches nothing.

The ledger reserves an attempt before execution. Same-attempt duplicate commands never
rerun; changing that attempt's command is rejected. Terminal events survive reconnect
and process restart until acknowledgement. Acknowledged identities remain tombstones.
An attempt interrupted by process exit becomes a terminal `UNKNOWN_EFFECTS` failure:
Nessie must reconcile the current page before issuing a new action. It must never
silently replay a potentially effective click, typing or navigation. Journal capacity
is bounded (32 MiB, 8192 attempt identities) and exhaustion fails closed.

Sign-out/account change cancels local jobs, closes the socket, and discards the prior
account journal. Reconnection revalidates UOA authority. Mobile execution is foreground
only; no iOS background browser or extraction capability is advertised.

## Native browser adapter

Nessie controls live in Settings and appear beside the visible browser while a job is
running or paused. Pause cancels the current job; Resume allows new jobs; Stop cancels
and leaves the device paused. A person switching or closing the controlled tab pauses
remote work. Returning to the foreground does not override a person's pause.

Apple and Android reuse their existing browser handlers through a job-owned context.
macOS supports both WebKit tabs and the visible Chromium/CEF surface. CEF exposes its
one current surface as one tab; `open` navigates that surface. Each main-frame start
rotates a native document identity, including reloads to the same URL. Remote `type`
sets the selected editable control through the existing atomic `fill` handler; it
does not write to an unrelated focused control. Only validated selector/text, HTTP(S)
URL, and bounded scroll inputs enter handlers. No caller-supplied JavaScript is accepted.

`tabs` returns `{tabs:[{tabId,tabVersion,url,title,loading,active}]}`. `open` returns
`{tabId,tabVersion,tabs}`. Actions return `{tabId,tabVersion,result}`; typing reports
the character count without echoing its contents. `snapshot` returns
`{tabId,tabVersion,page}` using compact interactable elements. Explicit
`input.includeScreenshot: true` adds the existing viewport JPEG response under
`screenshot`, including `image` base64 and CSS-pixel coordinate metadata.

`extract` takes `question` and `maxOutputCharacters`. It reads at most 6000 page
characters, verifies the document before and after local inference, and returns
`{tabId,tabVersion,summary,evidence:[{url,excerpt,observedAt}],modelCapabilities:["text"]}`.
It uses the loaded embedded model only, with no model/provider fallback or cloud cost.
Backgrounding, cancellation, account changes, deadline expiry, and connection loss
stop active work and preserve a terminal result for acknowledgement/reconciliation.
