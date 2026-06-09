import type {
  ElementInfo,
  ScreenshotResolution,
  ScreenshotResponse,
  SuccessResponse,
} from "./api-types.js";

export interface CoordinateDiagnosticsPoint {
  label?: string;
  x: number;
  y: number;
  expectedSelector?: string;
}

export interface CoordinateDiagnosticsSwipeAction {
  type: "swipe";
  label?: string;
  from: CoordinateDiagnosticsPoint;
  to: CoordinateDiagnosticsPoint;
  durationMs?: number;
  steps?: number;
  expectedSelector?: string;
}

export interface CoordinateDiagnosticsTapAction extends CoordinateDiagnosticsPoint {
  type: "tap";
}

export interface CoordinateDiagnosticsScrollAction {
  type: "scroll";
  label?: string;
  deltaX?: number;
  deltaY?: number;
  expectedSelector?: string;
}

export type CoordinateDiagnosticsAction =
  | CoordinateDiagnosticsTapAction
  | CoordinateDiagnosticsSwipeAction
  | CoordinateDiagnosticsScrollAction;

export interface CoordinateDiagnosticsRequest {
  points?: CoordinateDiagnosticsPoint[];
  actions?: CoordinateDiagnosticsAction[];
  setupExpression?: string;
  exportExpression?: string;
  captureScreenshot?: boolean;
  screenshotFormat?: "png" | "jpeg";
  screenshotResolution?: ScreenshotResolution;
  tabId?: string;
}

export interface CoordinateDiagnosticsVisualViewport {
  offsetLeft: number;
  offsetTop: number;
  pageLeft: number;
  pageTop: number;
  width: number;
  height: number;
  scale: number;
}

export interface CoordinateDiagnosticsViewport {
  width: number;
  height: number;
  scrollX: number;
  scrollY: number;
  devicePixelRatio: number;
  visualViewport: CoordinateDiagnosticsVisualViewport | null;
}

export interface CoordinateDiagnosticsPointSample extends CoordinateDiagnosticsPoint {
  pageX: number;
  pageY: number;
  elementFromPoint: ElementInfo | null;
  elementsFromPoint: ElementInfo[];
  matchesExpected?: boolean;
}

export interface CoordinateDiagnosticsEvent {
  type: string;
  target: ElementInfo | null;
  clientX?: number;
  clientY?: number;
  pageX?: number;
  pageY?: number;
  timeStamp?: number;
}

export interface CoordinateDiagnosticsActionResult {
  type: CoordinateDiagnosticsAction["type"];
  label?: string;
  accepted: boolean;
  input?: Record<string, unknown>;
  before?: CoordinateDiagnosticsPointSample | null;
  after?: CoordinateDiagnosticsPointSample | null;
  events: CoordinateDiagnosticsEvent[];
  expectedSelector?: string;
  matchesExpected?: boolean;
}

export interface CoordinateDiagnosticsInputCapabilities {
  trustedNativeInput: boolean;
  availableInputSources: ("page-synthesized" | "native-touch" | "native-mouse")[];
}

export interface CoordinateDiagnosticsClassification {
  status: "pass" | "fail" | "needs-review";
  reason: string;
}

export interface CoordinateDiagnosticsResponse extends SuccessResponse {
  coordinateSpace: "viewport-css-pixels";
  inputSource: "page-synthesized" | "native-touch" | "native-mouse";
  inputCapabilities: CoordinateDiagnosticsInputCapabilities;
  viewport: CoordinateDiagnosticsViewport;
  setupResult?: unknown;
  points: CoordinateDiagnosticsPointSample[];
  actions: CoordinateDiagnosticsActionResult[];
  eventLog: CoordinateDiagnosticsEvent[];
  exportResult?: unknown;
  screenshot?: ScreenshotResponse;
  classification: CoordinateDiagnosticsClassification;
}
