import type { DeviceInfoFull, DeviceCapabilities, Platform } from "./device-types.js";

// --- Base ---

export interface SuccessResponse {
  success: true;
}

export interface ElementRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface ElementInfo {
  tag: string;
  id?: string;
  text?: string;
  classes?: string[];
  attributes?: Record<string, string | null>;
  rect?: ElementRect;
  visible?: boolean;
  interactable?: boolean;
}

// --- Navigation ---

export interface NavigateRequest {
  url: string;
}

export interface NavigateResponse extends SuccessResponse {
  url: string;
  title: string;
  loadTime: number;
}

export interface HistoryResponse extends SuccessResponse {
  url: string;
  title: string;
}

export interface GetCurrentUrlResponse {
  url: string;
  title: string;
}

// --- Screenshots ---

export type ScreenshotResolution = "native" | "viewport";

export interface ScreenshotRequest {
  fullPage?: boolean;
  format?: "png" | "jpeg";
  quality?: number;
  resolution?: ScreenshotResolution;
}

export interface ScreenshotMetadata {
  width: number;
  height: number;
  format: "png" | "jpeg";
  resolution?: ScreenshotResolution;
  coordinateSpace?: "viewport-css-pixels";
  viewportWidth?: number;
  viewportHeight?: number;
  devicePixelRatio?: number;
  imageScaleX?: number;
  imageScaleY?: number;
}

export interface ScreenshotResponse extends SuccessResponse, ScreenshotMetadata {
  image: string;
}

// --- DOM ---

export interface GetDOMRequest {
  selector?: string;
  depth?: number;
}

export interface GetDOMResponse extends SuccessResponse {
  html: string;
  nodeCount: number;
}

export interface QuerySelectorRequest {
  selector: string;
}

export interface QuerySelectorResponse extends SuccessResponse {
  found: boolean;
  element?: ElementInfo;
}

export interface QuerySelectorAllRequest {
  selector: string;
}

export interface QuerySelectorAllResponse extends SuccessResponse {
  count: number;
  elements: ElementInfo[];
}

export interface GetElementTextRequest {
  selector: string;
}

export interface GetElementTextResponse extends SuccessResponse {
  text: string;
}

export interface GetAttributesRequest {
  selector: string;
}

export interface GetAttributesResponse extends SuccessResponse {
  attributes: Record<string, string>;
}

// --- Interaction ---

export interface ClickRequest {
  selector: string;
  timeout?: number;
}

export interface ClickResponse extends SuccessResponse {
  element: { tag: string; text?: string };
}

export interface TapRequest {
  x: number;
  y: number;
}

export interface TapResponse extends SuccessResponse {
  x: number;
  y: number;
  appliedX: number;
  appliedY: number;
  offsetX: number;
  offsetY: number;
}

export interface SetTapCalibrationRequest {
  offsetX: number;
  offsetY: number;
}

export interface GetTapCalibrationResponse extends SuccessResponse {
  offsetX: number;
  offsetY: number;
}

export interface SetTapCalibrationResponse extends SuccessResponse {
  offsetX: number;
  offsetY: number;
}

export interface FillRequest {
  selector: string;
  value: string;
  timeout?: number;
}

export interface FillResponse extends SuccessResponse {
  selector: string;
  value: string;
}

export interface TypeRequest {
  selector?: string;
  text: string;
  delay?: number;
}

export interface TypeResponse extends SuccessResponse {
  typed: string;
}

export interface SelectOptionRequest {
  selector: string;
  value: string;
}

export interface SelectOptionResponse extends SuccessResponse {
  selected: { value: string; text: string };
}

export interface CheckRequest {
  selector: string;
}

export interface CheckResponse extends SuccessResponse {
  checked: boolean;
}

// --- Scrolling ---

export interface ScrollRequest {
  deltaX: number;
  deltaY: number;
}

export interface ScrollResponse extends SuccessResponse {
  scrollX: number;
  scrollY: number;
}

export interface Scroll2Request {
  selector: string;
  position?: "top" | "center" | "bottom";
  maxScrolls?: number;
}

export interface Scroll2Response extends SuccessResponse {
  element: { tag: string; visible: boolean; rect: ElementRect };
  scrollsPerformed: number;
  viewport: { width: number; height: number };
}

export interface ScrollToResponse extends SuccessResponse {
  scrollY: number;
}

// --- Viewport & Device Info ---

export interface GetViewportResponse {
  width: number;
  height: number;
  devicePixelRatio: number;
  platform: Platform;
  deviceName: string;
  orientation: "portrait" | "landscape";
}

export type GetDeviceInfoResponse = DeviceInfoFull;
export type GetCapabilitiesResponse = DeviceCapabilities;

// --- Wait / Sync ---

export interface WaitForElementRequest {
  selector: string;
  timeout?: number;
  state?: "attached" | "visible" | "hidden";
}

export interface WaitForElementResponse extends SuccessResponse {
  element: { tag: string; classes?: string[]; visible: boolean };
  waitTime: number;
}

export interface WaitForNavigationRequest {
  timeout?: number;
}

export interface WaitForNavigationResponse extends SuccessResponse {
  url: string;
  title: string;
  loadTime: number;
}

// --- Evaluate ---

export interface EvaluateRequest {
  expression: string;
}

export interface EvaluateResponse extends SuccessResponse {
  result: unknown;
}

// --- LLM: Smart Queries ---

export interface FindElementRequest {
  text: string;
  role?: string;
  selector?: string;
}

export interface FindElementResponse {
  found: boolean;
  element?: ElementInfo & { selector: string };
}

export interface FindButtonRequest {
  text: string;
}

export interface FindLinkRequest {
  text: string;
}

export interface FindInputRequest {
  label?: string;
  placeholder?: string;
  name?: string;
}

export interface FindInputResponse {
  found: boolean;
  element?: ElementInfo & { type: string; name: string; selector: string };
}

// --- LLM: Accessibility ---

export interface GetAccessibilityTreeRequest {
  root?: string;
  interactableOnly?: boolean;
  maxDepth?: number;
}

export interface AccessibilityNode {
  role: string;
  name?: string;
  value?: string;
  level?: number;
  checked?: boolean;
  disabled?: boolean;
  focused?: boolean;
  required?: boolean;
  children?: AccessibilityNode[];
}

export interface GetAccessibilityTreeResponse extends SuccessResponse {
  tree: AccessibilityNode;
  nodeCount: number;
}

// --- LLM: Annotated Screenshots ---

export interface ScreenshotAnnotatedRequest {
  fullPage?: boolean;
  format?: "png" | "jpeg";
  interactableOnly?: boolean;
  labelStyle?: "numbered" | "badge";
  resolution?: ScreenshotResolution;
}

export interface Annotation {
  index: number;
  role: string;
  name: string;
  selector: string;
  rect: ElementRect;
}

export interface ScreenshotAnnotatedResponse extends SuccessResponse, ScreenshotMetadata {
  image: string;
  annotations: Annotation[];
}

export interface ClickAnnotationRequest {
  index: number;
}

export interface ClickAnnotationResponse extends SuccessResponse {
  element: { role: string; name: string; selector: string };
}

export interface FillAnnotationRequest {
  index: number;
  value: string;
}

export interface FillAnnotationResponse extends SuccessResponse {
  element: { role: string; name: string; selector: string };
  value: string;
}

// --- LLM: Visible Elements ---

export interface GetVisibleElementsRequest {
  interactableOnly?: boolean;
  includeText?: boolean;
}

export interface VisibleElement {
  tag: string;
  text?: string;
  type?: string;
  name?: string;
  placeholder?: string;
  value?: string;
  rect: ElementRect;
  role?: string;
  interactable?: boolean;
}

export interface GetVisibleElementsResponse extends SuccessResponse {
  viewport: { width: number; height: number; scrollX: number; scrollY: number };
  elements: VisibleElement[];
  count: number;
}

// --- LLM: Page Text ---

export interface GetPageTextRequest {
  mode?: "readable" | "full" | "markdown";
  selector?: string;
}

export interface GetPageTextResponse extends SuccessResponse {
  title: string;
  byline: string | null;
  content: string;
  wordCount: number;
  language: string | null;
  excerpt: string;
}

// --- LLM: Form State ---

export interface GetFormStateRequest {
  selector?: string;
}

export interface FormField {
  name: string;
  type: string;
  selector: string;
  label: string | null;
  value: string;
  placeholder?: string;
  checked?: boolean;
  required: boolean;
  valid: boolean;
  validationMessage?: string;
  disabled: boolean;
  readonly?: boolean;
}

export interface FormInfo {
  selector: string;
  action: string;
  method: string;
  fields: FormField[];
  isValid: boolean;
  emptyRequired: string[];
  submitButton: { selector: string; text: string; disabled: boolean } | null;
}

export interface GetFormStateResponse extends SuccessResponse {
  forms: FormInfo[];
  formCount: number;
}

// --- DevTools: Console ---

export interface GetConsoleMessagesRequest {
  level?: "log" | "warn" | "error" | "info" | "debug";
  since?: string;
  limit?: number;
}

export interface ConsoleMessage {
  level: string;
  text: string;
  source: string;
  line: number;
  column: number;
  timestamp: string;
  stackTrace: string | null;
}

export interface GetConsoleMessagesResponse extends SuccessResponse {
  messages: ConsoleMessage[];
  count: number;
  hasMore: boolean;
}

export interface GetJSErrorsResponse extends SuccessResponse {
  errors: (ConsoleMessage & { type: string })[];
  count: number;
}

export interface ClearConsoleResponse extends SuccessResponse {
  cleared: number;
}

// --- DevTools: Network ---

export interface GetNetworkLogRequest {
  type?: string;
  status?: "success" | "error" | "pending";
  since?: string;
  limit?: number;
}

export interface NetworkEntry {
  url: string;
  type: string;
  method: string;
  status: number;
  statusText: string;
  mimeType: string;
  size: number;
  transferSize: number;
  timing: {
    started: string;
    dnsLookup?: number;
    tcpConnect?: number;
    tlsHandshake?: number;
    requestSent?: number;
    waiting?: number;
    contentDownload?: number;
    total: number;
  };
  initiator: string;
}

export interface GetNetworkLogResponse extends SuccessResponse {
  entries: NetworkEntry[];
  count: number;
  hasMore: boolean;
  summary: {
    totalRequests: number;
    totalSize: number;
    totalTransferSize: number;
    byType: Record<string, number>;
    errors: number;
    loadTime: number;
  };
}

export interface ResourceTimelineEntry {
  url: string;
  type: string;
  start: number;
  end: number;
  status: number;
}

export interface GetResourceTimelineResponse extends SuccessResponse {
  pageUrl: string;
  navigationStart: string;
  domContentLoaded: number;
  domComplete: number;
  loadEvent: number;
  resources: ResourceTimelineEntry[];
}

// --- DevTools: Mutations ---

export interface WatchMutationsRequest {
  selector?: string;
  attributes?: boolean;
  childList?: boolean;
  subtree?: boolean;
  characterData?: boolean;
}

export interface WatchMutationsResponse extends SuccessResponse {
  watchId: string;
  watching: boolean;
}

export interface GetMutationsRequest {
  watchId: string;
  clear?: boolean;
}

export interface MutationRecord {
  type: "childList" | "attributes" | "characterData";
  target: string;
  added?: { tag: string; class?: string; text?: string }[];
  removed?: { tag: string; class?: string; text?: string }[];
  attribute?: string;
  oldValue?: string | null;
  newValue?: string | null;
  timestamp: string;
}

export interface GetMutationsResponse extends SuccessResponse {
  mutations: MutationRecord[];
  count: number;
  hasMore: boolean;
}

export interface StopWatchingRequest {
  watchId: string;
}

export interface StopWatchingResponse extends SuccessResponse {
  totalMutations: number;
}

// --- DevTools: Shadow DOM ---

export interface QueryShadowDOMRequest {
  hostSelector: string;
  shadowSelector: string;
  pierce?: boolean;
}

export interface QueryShadowDOMResponse extends SuccessResponse {
  found: boolean;
  element?: ElementInfo & { shadowHost: string };
}

export interface ShadowRootHost {
  selector: string;
  tag: string;
  mode: "open" | "closed";
  childCount: number | null;
}

export interface GetShadowRootsResponse extends SuccessResponse {
  hosts: ShadowRootHost[];
  count: number;
}

// --- DevTools: Request Interception ---

export interface InterceptionRule {
  pattern: string;
  action: "block" | "mock" | "allow";
  mockResponse?: {
    status: number;
    headers: Record<string, string>;
    body: string;
  };
}

export interface SetRequestInterceptionRequest {
  rules: InterceptionRule[];
}

export interface SetRequestInterceptionResponse extends SuccessResponse {
  activeRules: number;
}

export interface GetInterceptedRequestsRequest {
  since?: string;
  limit?: number;
}

export interface InterceptedRequest {
  url: string;
  method: string;
  action: string;
  rule: string;
  timestamp: string;
}

export interface GetInterceptedRequestsResponse extends SuccessResponse {
  requests: InterceptedRequest[];
  count: number;
}

export interface ClearRequestInterceptionResponse extends SuccessResponse {
  cleared: number;
}

// --- Browser: Dialogs ---

export interface DialogInfo {
  type: "alert" | "confirm" | "prompt" | "beforeunload";
  message: string;
  defaultValue: string | null;
}

export interface GetDialogResponse extends SuccessResponse {
  showing: boolean;
  dialog: DialogInfo | null;
}

export interface HandleDialogRequest {
  action: "accept" | "dismiss";
  promptText?: string;
}

export interface HandleDialogResponse extends SuccessResponse {
  action: string;
  dialogType: string;
}

export interface SetDialogAutoHandlerRequest {
  enabled: boolean;
  defaultAction?: "accept" | "dismiss" | "queue";
  promptText?: string;
}

export interface SetDialogAutoHandlerResponse extends SuccessResponse {
  enabled: boolean;
}

// --- Browser: Tabs ---

export interface TabInfo {
  id: string;
  url: string;
  title: string;
  active: boolean;
  isLoading?: boolean;
}

export interface GetTabsResponse extends SuccessResponse {
  tabs: TabInfo[];
  count: number;
  /**
   * Active tab ID. Empty string `""` when no tab is active (e.g. CEF window
   * with no tabs, or transient state during a switch). Platforms have agreed
   * to standardise on the empty-string sentinel so consumers can branch on
   * `activeTab === ""` without null-checks.
   */
  activeTab: string;
}

export interface NewTabRequest {
  url?: string;
}

export interface NewTabResponse extends SuccessResponse {
  tab: TabInfo;
  tabCount: number;
}

export interface SwitchTabRequest {
  tabId: string;
}

export interface SwitchTabResponse extends SuccessResponse {
  tab: TabInfo;
}

export interface CloseTabRequest {
  tabId: string;
}

export interface CloseTabResponse extends SuccessResponse {
  closed: string;
  tabCount: number;
}

// --- Browser: Iframes ---

export interface IframeInfo {
  id: number;
  src: string;
  name: string;
  selector: string;
  rect: ElementRect;
  visible: boolean;
  crossOrigin: boolean;
}

export interface GetIframesResponse extends SuccessResponse {
  iframes: IframeInfo[];
  count: number;
}

export interface SwitchToIframeRequest {
  iframeId?: number;
  selector?: string;
}

export interface SwitchToIframeResponse extends SuccessResponse {
  iframe: { id: number; src: string };
  context: string;
}

export interface SwitchToMainResponse extends SuccessResponse {
  context: "main";
}

export interface GetIframeContextResponse extends SuccessResponse {
  context: string;
  iframe?: { id: number; src: string };
}

// --- Browser: Cookies ---

export interface CookieInfo {
  name: string;
  value: string;
  domain: string;
  path: string;
  expires: string | null;
  httpOnly: boolean;
  secure: boolean;
  sameSite: string;
}

export interface GetCookiesRequest {
  url?: string;
  name?: string;
}

export interface GetCookiesResponse extends SuccessResponse {
  cookies: CookieInfo[];
  count: number;
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
  name?: string;
  domain?: string;
  deleteAll?: boolean;
}

export interface DeleteCookiesResponse extends SuccessResponse {
  deleted: number;
}

// --- Browser: Storage ---

export interface GetStorageRequest {
  type?: "local" | "session";
  key?: string;
}

export interface GetStorageResponse extends SuccessResponse {
  type: string;
  entries: Record<string, string>;
  count: number;
}

export interface SetStorageRequest {
  type?: "local" | "session";
  key: string;
  value: string;
}

export interface ClearStorageRequest {
  type?: "local" | "session" | "both";
}

export interface ClearStorageResponse extends SuccessResponse {
  cleared: string;
}

// --- Browser: Clipboard ---

export interface GetClipboardResponse extends SuccessResponse {
  text: string;
  hasImage: boolean;
}

export interface SetClipboardRequest {
  text: string;
}

// --- Browser: Geolocation ---

export interface SetGeolocationRequest {
  latitude: number;
  longitude: number;
  accuracy?: number;
}

export interface SetGeolocationResponse extends SuccessResponse {
  geolocation: { latitude: number; longitude: number; accuracy: number };
}

// --- Browser: Keyboard & Viewport ---

export interface ShowKeyboardRequest {
  selector?: string;
  keyboardType?: "default" | "email" | "number" | "phone" | "url";
}

export interface ShowKeyboardResponse extends SuccessResponse {
  keyboardVisible: boolean;
  keyboardHeight: number;
  visibleViewport: { width: number; height: number };
  focusedElement: { selector: string; visibleInViewport: boolean } | null;
}

export interface HideKeyboardResponse extends SuccessResponse {
  keyboardVisible: false;
  visibleViewport: { width: number; height: number };
}

export interface GetKeyboardStateResponse extends SuccessResponse {
  visible: boolean;
  height: number;
  type: string;
  visibleViewport: { width: number; height: number };
  focusedElement: {
    selector: string;
    rect: ElementRect;
    visibleInViewport: boolean;
    obscuredByKeyboard: boolean;
  } | null;
}

export interface ResizeViewportRequest {
  width?: number;
  height?: number;
}

export interface ResizeViewportResponse extends SuccessResponse {
  viewport: { width: number; height: number };
  originalViewport: { width: number; height: number };
  /** macOS sets this to null after a manual resize since no named preset is active. */
  activePresetId?: string | null;
}

export interface ResetViewportResponse extends SuccessResponse {
  viewport: { width: number; height: number };
  /** macOS clears the active preset on reset. */
  activePresetId?: string | null;
}

export interface IsElementObscuredRequest {
  selector: string;
}

export interface IsElementObscuredResponse extends SuccessResponse {
  element: { selector: string; rect: ElementRect };
  obscured: boolean;
  reason: string | null;
  keyboardOverlap: number | null;
  suggestion: string | null;
}

// --- Browser: Viewport Presets ---

export interface SetViewportPresetRequest {
  presetId: string;
}

/** Describes a named viewport preset returned by `set-viewport-preset`. */
export interface ViewportPresetSummary {
  id: string;
  name: string;
  /** Display-size label such as "13.0\"" or "iPhone 15 Pro" — purely informational. */
  inches: string;
  /** Pixel-resolution label such as "390 x 844" — purely informational. */
  pixels: string;
}

export interface SetViewportPresetResponse extends SuccessResponse {
  activePresetId: string;
  preset: ViewportPresetSummary;
  viewport: { width: number; height: number };
}

// --- Browser: Fullscreen (macOS + Linux) ---

export interface SetFullscreenRequest {
  enabled: boolean;
}

export interface SetFullscreenResponse extends SuccessResponse {
  enabled: boolean;
}

export interface GetFullscreenResponse extends SuccessResponse {
  enabled: boolean;
}

// --- Browser: Orientation (iOS, Android, macOS) ---

export type OrientationMode = "portrait" | "landscape" | "auto";

export interface SetOrientationRequest {
  orientation: OrientationMode;
}

export interface GetOrientationResponse extends SuccessResponse {
  /** Currently reported orientation. */
  orientation: "portrait" | "landscape";
  /**
   * Locked orientation, or null when free rotation is allowed.
   * On macOS this is null whenever the active viewport does not support orientation selection.
   */
  locked: "portrait" | "landscape" | null;
}

export interface SetOrientationResponse extends SuccessResponse {
  orientation: "portrait" | "landscape";
  locked: "portrait" | "landscape";
  /** macOS reports the active viewport preset when orientation is changed. */
  activePresetId?: string | null;
  /** macOS reports the resulting viewport dimensions. */
  viewport?: { width: number; height: number };
}

// --- Browser: Renderer (macOS only) ---

/** @platform macos */
export type RendererEngine = "webkit" | "chromium" | "gecko";

/** @platform macos */
export interface SetRendererRequest {
  engine: RendererEngine;
}

/** @platform macos */
export interface SetRendererResponse extends SuccessResponse {
  engine: RendererEngine;
  /** True when the active engine changed, false when the requested engine was already active. */
  changed: boolean;
}

/** @platform macos */
export interface GetRendererResponse extends SuccessResponse {
  engine: RendererEngine;
  available: RendererEngine[];
}

// --- Browser: Issue Reporting ---

export interface ReportIssueRequest {
  category: string;
  command: string;
  error?: string;
  context?: string;
  url?: string;
  params?: Record<string, unknown>;
  diagnostics?: Record<string, unknown>;
  screenshotBase64?: string;
}

export interface ReportIssueResponse extends SuccessResponse {
  reportId: string;
  storedAt: string;
  platform: Platform;
  deviceId: string;
}

// --- Pairing & Auth ---

/**
 * `POST /v1/pair` request body. Both fields are caller-supplied and treated as
 * untrusted display data by the server — `clientName` is sanitized and labeled
 * "self-reported" in the device approval prompt.
 */
export interface PairRequest {
  /** Stable per-install UUID generated by the CLI. */
  clientId: string;
  /** Human-readable client name (e.g. `username@hostname`). Truncated to 64 chars. */
  clientName: string;
}

/** Initial response from `POST /v1/pair`. */
export interface PairResponse {
  status: "pending";
  /** Server-issued 32-byte CSPRNG nonce used to poll status. */
  requestId: string;
  /** Unix epoch ms when the pending request expires. */
  expiresAt: number;
  /** Authoritative socket peer address as seen by the server. */
  sourceAddress: string;
}

/**
 * Scope of an approved pairing.
 *
 * - `session` — kept in device memory only; cleared on app restart.
 * - `persistent` — written to the device's pairings store; survives restart.
 */
export type PairScope = "session" | "persistent";

export type PairStatusState =
  | "pending"
  | "approved"
  | "denied"
  | "expired"
  | "not_found";

/**
 * `GET /v1/pair/status?requestId=…` response. The plaintext `token` is
 * returned **exactly once** on approval; the pending entry is deleted server-side
 * immediately afterwards.
 */
export interface PairStatusResponse {
  status: PairStatusState;
  scope?: PairScope;
  token?: string;
}

/** `GET /v1/get-device-info` (unauthenticated) advertises pairing requirement. */
export interface DeviceInfoPairing {
  name: string;
  platform: string;
  version: string;
  requiresPairing: true;
}

// --- Group Command Responses ---

export interface DeviceMeta {
  name: string;
  platform: Platform;
  resolution: string;
}

export interface GroupResult<T = unknown> {
  command: string;
  deviceCount: number;
  results: {
    device: DeviceMeta;
    success: boolean;
    data?: T;
    error?: { code: string; message: string };
  }[];
  succeeded: number;
  failed: number;
}

export interface SmartQueryResult<T = unknown> {
  command: string;
  deviceCount: number;
  found: ({ device: DeviceMeta } & T)[];
  notFound: { device: DeviceMeta; reason: string }[];
}
