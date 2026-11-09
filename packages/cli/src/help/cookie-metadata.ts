import type { CommandHelp, HelpField } from "./command-metadata.js";

/**
 * Help metadata for cookie commands and peer-to-peer cookie sync. Keyed by
 * endpoint name; `command-aliases.ts` maps the CLI phrases here. The sync
 * protocol is in docs/api/cookie-sync.md.
 */

const SYNCED =
  "While the person is signed in to Kelpie, the default store also holds the cookies synced from their other Kelpie devices signed in to the same account on the same network.";

const cookieFields: HelpField[] = [
  { name: "name", type: "string" },
  { name: "value", type: "string" },
  { name: "domain", type: "string", description: "A leading dot marks a domain cookie; without it the cookie is host-only" },
  { name: "path", type: "string" },
  { name: "expires", type: "string|null", description: "ISO-8601 expiry, or null for a session cookie" },
  { name: "httpOnly", type: "boolean" },
  { name: "secure", type: "boolean" },
  { name: "sameSite", type: "enum", values: ["Strict", "Lax", "None", "Unspecified"] },
];

const failureFields: HelpField[] = [
  { name: "name", type: "string" },
  { name: "domain", type: "string" },
  { name: "error", type: "string", description: "Why the engine refused the cookie" },
];

const getCookiesResponse: HelpField[] = [
  { name: "success", type: "boolean", description: "true when the cookies were read" },
  { name: "cookies", type: "array", items: { name: "cookie", type: "object", fields: cookieFields } },
  { name: "count", type: "number" },
  { name: "complete", type: "boolean", description: "With all:true. False on Android, which only finds cookies for URLs it knows" },
];

const setCookiesResponse: HelpField[] = [
  { name: "success", type: "boolean", description: "true when the request was accepted; refused cookies are listed in failed" },
  { name: "set", type: "number", description: "Cookies written" },
  {
    name: "failed",
    type: "array",
    items: { name: "failure", type: "object", fields: [{ name: "index", type: "number", description: "Position in the request's cookies array" }, ...failureFields] },
  },
];

const copyCookiesResponse: HelpField[] = [
  { name: "success", type: "boolean", description: "true when the copy ran; refused cookies are listed in failed" },
  { name: "copied", type: "number", description: "Cookies written into the target store" },
  { name: "failed", type: "array", items: { name: "failure", type: "object", fields: failureFields } },
];

const syncStatusResponse: HelpField[] = [
  { name: "success", type: "boolean" },
  { name: "supported", type: "boolean", description: "False when sync is not running on this device; reason says why" },
  { name: "reason", type: "enum", values: ["signed-out", "embedded", "webview-unsupported", "mdns-unavailable", "no-cef"] },
  { name: "signedIn", type: "boolean" },
  { name: "replica", type: "string", description: "This run's replica id; new on every launch and sign-in" },
  { name: "listening", type: "boolean", description: "Whether the sync-only listener accepts peers" },
  {
    name: "peers",
    type: "array",
    items: {
      name: "peer",
      type: "object",
      fields: [
        { name: "replica", type: "string" },
        { name: "platform", type: "string" },
        { name: "name", type: "string" },
        { name: "state", type: "enum", values: ["handshaking", "connected", "backoff", "clock-skew", "failed"] },
        { name: "lastSyncAt", type: "number", description: "Unix milliseconds" },
        { name: "lastError", type: "string" },
      ],
    },
  },
  {
    name: "store",
    type: "object",
    description: "Counts only; never a cookie name or domain",
    fields: [
      { name: "entries", type: "number" },
      { name: "tombstones", type: "number" },
      { name: "localOnly", type: "number", description: "Cookies kept from a different account; never synced" },
      { name: "unapplied", type: "number", description: "Synced cookies this engine refused" },
      { name: "skipped", type: "number", description: "Synced cookies ignored to stay under the per-domain and total caps" },
      { name: "warming", type: "boolean", description: "True for up to 30 s after launch while peers' cookies arrive" },
      { name: "lastPurgeAt", type: "number|null", description: "When a mass disappearance was last treated as a purge, not a logout" },
    ],
  },
];

export const cookieMetadata: Record<string, CommandHelp> = {
  "get-cookies": {
    purpose: "Get cookies",
    when: "Inspecting auth tokens, session cookies, or preferences, or exporting every cookie in a store",
    explanation: `Returns cookies from the native cookie store, including httpOnly cookies that JS \`document.cookie\` cannot see. Without all, returns the cookies the current page would send; url and name filter them. all:true returns every cookie in the target store instead. domain keeps cookies whose host is that domain or a subdomain. With no tabId and no partition the target is the default store. ${SYNCED} tabId reads that tab's store; partition reads that partition's store; pass at most one.`,
    errors: ["INVALID_PARTITION", "TAB_NOT_FOUND"],
    related: ["set-cookies", "copy-cookies", "set-cookie", "delete-cookies", "get-cookie-sync-status"],
    response: getCookiesResponse,
  },
  "set-cookie": {
    purpose: "Set a cookie",
    when: "Authenticating from a known session cookie, or setting auth tokens, locale preferences, or test data",
    explanation: "Sets a cookie in the native cookie store with optional domain, path, expires, secure, sameSite, and httpOnly. This is the supported way to inject an httpOnly session cookie — `eval`/`document.cookie` cannot set httpOnly cookies.",
    related: ["get-cookies", "set-cookies", "delete-cookies"],
  },
  "set-cookies": {
    purpose: "Write a list of cookies into one store",
    when: "Restoring cookies saved with get-cookies all:true, or planting a known session in a tab, partition, or the default store",
    explanation: `Writes up to 500 cookies in the shape get-cookies returns. With no tabId and no partition the target is the default store. ${SYNCED} Cookies written there sync to those devices like any other change. Refused cookies come back in failed with their index; the rest are still written. The CLI command \`kelpie cookies import <file|->\` reads a JSON array or a saved \`kelpie cookies list\` output and sends it in batches of 500. To move cookies between stores on one device, use copy-cookies.`,
    errors: ["INVALID_PARAMS", "INVALID_PARTITION", "TAB_NOT_FOUND"],
    related: ["get-cookies", "copy-cookies", "set-cookie"],
    response: setCookiesResponse,
  },
  "copy-cookies": {
    purpose: "Copy cookies between stores on one device",
    when: "Giving an isolated tab the person's signed-in sessions, or bringing a partition's cookies back into the default store",
    explanation: `Copies from one store to another without the values passing through the caller. {} is the default store. ${SYNCED} To sign an isolated tab in: open it with new-tab and a partition, then copy-cookies with from:{} and to:{tabId}, optionally with domain. Copying into the default store syncs the cookies to the person's other devices. Some sites bind a session to one device, address or user agent and reject a copied cookie. The same store as source and target is INVALID_ARGUMENT.`,
    errors: ["INVALID_ARGUMENT", "INVALID_PARTITION", "TAB_NOT_FOUND"],
    related: ["get-cookies", "set-cookies", "new-tab", "get-partitions"],
    response: copyCookiesResponse,
  },
  "get-cookie-sync-status": {
    purpose: "Show peer-to-peer cookie sync state",
    when: "Checking why cookies from another device have not arrived, or whether sync runs here at all",
    explanation: "Kelpie devices signed in to the same UOA account on the same local network keep one shared set of default-store cookies. No server stores or sees them. Partitioned tabs never sync. iOS syncs only in the foreground. This status reports whether sync runs (supported, reason), sign-in state, this run's replica id, whether the sync listener is up, each peer's platform, name, state, last sync and last error, and store counts. A peer in clock-skew has a clock more than 2 minutes off. Status never names a cookie or a domain.",
    related: ["get-cookies", "copy-cookies"],
    response: syncStatusResponse,
  },
  "delete-cookies": {
    purpose: "Delete cookies",
    when: "Clearing auth state or resetting to a clean state",
    explanation: "Deletes cookies by name and/or domain, or all cookies with deleteAll. While cookie sync runs, a small deletion from the default store (a site logout) reaches the person's other devices. Deleting more than 20 synced cookies that are also more than a quarter of the store at once (a clear-all) is treated as a purge and clears only this device.",
    related: ["get-cookies"],
  },
};
