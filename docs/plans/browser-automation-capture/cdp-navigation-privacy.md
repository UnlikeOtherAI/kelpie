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
