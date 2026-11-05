# Cross-document privacy checkpoint investigation

The Linux desktop CDP corpus recorded successful acknowledged click/input
checks but two cross-document capture cases refused because the old realm's
privacy classification was unavailable. The refusal remains in force.
Successful input acknowledgement does not prove that an unavailable later
classification was non-sensitive.

The desktop engine evaluates the fixed reader in a CDP isolated world.
Its current reader call obtains the current frame and world afresh; after
cross-document navigation this may be a different realm. The CEF DevTools
observer presently forwards network-observation events and has no Fetch
request interceptor.

A bounded headless Chromium loopback experiment on Maxis tested a possible
per-action checkpoint. It enabled CDP Fetch request-stage interception for
Document requests, dispatched a trusted CDP click, and retained the original
isolated-world context and target token. In the instrumented attempt:

- The Document request paused and the mouse-release command acknowledged.
- Runtime.evaluate in the original isolated context did not return within
  five seconds while the request remained paused.
- Fetch.continueRequest completed eleven milliseconds after it was issued.
- No privacy classification case completed; no capture was accepted.

The 1-CPU, 2-GiB JobObject receipt and bounded logs are in the common owner's
ignored Maxis scratch, `tmp/cdp-navigation-proof`. The second attempt's
job receipt SHA-256 is
`22b543968439724b5f5e4d75d966d9ed4d68fbaabbdef6d0b3bcb089f5a8c18c`;
its log SHA-256 is
`7dc6f07c824cf7283bf2d931941c8bc59e5d00868b732c653c7db393e363e028`.
The first attempt and its timeout are retained alongside it. The test used
one loopback navigation and does not establish behavior for every Chromium
version, response-stage interception, cached navigation, or CEF host.

The [Fetch protocol](https://chromedevtools.github.io/devtools-protocol/tot/Fetch/)
specifies that matching requests pause until continued, failed or fulfilled;
it does not promise that old-realm evaluation can run while a document
navigation is paused. [Page navigation events](https://chromedevtools.github.io/devtools-protocol/tot/Page/#event-frameStartedNavigating)
are notifications and can describe a navigation that is later cancelled; they
do not establish a synchronous pre-retirement checkpoint.

Therefore the straightforward request-pause and post-ack evaluation approach
is not accepted. A future solution needs evidence that final page handlers
have completed, a classification bound to the original target and realm,
and guaranteed release on all abort and error paths. Lost realms, malformed
results and unsupported navigation kinds remain unknown; capture discard and
output scrubbing must not be weakened. Acknowledged navigation itself remains
a valid final input outcome.

## CEF renderer lifecycle candidate

CEF's [render-process handler](https://github.com/chromiumembedded/cef/blob/master/include/cef_render_process_handler.h)
provides OnContextReleased on the renderer thread immediately before a V8
context is released. References must not be retained after that callback.
The [CEF world-identity issue](https://github.com/chromiumembedded/cef/issues/3867)
documents that DevTools isolated worlds can produce callbacks but the
callback does not expose their world ID.

A possible test-only probe would arm one bounded action against a specific
browser and frame, use an unpredictable isolated-world nonce and target token,
and attempt synchronous classification in the matching retiring context. Its
typed reply must carry the action nonce; missing, malformed, late, duplicated
or mismatched replies remain unknown. The registration and all context
references must retire at action completion, abort or teardown.

This remains a hypothesis. A native CEF test must establish that fixed-reader
evaluation and DOM access are allowed during the callback, that it follows
all synchronous final handlers, and that it distinguishes the correct
isolated world. It must exercise an actual navigation, late sensitivity,
target replacement, stale replies, crash and no-release cases. A BFCache
entry, failed or cancelled navigation, and a missing callback cannot be
treated as a non-sensitive classification. Do not introduce a persistent
page script or relax capture discard in lieu of that evidence.

A second otherwise matched probe intercepted the Document response stage. It
also received the mouse-release acknowledgement, but the original isolated
world evaluation did not return within five seconds. The response was
continued successfully; no classification case completed. The bounded
JobObject receipt SHA-256 is
`0fad4ea25835d2359436e9bd97ec7ee5b028724ec0fd66ebe166e4ad1da1c0ec`;
the log SHA-256 is
`6546a80127170dddf9d4c67f30ebd5071c9447d2d6bab90a2f11d83e47ceb63d`.
This does not establish all possible response-stage or CEF behavior.
