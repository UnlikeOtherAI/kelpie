# Nessie account connection

Native build/test evidence and remaining real-device checks are recorded in [verification](nessie-connect-verification.md).

Device labels and compact model evidence obey wire UTF-16 length limits while preserving valid Unicode.

Extraction cancellation owns a separate request authority flag in the native model
runtime, including before worker dispatch. Pause/Stop never invokes a global model
cancel for that remote extraction, so it cannot cancel a person's separate AI chat.
Snapshots include observed unique selectors from the existing DOM selector builder,
bounded to 2000 characters; elements without a bounded selector are omitted.

The durable ledger acknowledges cancellation even before command delivery by retaining
a cancelled attempt tombstone and sequence-2 receipt. A later command for that attempt
cannot execute. Cancellation of a terminal attempt replays its retained event; an
already acknowledged attempt sends a lightweight receipt without old output. Receipt
decisions never cancel another active attempt. Exact terminal acknowledgements compact
known jobs to identity, deadline and terminal state. Only acknowledged terminal jobs
are retired after deadline plus 60 seconds; unknown cancellation receipts retain at
least the server's 15-minute admission window plus 60 seconds. A persisted nondecreasing
local time floor prevents a backward clock jump from re-admitting a retired deadline.
The core rejects expired commands before dispatch and deadlines over 15 minutes ahead;
active and unacknowledged results are never discarded to make capacity.

Android navigation reserves one explicit destination at the native mutation point. Only fixed
completion metadata reads may transfer to its first matching document start and resulting pin;
cancelled/replaced jobs, user page input, another tab, later document starts, and expired authority
invalidate that lease. Redirects that produce another document start fail closed and need a fresh snapshot.
Canonical account `tab.goto` uses this same lease: admission and renderer dispatch require the
original document version, and only the owned navigation's completion read may return with its
new outer `tabVersion`. A competing human navigation is not adopted as the job result.
Android and CEF do not expose a unique native navigation object. Their conservative
leases require the observed main-frame start and destination; hash-only navigation
that emits no such start cannot acquire a completion pin and fails on the job deadline.
WebKit likewise requires its issued navigation object to produce a matching start.
Apple WebKit binds completion to the issued `WKNavigation` object and its document start;
the iOS mutation checks authority immediately before calling WebKit. CEF completion requires
exactly the expected native main-frame navigation count and destination for navigate/reload.
Another document start or native user input revokes completion authority. Redirects that change
the expected CEF destination require a fresh snapshot rather than inheriting its contents.
Canonical account navigation uses that same CEF transition fence while retaining its immutable
job cancellation, deadline, generation and active-tab lease through the wait.

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
`operation`, `tabId`, `tabVersion` and object `input`. Legacy operation names remain
for persisted jobs during migration. New browser control uses `operation:"control"`
with `input:{request:<canonical Browser Control v1 request>}` and is advertised only
when the device hello includes the distinct `browser.control.v1` capability. The old
`browser.control` capability is retained for legacy clients and does not imply v1.
Canonical `capabilities`, `documentation`, `tabs.list` and `tabs.new` requests are
unbound (`tabId`/`tabVersion` null); every other method needs the same explicit
`request.tabId` and outer tab id plus the current outer document version. A successful
control result wraps the unchanged canonical response as `{response}` and adds
transport-only `tab:{tabId,tabVersion}` or `tabs:[{tabId,tabVersion}]` pins when
available. Canonical `tabs.list.value` remains an array whose entries use `id`.
Changing or reloading the document invalidates its version, even when the URL is
unchanged. Control uses the persistent native browser gateway, including its reference
registry, admission lease and renderer-operation fence; it does not translate references
into selectors or expose arbitrary scripts, cookies, account endpoints or extensions.
Screenshots retain the canonical typed image response and are projected through the
job-owned file service before model presentation. Native execution requires the named
tab to remain active except for an explicit `tabs.select`; account sign-in surfaces are
forbidden as both current and destination pages.

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
Their isolated routers share the original browser gateway's admission and reference
invalidation. Android also shares its renderer callback retirement tracker; Apple
keeps the admission lease until the awaited handler completes. A common browser
operation cannot overlap remote renderer work. Extraction releases that browser
admission before local model inference, and rechecks its immutable document authority
after inference. The selector/evidence wire remains version 1.
macOS supports both WebKit tabs and the visible Chromium/CEF surface. CEF exposes its
one current surface as one tab; `open` navigates that surface. Each main-frame start
rotates a native document identity, including reloads to the same URL. Remote `type`
sets the selected editable control through the existing atomic `fill` handler; it
does not write to an unrelated focused control. Only validated selector/text, HTTP(S)
URL, and bounded scroll inputs enter handlers. No caller-supplied JavaScript is accepted.

`tabs` returns `{tabs:[{tabId,tabVersion,url,title,loading,active}]}`. `open` returns
`{tabId,tabVersion,tabs}`. Actions return `{tabId,tabVersion,result}`; typing reports
the character count without echoing its contents. `snapshot` returns
`{tabId,tabVersion,page}` using the shared value-free fixed snapshot reader. Explicit
`input.includeScreenshot: true` adds the existing viewport JPEG response under
`screenshot`, including `image` base64 and CSS-pixel coordinate metadata.
Page entries include bounded `url`, `title`, `text`, `truncated` and observed
`elements:[{selector,tag,role,label}]`. Every selector resolves uniquely to the
observed element; duplicate IDs and document roots are checked. Snapshot and
extraction reuse the canonical collector without creating a reference registry.
Form values, textarea defaults and contenteditable text are excluded. Extraction
requests 6000 characters from `text`. Apple evaluates in its existing private
browser-control world; Android retains its documented page-realm limitations.
Each job's mutation fence includes its immutable job/attempt/deadline and native
account, foreground, connection and document authority. Canonical account requests
reuse the persistent common browser gateway and reference owner while carrying the
job's authorization, deadline, cancellation and document guard through renderer
dispatch. Later jobs cannot inherit that authority.

`extract` takes `question` and `maxOutputCharacters`. It reads at most 6000 page
characters, verifies the document before and after local inference, and returns
`{tabId,tabVersion,summary,evidence:[{url,excerpt,observedAt}],modelCapabilities:["text"]}`.
It uses the loaded embedded model only, with no model/provider fallback or cloud cost.
Backgrounding, cancellation, account changes, deadline expiry, and connection loss
stop active work and preserve a terminal result for acknowledgement/reconciliation.
The desktop browser must also remain visible and active; hiding/backgrounding the Mac
pauses its lifecycle. Device labels use the system device name when available and remain
bounded operational metadata.

For isolated Android verification, `./gradlew assembleDebug -PkelpieVerificationProfile=true`
builds `com.kelpie.browser.nessieverify` with local HTTP port 18420, leaving an installed Kelpie app's data and listener untouched.
This debug-only profile is for browser/UI checks; production OAuth verification uses the
registered production app. Native UI tests use their own simulator/emulator and never
terminate another person's Kelpie instance.
