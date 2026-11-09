import type { SuccessResponse } from "./api-types.js";

// Cookie requests and responses, including peer-to-peer cookie sync status.
// The sync protocol itself is in docs/api/cookie-sync.md.

/** `Unspecified` means the cookie carries no SameSite attribute. */
export type CookieSameSite = "Strict" | "Lax" | "None" | "Unspecified";

export interface CookieInfo {
  name: string;
  value: string;
  /** A leading dot marks a domain cookie; without it the cookie is host-only. */
  domain: string;
  path: string;
  /** ISO-8601 expiry, or `null` for a session cookie. */
  expires: string | null;
  httpOnly: boolean;
  secure: boolean;
  sameSite: CookieSameSite;
}

/**
 * Which cookie store a cookie call reads or writes. Pass at most one field.
 * Neither field means the default (unpartitioned) store, the one cookie sync
 * keeps in step across the person's signed-in devices.
 */
export interface CookieStoreTarget {
  /** That tab's store: its partition, or the default store for an unpartitioned tab. */
  tabId?: string;
  /** That partition's store. Must satisfy `validatePartition`. */
  partition?: string;
}

export interface GetCookiesRequest extends CookieStoreTarget {
  url?: string;
  name?: string;
  /** Every cookie in the target store instead of the current page's. */
  all?: boolean;
  /** Keep cookies whose host equals this domain or is a subdomain of it. */
  domain?: string;
}

export interface GetCookiesResponse extends SuccessResponse {
  cookies: CookieInfo[];
  count: number;
  /**
   * Sent with `all: true`. False on Android, which can only read cookies for
   * the URLs it knows about; true where the engine enumerates its whole store.
   */
  complete?: boolean;
}

/** Most cookies one `set-cookies` call accepts. */
export const MAX_SET_COOKIES = 500;

export interface SetCookiesRequest extends CookieStoreTarget {
  /** At most `MAX_SET_COOKIES`, in the shape `get-cookies` returns. */
  cookies: CookieInfo[];
}

/** A cookie the engine refused. Values never appear here. */
export interface CookieWriteFailure {
  name: string;
  domain: string;
  error: string;
}

export interface SetCookieFailure extends CookieWriteFailure {
  /** Position of the refused cookie in the request's `cookies` array. */
  index: number;
}

export interface SetCookiesResponse extends SuccessResponse {
  set: number;
  failed: SetCookieFailure[];
}

export interface CopyCookiesRequest {
  /** `{}` is the default store. */
  from: CookieStoreTarget;
  /** `{}` is the default store. Must differ from `from`. */
  to: CookieStoreTarget;
  /** Copy only cookies whose host equals this domain or is a subdomain of it. */
  domain?: string;
}

export interface CopyCookiesResponse extends SuccessResponse {
  copied: number;
  failed: CookieWriteFailure[];
}

/** Why cookie sync is not running on this device. */
export type CookieSyncUnsupportedReason =
  | "signed-out"
  | "embedded"
  | "webview-unsupported"
  | "mdns-unavailable"
  | "no-cef";

export type CookieSyncPeerState = "handshaking" | "connected" | "backoff" | "clock-skew" | "failed";

export interface CookieSyncPeer {
  /** The peer's replica id for this run of its store. */
  replica: string;
  /** Platform the peer reported in its hello, e.g. `macos`. */
  platform: string;
  /** Device name the peer reported in its hello. */
  name: string;
  state: CookieSyncPeerState;
  /** Unix milliseconds of the last completed pull or push. */
  lastSyncAt?: number;
  /** Error code of the last failure, e.g. `CLOCK_SKEW` or `ACCOUNT_MISMATCH`. */
  lastError?: string;
}

/** Counts only; the status never names a cookie or a domain. */
export interface CookieSyncStoreStatus {
  entries: number;
  tombstones: number;
  localOnly: number;
  unapplied: number;
  /** Remote records ignored because they would break the per-domain or total cap. */
  skipped: number;
  warming: boolean;
  /** Unix milliseconds of the last scan treated as a purge, or `null`. */
  lastPurgeAt: number | null;
}

export type GetCookieSyncStatusRequest = Record<string, never>;

export interface GetCookieSyncStatusResponse extends SuccessResponse {
  /** False when sync is not running here; `reason` says why. */
  supported: boolean;
  reason?: CookieSyncUnsupportedReason;
  signedIn: boolean;
  /** This run's replica id; absent while sync is not running. */
  replica?: string;
  /** Whether the sync-only listener is accepting peers. */
  listening: boolean;
  peers: CookieSyncPeer[];
  store: CookieSyncStoreStatus;
}

export interface SetCookieRequest {
  name: string;
  value: string;
  domain?: string;
  path?: string;
  httpOnly?: boolean;
  secure?: boolean;
  sameSite?: string;
  expires?: string;
}

export interface DeleteCookiesRequest {
  /** Scope deletion to cookies that would be sent to this URL (host/path/secure match). */
  url?: string;
  name?: string;
  domain?: string;
  deleteAll?: boolean;
}

export interface DeleteCookiesResponse extends SuccessResponse {
  deleted: number;
}
