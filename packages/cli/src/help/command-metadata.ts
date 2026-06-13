import type { Platform } from "@unlikeotherai/kelpie-shared";

export interface HelpField {
  name: string;
  type: string;
  description?: string;
  values?: unknown[];
  default?: unknown;
  fields?: HelpField[];
  items?: HelpField;
}

export interface CommandHelp {
  purpose: string;
  when: string;
  explanation: string;
  errors?: string[];
  related?: string[];
  platforms?: readonly Platform[];
  paramDefaults?: Record<string, unknown>;
  response?: HelpField[];
}

const successOnlyResponse: HelpField[] = [
  { name: "success", type: "boolean", description: "true when the command succeeds" },
];

const screenshotResponse: HelpField[] = [
  { name: "success", type: "boolean", description: "true when the screenshot succeeds" },
  { name: "image", type: "string", description: "Base64-encoded image data" },
  { name: "format", type: "enum", description: "Image format", values: ["png", "jpeg"] },
  { name: "width", type: "number", description: "Image width in pixels" },
  { name: "height", type: "number", description: "Image height in pixels" },
  { name: "resolution", type: "enum", description: "Returned coordinate/image resolution mode", values: ["native", "viewport"] },
  { name: "coordinateSpace", type: "string", description: "Coordinate space for image-to-viewport mapping" },
  { name: "viewportWidth", type: "number", description: "Viewport width in CSS pixels" },
  { name: "viewportHeight", type: "number", description: "Viewport height in CSS pixels" },
  { name: "devicePixelRatio", type: "number", description: "Device pixel ratio used by the renderer" },
  { name: "imageScaleX", type: "number", description: "Image-to-viewport X scale factor" },
  { name: "imageScaleY", type: "number", description: "Image-to-viewport Y scale factor" },
];

const elementResponse: HelpField[] = [
  { name: "success", type: "boolean", description: "true when the element action succeeds" },
  {
    name: "element",
    type: "object",
    description: "The element that was targeted",
    fields: [
      { name: "tag", type: "string", description: "Element tag name" },
      { name: "text", type: "string", description: "Visible text when available" },
      { name: "selector", type: "string", description: "Stable selector for the targeted element" },
      {
        name: "rect",
        type: "object",
        description: "Element rectangle in viewport CSS pixels when available",
        fields: [
          { name: "x", type: "number" },
          { name: "y", type: "number" },
          { name: "width", type: "number" },
          { name: "height", type: "number" },
        ],
      },
    ],
  },
];

const tapResponse: HelpField[] = [
  { name: "success", type: "boolean", description: "true when the tap command executed" },
  { name: "x", type: "number", description: "Requested X coordinate" },
  { name: "y", type: "number", description: "Requested Y coordinate" },
  { name: "appliedX", type: "number", description: "Applied X coordinate after calibration" },
  { name: "appliedY", type: "number", description: "Applied Y coordinate after calibration" },
  { name: "offsetX", type: "number", description: "Applied calibration offset in X" },
  { name: "offsetY", type: "number", description: "Applied calibration offset in Y" },
  {
    name: "element",
    type: "object",
    description: "The actual element at the applied tap point when available",
    fields: [
      { name: "tag", type: "string" },
      { name: "text", type: "string" },
      { name: "selector", type: "string" },
    ],
  },
];

const coordinateDiagnosticsResponse: HelpField[] = [
  { name: "success", type: "boolean", description: "true when diagnostics ran" },
  { name: "inputSource", type: "string", description: "Input provenance, currently page-synthesized" },
  { name: "inputCapabilities", type: "object", description: "Whether trusted native input is available" },
  { name: "viewport", type: "object", description: "Viewport, scroll, DPR, and visualViewport metadata" },
  { name: "points", type: "array", description: "elementFromPoint/elementsFromPoint samples" },
  { name: "actions", type: "array", description: "Executed coordinate action diagnostics and event logs" },
  { name: "eventLog", type: "array", description: "Captured pointer, mouse, touch, wheel, and scroll events" },
  { name: "classification", type: "object", description: "pass, fail, or needs-review based on expectedSelector checks" },
];

const capabilitiesResponse: HelpField[] = [
  { name: "success", type: "boolean", description: "true when capabilities were retrieved" },
  { name: "version", type: "string", description: "App version on the device" },
  { name: "platform", type: "string", description: "Device platform" },
  { name: "supported", type: "array", description: "Supported HTTP methods", items: { name: "method", type: "string" } },
  { name: "partial", type: "array", description: "Methods with runtime caveats", items: { name: "method", type: "string" } },
  { name: "unsupported", type: "array", description: "Unsupported HTTP methods", items: { name: "method", type: "string" } },
];

const tabsResponse: HelpField[] = [
  { name: "success", type: "boolean", description: "true when tab state was retrieved" },
  { name: "count", type: "number", description: "Number of open tabs" },
  { name: "activeTab", type: "string", description: "Active tab ID" },
  {
    name: "tabs",
    type: "array",
    description: "Open tabs",
    items: {
      name: "tab",
      type: "object",
      fields: [
        { name: "id", type: "string" },
        { name: "url", type: "string" },
        { name: "title", type: "string" },
        { name: "active", type: "boolean" },
        { name: "isLoading", type: "boolean" },
      ],
    },
  },
];

const newTabResponse: HelpField[] = [
  { name: "success", type: "boolean", description: "true when the tab was created" },
  { name: "tabId", type: "string", description: "Created tab ID. This is the value to pass back as tabId in later commands." },
  {
    name: "tab",
    type: "object",
    description: "Created tab metadata",
    fields: [
      { name: "id", type: "string", description: "Created tab ID. Same value as tabId." },
      { name: "url", type: "string" },
      { name: "title", type: "string" },
      { name: "active", type: "boolean" },
      { name: "isLoading", type: "boolean" },
    ],
  },
  { name: "tabCount", type: "number", description: "Number of open tabs after creation" },
];

const reportIssueResponse: HelpField[] = [
  { name: "success", type: "boolean", description: "true when the report was stored" },
  { name: "reportId", type: "string", description: "Remote report identifier" },
  { name: "storedAt", type: "string", description: "Remote storage timestamp" },
  { name: "platform", type: "string", description: "Platform that stored the report" },
  { name: "deviceId", type: "string", description: "Device identifier on the target" },
];

const feedbackSummaryResponse: HelpField[] = [
  { name: "success", type: "boolean", description: "true when the summary succeeded" },
  { name: "total", type: "number", description: "Total locally stored reports" },
  { name: "byCategory", type: "record", description: "Counts by failure category" },
  { name: "byCommand", type: "record", description: "Counts by command" },
  { name: "byPlatform", type: "record", description: "Counts by platform" },
  { name: "byError", type: "record", description: "Counts by error code" },
  { name: "recent", type: "array", description: "Most recent stored reports", items: { name: "report", type: "object" } },
];

/** Extended help metadata keyed by CLI command name (kebab-case). */
export const commandMetadata: Record<string, CommandHelp> = {
  // --- Navigation ---
  navigate: { purpose: "Navigate the browser to a URL", when: "Starting a new page interaction or redirecting the browser", explanation: "Loads the given URL in the device browser and waits for the page to finish loading. Returns the final URL (which may differ due to redirects), page title, and load time in milliseconds.", errors: ["NAVIGATION_ERROR", "TIMEOUT", "INVALID_URL"], related: ["back", "forward", "reload", "get-current-url"] },
  back: { purpose: "Go back in browser history", when: "Returning to a previously visited page", explanation: "Navigates one step back in the browser's session history, equivalent to pressing the browser back button.", errors: ["NAVIGATION_ERROR"], related: ["forward", "navigate"] },
  forward: { purpose: "Go forward in browser history", when: "Returning to a page after going back", explanation: "Navigates one step forward in the browser's session history.", errors: ["NAVIGATION_ERROR"], related: ["back", "navigate"] },
  reload: { purpose: "Reload the current page", when: "Page content may have changed or you need a fresh state", explanation: "Reloads the current page and waits for load to complete.", errors: ["NAVIGATION_ERROR", "TIMEOUT"], related: ["navigate"] },
  "get-current-url": { purpose: "Get the current URL and title", when: "Checking which page the browser is on", explanation: "Returns the current page URL and title without performing any navigation.", related: ["navigate"] },
  "set-home": { purpose: "Set the device home page", when: "Configuring which URL loads on app start", explanation: "Sets a persistent home page URL on the device. The browser will load this URL on next launch instead of the default.", related: ["get-home", "navigate"] },
  "get-home": { purpose: "Get the device home page", when: "Checking what URL loads on app start", explanation: "Returns the currently configured home page URL.", related: ["set-home", "navigate"] },
  toast: { purpose: "Show a toast overlay", when: "Displaying short status or narration on the device itself", explanation: "Shows a short-lived toast message overlay on the target device. Use this to narrate automation steps or expose state to a person watching the screen.", related: ["show-commentary", "highlight show"], response: successOnlyResponse },
  "debug-screens": { purpose: "Get screen diagnostics", when: "Inspecting connected displays, scenes, and debug screen state on supported platforms", explanation: "Returns platform-specific screen, scene, and external-display diagnostics. This is mainly useful on iOS when investigating stage placement or display routing.", errors: ["PLATFORM_NOT_SUPPORTED"], related: ["get-device-info", "get-debug-overlay", "set-debug-overlay"], platforms: ["ios"], response: successOnlyResponse },
  "set-debug-overlay": { purpose: "Set debug overlay state", when: "Turning the on-screen debug overlay on or off during display debugging", explanation: "Enables or disables the on-screen debug overlay on supported platforms.", errors: ["PLATFORM_NOT_SUPPORTED"], related: ["get-debug-overlay", "debug-screens"], platforms: ["ios"], response: successOnlyResponse },
  "get-debug-overlay": { purpose: "Get debug overlay state", when: "Checking whether the on-screen debug overlay is enabled", explanation: "Returns whether the debug overlay is currently enabled on the target device.", errors: ["PLATFORM_NOT_SUPPORTED"], related: ["set-debug-overlay", "debug-screens"], platforms: ["ios"], response: successOnlyResponse },
  "safari-auth": { purpose: "Authenticate in a browser-backed session", when: "A site must be authenticated through the platform browser session instead of in-page automation", explanation: "Opens a platform browser-backed authentication flow and returns once it has been started. Useful when a login flow depends on the platform browser's saved credentials, cookies, or anti-automation behavior.", errors: ["NO_WEBVIEW", "NO_URL", "PLATFORM_NOT_SUPPORTED"], related: ["navigate", "get-current-url"], platforms: ["ios", "macos"], response: successOnlyResponse },

  // --- Screenshots ---
  screenshot: { purpose: "Capture a screenshot", when: "Verifying visual state, debugging layout, or saving a snapshot", explanation: "Takes a PNG or JPEG screenshot of the visible viewport or full page. For LLM and MCP use, prefer viewport/CSS-pixel resolution unless you specifically need native renderer detail. The screenshot response now includes viewport mapping metadata so image pixels can be converted back into tap coordinates when needed. By default the CLI saves to a file (never returns base64 to LLMs). Use --output to control the save directory.", errors: ["TIMEOUT"], related: ["screenshot-annotated"], paramDefaults: { format: "png", resolution: "viewport" }, response: screenshotResponse },

  // --- DOM ---
  "get-dom": { purpose: "Get DOM tree as HTML", when: "Inspecting page structure or extracting content", explanation: "Returns the full or partial DOM tree as HTML string. Use the selector parameter to scope to a subtree, and depth to limit nesting. For large pages, prefer get-page-text or get-visible-elements.", errors: ["ELEMENT_NOT_FOUND"], related: ["query-selector", "get-page-text", "get-visible-elements"] },
  "query-selector": { purpose: "Find a single element", when: "Checking if an element exists or getting its properties", explanation: "Runs querySelector with the given CSS selector. Returns element info (tag, text, classes, rect) if found.", errors: ["ELEMENT_NOT_FOUND"], related: ["query-selector-all", "find-element"] },
  "query-selector-all": { purpose: "Find all matching elements", when: "Counting elements or collecting a list", explanation: "Runs querySelectorAll with the given CSS selector. Returns all matching elements with their properties.", related: ["query-selector"] },
  "get-element-text": { purpose: "Get text content of an element", when: "Reading text from a specific element", explanation: "Returns the textContent of the element matching the selector.", errors: ["ELEMENT_NOT_FOUND"], related: ["get-page-text", "query-selector"] },
  "get-attributes": { purpose: "Get all attributes of an element", when: "Inspecting element properties like href, src, data-* attributes", explanation: "Returns a key-value map of all HTML attributes on the matched element.", errors: ["ELEMENT_NOT_FOUND"], related: ["query-selector"] },

  // --- Interaction ---
  click: { purpose: "Click an element", when: "Activating buttons, links, or interactive elements after you already know the selector", explanation: "Finds the element by CSS selector, scrolls it into view if needed, and dispatches a coordinate-bearing activation at the rendered hit target. Prefer this after get-accessibility-tree or find-element and before any coordinate tap. The selectors returned by find-element, find-button, find-input, and screenshot-annotated are intended to be used here directly.", errors: ["ELEMENT_NOT_FOUND", "ELEMENT_NOT_VISIBLE", "TIMEOUT"], related: ["find-button", "find-element", "click-annotation", "tap"], response: elementResponse },
  tap: { purpose: "Tap at coordinates", when: "Last-resort interaction when semantic targeting and annotation-based targeting are both unavailable", explanation: "Performs a tap/click at the given x,y coordinates relative to the viewport. If the device has saved tap calibration offsets, they are applied automatically before dispatch. Prefer click, fill, or click-annotation first because raw coordinates still drift with layout, scrolling, and overlays.", errors: ["TIMEOUT"], related: ["click", "click-annotation", "screenshot-annotated"], response: tapResponse },
  fill: { purpose: "Fill a form field", when: "Entering text into inputs, textareas, or contenteditable elements once you have a selector", explanation: "Clears the current value and sets the new value. Prefer find-input or get-form-state first when you do not already know the selector. For character-by-character typing, use the type command instead.", errors: ["ELEMENT_NOT_FOUND", "ELEMENT_NOT_VISIBLE", "TIMEOUT"], related: ["type", "find-input", "fill-annotation", "get-form-state"], paramDefaults: { mode: "instant", delay: 50 }, response: elementResponse },
  type: { purpose: "Type text character by character", when: "Simulating real typing with keypress events, or typing into focused elements", explanation: "Types text one character at a time with optional delay between keystrokes. If selector is provided, focuses that element first. Useful for triggering autocomplete or real-time validation.", errors: ["ELEMENT_NOT_FOUND", "TIMEOUT"], related: ["fill"], paramDefaults: { delay: 50 }, response: successOnlyResponse },
  "select-option": { purpose: "Select a dropdown option", when: "Choosing from a <select> element", explanation: "Selects the option with the matching value attribute from a <select> element.", errors: ["ELEMENT_NOT_FOUND"], related: ["fill", "get-form-state"] },
  check: { purpose: "Check a checkbox", when: "Enabling a checkbox option", explanation: "Checks a checkbox element. No-op if already checked.", errors: ["ELEMENT_NOT_FOUND"], related: ["uncheck", "get-form-state"] },
  uncheck: { purpose: "Uncheck a checkbox", when: "Disabling a checkbox option", explanation: "Unchecks a checkbox element. No-op if already unchecked.", errors: ["ELEMENT_NOT_FOUND"], related: ["check"] },
  swipe: { purpose: "Swipe across the viewport", when: "You need to visually demonstrate a drag or JS-driven drag gesture", explanation: "Animates a swipe trail between two viewport coordinates and dispatches matching pointer events on the page. Useful for recording demos, carousels, and other JS-driven drags; use scroll for reliable native page scrolling.", related: ["scroll", "tap", "script"] },
  "coordinate-diagnostics": { purpose: "Run coordinate diagnostics", when: "Debugging hit-test, sticky-scroll, visual viewport, or coordinate translation bugs", explanation: "Samples elementFromPoint/elementsFromPoint at viewport coordinates, optionally runs page-synthesized tap/swipe/scroll actions, records delivered pointer and mouse event targets, can evaluate setup/export oracle JavaScript, and can return a screenshot with viewport mapping metadata. The response reports inputSource and inputCapabilities; do not assume trusted native input.", errors: ["INVALID_PARAMS", "EVAL_ERROR", "SCREENSHOT_FAILED"], related: ["tap", "swipe", "scroll", "evaluate", "screenshot"], platforms: ["ios", "android", "macos"], response: coordinateDiagnosticsResponse },
  "commentary show": { purpose: "Show commentary text", when: "Narrating a recording or calling attention to what happens next", explanation: "Displays a commentary pill inside the viewport at the chosen position. Use duration 0 to keep it visible until you hide or replace it.", related: ["commentary hide", "script run"] },
  "commentary hide": { purpose: "Hide commentary text", when: "Clearing a persistent commentary overlay before the next shot", explanation: "Dismisses the active commentary overlay immediately.", related: ["commentary show", "script run"] },
  "highlight show": { purpose: "Highlight an element", when: "You already know the selector and want to visually pin the target before interacting with it or before taking a screenshot", explanation: "Draws a colored ring/box around the element matching the selector. Supports quick appear or draw animations and optional persistence. Use duration 0 if you want the overlay to stay visible while you capture a screenshot and ask an LLM to reason about that specific area.", related: ["highlight hide", "click", "screenshot", "screenshot-annotated", "script run"] },
  "highlight hide": { purpose: "Hide the active highlight", when: "Clearing a persistent highlight overlay", explanation: "Removes the active highlight ring from the page.", related: ["highlight show", "script run"] },
  "script run": { purpose: "Run a scripted recording", when: "A walkthrough needs precise timing, overlays, and sequential device actions", explanation: "Reads a JSON script from disk and sends it to the device's play-script endpoint. The device enters recording mode, executes the actions in order, and returns the final playback summary.", related: ["script status", "script abort", "swipe"] },
  "script status": { purpose: "Check recording status", when: "A script is playing and you need to know which action is currently running", explanation: "Returns whether a recording script is currently playing, which action index is active, and how long playback has been running.", related: ["script run", "script abort"] },
  "script abort": { purpose: "Abort the current recording", when: "The scripted walkthrough needs to stop immediately", explanation: "Requests that the active recording script stop and returns the partial playback result collected so far.", related: ["script run", "script status"] },

  // --- Scrolling ---
  scroll: { purpose: "Scroll by pixel offset", when: "Scrolling a known number of pixels", explanation: "Scrolls the page by the given pixel deltas. Positive deltaY scrolls down, positive deltaX scrolls right.", related: ["scroll2", "scroll-to-top", "scroll-to-bottom"] },
  scroll2: { purpose: "Scroll until element is visible (resolution-aware)", when: "You need to interact with an element below the fold", explanation: "Scrolls the page until the target element is visible in the viewport. Unlike regular scroll, it adapts scroll distance to the device's screen size — a phone needs more scroll steps than a tablet. Use this when you need to bring an element into view before clicking or reading it.", errors: ["ELEMENT_NOT_FOUND", "TIMEOUT"], related: ["scroll", "click", "is-element-obscured"] },
  "scroll-to-top": { purpose: "Scroll to page top", when: "Returning to the beginning of the page", explanation: "Scrolls to the top of the page (scrollY = 0).", related: ["scroll-to-bottom", "scroll"] },
  "scroll-to-bottom": { purpose: "Scroll to page bottom", when: "Reaching the end of the page", explanation: "Scrolls to the bottom of the page.", related: ["scroll-to-top", "scroll"] },
  "scroll-to": { purpose: "Scroll to absolute pixel offset", when: "Debugging layout or navigating to a known Y position", explanation: "Scrolls the page so window.scrollY equals the given --y value. Optional --x offset (default 0). Works while the macOS 3D inspector is active — the inspector state is synced so exit restores the new position.", related: ["scroll", "scroll-to-top", "scroll-to-bottom"] },

  // --- Viewport & Device ---
  "get-viewport": { purpose: "Get viewport dimensions", when: "Checking screen size or device pixel ratio", explanation: "Returns viewport width, height, devicePixelRatio, platform, device name, and orientation.", related: ["resize-viewport", "get-device-info"], response: successOnlyResponse },
  "get-device-info": { purpose: "Get full device information", when: "Understanding device capabilities and hardware", explanation: "Returns comprehensive device info including OS version, browser engine, display properties, and network info.", related: ["get-viewport", "get-capabilities"], response: successOnlyResponse },
  "get-capabilities": { purpose: "Get device capabilities", when: "Checking what the current device and runtime actually support before attempting a command", explanation: "Returns supported, partial, and unsupported HTTP methods for the target device. Prefer this before platform-specific or engine-specific commands when capability mismatches are likely.", related: ["get-device-info", "discover"], response: capabilitiesResponse },
  "set-orientation": { purpose: "Set device orientation", when: "Forcing portrait, landscape, or auto orientation for responsive or rotation-specific testing", explanation: "Requests a new orientation mode on supported platforms. Use `auto` to remove the lock and let the device rotate normally.", errors: ["INVALID_PARAM", "PLATFORM_NOT_SUPPORTED"], related: ["get-orientation", "get-viewport"], platforms: ["ios", "android", "macos"], response: successOnlyResponse },
  "get-orientation": { purpose: "Get device orientation", when: "Checking the current orientation and whether the device is orientation-locked", explanation: "Returns the current orientation and any active orientation lock on supported platforms.", errors: ["PLATFORM_NOT_SUPPORTED"], related: ["set-orientation", "get-viewport"], platforms: ["ios", "android", "macos"], response: successOnlyResponse },
  "set-fullscreen": { purpose: "Set fullscreen mode", when: "Entering or leaving fullscreen mode on supported desktop platforms", explanation: "Enables or disables fullscreen mode for the local browser window when the platform supports it.", errors: ["PLATFORM_NOT_SUPPORTED"], related: ["get-fullscreen"], platforms: ["macos", "linux"], response: successOnlyResponse },
  "get-fullscreen": { purpose: "Get fullscreen mode", when: "Checking whether the desktop browser window is currently fullscreen", explanation: "Returns whether fullscreen mode is active on supported desktop platforms.", errors: ["PLATFORM_NOT_SUPPORTED"], related: ["set-fullscreen"], platforms: ["macos", "linux"], response: successOnlyResponse },
  "set-renderer": { purpose: "Set renderer engine", when: "Switching the active browser engine on platforms that support runtime renderer switching", explanation: "Requests a renderer switch, for example between WebKit and Chromium on macOS. Platform support and available engines vary.", errors: ["INVALID_PARAM", "PLATFORM_NOT_SUPPORTED"], related: ["get-renderer", "get-capabilities"], platforms: ["macos"], response: successOnlyResponse },
  "get-renderer": { purpose: "Get renderer engine", when: "Checking the active browser engine and available renderer choices", explanation: "Returns the active renderer and the renderer engines available on the current platform.", errors: ["PLATFORM_NOT_SUPPORTED"], related: ["set-renderer", "get-capabilities"], platforms: ["macos"], response: successOnlyResponse },
  "get-viewport-presets": { purpose: "List viewport presets", when: "Inspecting named viewport/device-size presets available on the current target", explanation: "Returns the available viewport presets and any currently active preset on supported platforms.", errors: ["PLATFORM_NOT_SUPPORTED"], related: ["set-viewport-preset", "get-viewport"], platforms: ["ios", "android", "macos"], response: successOnlyResponse },
  "set-viewport-preset": { purpose: "Set viewport preset", when: "Switching to a named viewport preset instead of a raw width/height resize", explanation: "Activates a named viewport preset returned by `get-viewport-presets` on supported platforms.", errors: ["INVALID_PARAM", "PLATFORM_NOT_SUPPORTED"], related: ["get-viewport-presets", "resize-viewport", "reset-viewport"], platforms: ["ios", "android", "macos"], response: successOnlyResponse },

  // --- Wait ---
  "wait-for-element": { purpose: "Wait for an element to appear", when: "Content loads asynchronously or appears after an action", explanation: "Waits until an element matching the selector reaches the specified state (attached, visible, or hidden). Returns the element and how long the wait took.", errors: ["TIMEOUT"], related: ["wait-for-navigation"] },
  "wait-for-navigation": { purpose: "Wait for navigation to complete", when: "After triggering a navigation (e.g., form submit) and waiting for the new page", explanation: "Waits for the current navigation to finish loading.", errors: ["TIMEOUT"], related: ["navigate", "wait-for-element"] },

  // --- Smart Queries ---
  "find-element": { purpose: "Find element by text or role", when: "Searching for an element when you don't know the CSS selector", explanation: "Searches the page for an element containing the given text, optionally filtered by ARIA role. Returns the element info and a stable CSS selector you can use for subsequent click, fill, or highlight commands. Prefer this before screenshot-driven tapping.", related: ["find-button", "find-link", "find-input", "query-selector", "click", "highlight show"] },
  "find-button": { purpose: "Find a button by text", when: "Looking for a button to click without guessing selectors", explanation: "Searches for a button (button, [role=button], input[type=submit]) matching the given text. Returns element info and a stable selector for a follow-up click or highlight.", related: ["click", "find-element", "highlight show"] },
  "find-link": { purpose: "Find a link by text", when: "Looking for a link to navigate without guessing selectors", explanation: "Searches for an anchor element matching the given text. Returns element info and a stable selector for a follow-up click or highlight.", related: ["click", "find-element", "highlight show"] },
  "find-input": { purpose: "Find an input by label", when: "Looking for a form field to fill without guessing selectors", explanation: "Searches for an input field by its label text, placeholder, or name attribute. Returns element info including type and a stable selector for a follow-up fill, click, or highlight.", related: ["fill", "find-element", "get-form-state", "highlight show"] },

  // --- Evaluate ---
  evaluate: { purpose: "Run JavaScript in the page", when: "Custom logic, extracting data, or manipulating the DOM directly", explanation: "Evaluates a JavaScript expression in the page context and returns the result. The expression runs in the page's global scope, not in Node.js.", errors: ["EVAL_ERROR"], related: ["get-dom", "get-page-text"] },

  // --- Console & DevTools ---
  "get-console-messages": { purpose: "Get console messages", when: "Debugging or monitoring page behavior", explanation: "Returns console messages (log, warn, error, info, debug) from the page. Filter by level or since a timestamp.", related: ["get-js-errors", "clear-console"] },
  "get-js-errors": { purpose: "Get JavaScript errors", when: "Checking for runtime errors on the page", explanation: "Returns only error-level console messages and uncaught exceptions.", related: ["get-console-messages"] },
  "clear-console": { purpose: "Clear console messages", when: "Resetting the console before monitoring a specific action", explanation: "Clears all stored console messages.", related: ["get-console-messages"] },
  "get-network-log": { purpose: "Get network requests", when: "Debugging API calls, checking request/response data", explanation: "Returns the network request log with URL, method, status, size, and timing information. Filter by type (xhr, script, image) or status.", related: ["get-resource-timeline", "set-request-interception"] },
  "get-resource-timeline": { purpose: "Get resource loading timeline", when: "Analyzing page load performance", explanation: "Returns the full resource loading timeline including DOMContentLoaded, load event times, and individual resource start/end times.", related: ["get-network-log"] },
  "get-websockets": { purpose: "List active WebSockets", when: "Inspecting live realtime connections on the page", explanation: "Returns the active WebSocket connections with URL, readyState, protocol, and sent/received message counters.", related: ["get-websocket-messages", "get-network-log"] },
  "get-websocket-messages": { purpose: "Get recent WebSocket messages", when: "Debugging live socket traffic or verifying realtime app behavior", explanation: "Returns recent sent and received WebSocket messages, optionally filtered to one active connection.", related: ["get-websockets"] },

  // --- LLM: Accessibility & Visual ---
  "get-accessibility-tree": { purpose: "Get the accessibility tree", when: "Understanding page structure semantically before interacting", explanation: "Returns the accessibility tree with roles, names, values, and states. This is usually the best first step for an LLM before clicking or filling. Use interactableOnly to filter to actionable elements.", related: ["find-element", "get-visible-elements", "get-dom"] },
  "screenshot-annotated": { purpose: "Screenshot with numbered annotations", when: "Using a visual fallback after semantic targeting fails, or after highlighting a known selector for visual confirmation", explanation: "Takes a screenshot with numbered labels overlaid on interactive elements. For LLM and MCP use, prefer viewport/CSS-pixel resolution so the image is smaller and the coordinate space lines up with tap more directly. Each annotation index is tied to the returned annotation list, not to image pixels. If you already know the selector and want to ground it visually, keep a highlight visible and then capture the screenshot.", related: ["click-annotation", "fill-annotation", "highlight show", "screenshot", "tap"] },
  "click-annotation": { purpose: "Click an annotated element by index", when: "After taking an annotated screenshot, clicking a numbered element without resorting to raw coordinates", explanation: "Clicks the element at the given annotation index from the most recent annotated screenshot using the same coordinate-bearing activation path as selector clicks. Prefer this over tap when you need visual grounding.", errors: ["ELEMENT_NOT_FOUND", "ELEMENT_NOT_VISIBLE"], related: ["screenshot-annotated", "fill-annotation", "tap"] },
  "fill-annotation": { purpose: "Fill an annotated element by index", when: "After taking an annotated screenshot, filling a numbered input without resorting to raw coordinates", explanation: "Fills the input at the given annotation index with the provided value. Prefer this over tap when you are working from a visual fallback.", errors: ["ELEMENT_NOT_FOUND"], related: ["screenshot-annotated", "click-annotation", "tap"] },
  "get-visible-elements": { purpose: "Get all visible elements", when: "Getting a concise list of what's currently on screen", explanation: "Returns all elements currently visible in the viewport with their positions. Use interactableOnly to filter to clickable/fillable elements.", related: ["get-accessibility-tree", "get-dom"] },
  "get-page-text": { purpose: "Extract readable text from the page", when: "Reading article content, form labels, or any text on the page", explanation: "Extracts text content from the page in readable, full, or markdown mode. The readable mode strips navigation and ads. This is usually the best way for an LLM to read page content.", related: ["get-dom", "get-element-text"] },
  "get-form-state": { purpose: "Get state of all forms", when: "Understanding form fields, their values, and validation status", explanation: "Returns all forms on the page with their fields, current values, validation state, and submit button info. Use this before filling forms to understand what needs to be filled.", related: ["fill", "find-input", "check"] },

  // --- Dialogs ---
  "get-dialog": { purpose: "Get current dialog", when: "Checking if a dialog (alert, confirm, prompt) is showing", explanation: "Returns info about any currently showing JavaScript dialog.", related: ["handle-dialog", "set-dialog-auto-handler"] },
  "handle-dialog": { purpose: "Accept or dismiss a dialog", when: "Responding to an alert, confirm, or prompt dialog", explanation: "Accepts or dismisses the current dialog. For prompt dialogs, provide promptText.", errors: ["NO_DIALOG"], related: ["get-dialog"] },
  "set-dialog-auto-handler": { purpose: "Auto-handle dialogs", when: "Dialogs interrupt your workflow and you want them handled automatically", explanation: "Enables automatic handling of JavaScript dialogs as they appear.", related: ["get-dialog", "handle-dialog"] },

  // --- Tabs ---
  "get-tabs": { purpose: "Get all open tabs", when: "Listing browser tabs or finding a specific one", explanation: "Returns all open tabs with their IDs, URLs, titles, and which is active.", related: ["new-tab", "switch-tab", "close-tab"], response: tabsResponse },
  "new-tab": { purpose: "Open a new tab", when: "Opening a URL in a new tab", explanation: "Opens a new browser tab, optionally navigating to a URL. Returns both tabId and tab.id for the created tab; they are the same identifier.", related: ["get-tabs", "switch-tab"], response: newTabResponse },
  "switch-tab": { purpose: "Switch to a tab", when: "Changing focus to a different tab", explanation: "Switches the active tab to the one with the given tab ID.", errors: ["TAB_NOT_FOUND"], related: ["get-tabs"], response: successOnlyResponse },
  "close-tab": { purpose: "Close a tab", when: "Cleaning up tabs you no longer need", explanation: "Closes the tab with the given ID.", errors: ["TAB_NOT_FOUND"], related: ["get-tabs"], response: successOnlyResponse },

  // --- Iframes ---
  "get-iframes": { purpose: "List all iframes", when: "Finding iframes on the page to interact with their content", explanation: "Returns all iframes with their src, name, position, and whether they're cross-origin.", related: ["switch-to-iframe", "get-iframe-context"] },
  "switch-to-iframe": { purpose: "Enter an iframe context", when: "You need to interact with content inside an iframe", explanation: "Switches the execution context into the specified iframe. All subsequent commands operate within the iframe until you switch-to-main.", related: ["switch-to-main", "get-iframes"] },
  "switch-to-main": { purpose: "Exit iframe context", when: "Returning to the main page after working in an iframe", explanation: "Switches back to the main frame context.", related: ["switch-to-iframe"] },
  "get-iframe-context": { purpose: "Check current frame context", when: "Verifying whether you're in the main frame or an iframe", explanation: "Returns the current frame context (main or iframe info).", related: ["switch-to-iframe", "switch-to-main"] },

  // --- Cookies ---
  "get-cookies": { purpose: "Get cookies", when: "Inspecting auth tokens, session cookies, or preferences", explanation: "Returns cookies from the native cookie store, including httpOnly cookies that JS `document.cookie` cannot see. Optionally filter by URL or name.", related: ["set-cookie", "delete-cookies"] },
  "set-cookie": { purpose: "Set a cookie", when: "Authenticating from a known session cookie, or setting auth tokens, locale preferences, or test data", explanation: "Sets a cookie in the native cookie store with optional domain, path, expires, secure, sameSite, and httpOnly. This is the supported way to inject an httpOnly session cookie — `eval`/`document.cookie` cannot set httpOnly cookies.", related: ["get-cookies", "delete-cookies"] },
  "delete-cookies": { purpose: "Delete cookies", when: "Clearing auth state or resetting to a clean state", explanation: "Deletes cookies by name and/or domain, or all cookies with deleteAll.", related: ["get-cookies"] },

  // --- Storage ---
  "get-storage": { purpose: "Get web storage entries", when: "Inspecting localStorage or sessionStorage", explanation: "Returns localStorage or sessionStorage entries. Filter by key name.", related: ["set-storage", "clear-storage"] },
  "set-storage": { purpose: "Set a storage entry", when: "Setting test data or configuration in web storage", explanation: "Sets a key-value pair in localStorage or sessionStorage.", related: ["get-storage", "clear-storage"] },
  "clear-storage": { purpose: "Clear web storage", when: "Resetting storage to a clean state", explanation: "Clears localStorage, sessionStorage, or both.", related: ["get-storage"] },

  // --- Mutations ---
  "watch-mutations": { purpose: "Start watching DOM changes", when: "Monitoring dynamic content or AJAX updates", explanation: "Starts a MutationObserver to record DOM changes. Returns a watchId to use with get-mutations and stop-watching.", related: ["get-mutations", "stop-watching"] },
  "get-mutations": { purpose: "Get recorded mutations", when: "Checking what DOM changes occurred since watching started", explanation: "Returns mutation records (added/removed nodes, attribute changes) for the given watchId.", related: ["watch-mutations", "stop-watching"] },
  "stop-watching": { purpose: "Stop watching mutations", when: "Done monitoring DOM changes", explanation: "Stops the mutation observer and returns the total count.", related: ["watch-mutations", "get-mutations"] },

  // --- Shadow DOM ---
  "query-shadow-dom": { purpose: "Query inside shadow DOM", when: "Interacting with web components that use shadow DOM", explanation: "Queries for an element inside a shadow root. Specify the host element selector and the selector within the shadow root.", errors: ["ELEMENT_NOT_FOUND"], related: ["get-shadow-roots"] },
  "get-shadow-roots": { purpose: "List shadow root hosts", when: "Finding which elements have shadow DOMs", explanation: "Returns all elements on the page that have shadow roots, with their mode and child count.", related: ["query-shadow-dom"] },

  // --- Clipboard ---
  "get-clipboard": { purpose: "Read clipboard", when: "Checking what's in the clipboard after a copy", explanation: "Returns the current text content of the clipboard.", related: ["set-clipboard"] },
  "set-clipboard": { purpose: "Write to clipboard", when: "Setting clipboard content for a paste operation", explanation: "Sets the clipboard text content.", related: ["get-clipboard"] },

  // --- Geolocation ---
  "set-geolocation": { purpose: "Override geolocation", when: "Testing location-based features with specific coordinates", explanation: "Overrides the device's geolocation to the given latitude and longitude.", errors: ["PLATFORM_NOT_SUPPORTED"], related: ["clear-geolocation"], platforms: [], response: successOnlyResponse },
  "clear-geolocation": { purpose: "Remove geolocation override", when: "Restoring real device location", explanation: "Removes the geolocation override, restoring the device's actual location.", related: ["set-geolocation"], platforms: [], response: successOnlyResponse },

  // --- Request Interception ---
  "set-request-interception": { purpose: "Intercept network requests", when: "Blocking ads, mocking API responses, or testing error handling", explanation: "Sets rules to intercept network requests. Each rule matches a URL pattern and can block, mock, or allow the request.", errors: ["PLATFORM_NOT_SUPPORTED"], related: ["get-intercepted-requests", "clear-request-interception"], platforms: [], response: successOnlyResponse },
  "get-intercepted-requests": { purpose: "Get intercepted requests", when: "Checking which requests were caught by interception rules", explanation: "Returns requests that matched interception rules.", related: ["set-request-interception"], platforms: [], response: successOnlyResponse },
  "clear-request-interception": { purpose: "Remove interception rules", when: "Done testing with request interception", explanation: "Clears all active interception rules.", related: ["set-request-interception"], platforms: [], response: successOnlyResponse },

  // --- Keyboard & Viewport ---
  "show-keyboard": { purpose: "Show on-screen keyboard", when: "Testing keyboard interaction or form input on mobile", explanation: "Shows the on-screen keyboard, optionally focusing a specific element. Returns keyboard height and visible viewport dimensions.", related: ["hide-keyboard", "get-keyboard-state", "is-element-obscured"], platforms: ["ios", "android"], response: successOnlyResponse },
  "hide-keyboard": { purpose: "Hide on-screen keyboard", when: "Dismissing the keyboard to interact with elements behind it", explanation: "Hides the on-screen keyboard and returns the restored viewport dimensions.", related: ["show-keyboard"], platforms: ["ios", "android"], response: successOnlyResponse },
  "get-keyboard-state": { purpose: "Get keyboard state", when: "Checking if keyboard is visible and what element has focus", explanation: "Returns keyboard visibility, height, type, and info about the focused element including whether it's obscured by the keyboard.", related: ["show-keyboard", "is-element-obscured"], platforms: ["ios", "android"], response: successOnlyResponse },
  "resize-viewport": { purpose: "Resize the viewport", when: "Testing responsive layouts at specific sizes", explanation: "Resizes the browser viewport to the given dimensions. Returns both the new and original viewport sizes.", related: ["reset-viewport", "get-viewport"] },
  "reset-viewport": { purpose: "Reset viewport to default", when: "Restoring the original device viewport size", explanation: "Resets the viewport to the device's default dimensions.", related: ["resize-viewport"] },
  "is-element-obscured": { purpose: "Check if element is obscured", when: "Before interacting with an element, checking if keyboard or other elements block it", explanation: "Returns whether the element is obscured, the reason, and a suggestion for how to unblock it (e.g., hide keyboard, scroll).", related: ["show-keyboard", "scroll2"], platforms: ["ios", "android"], response: successOnlyResponse },

  // --- Discovery ---
  discover: { purpose: "Discover devices on the network", when: "Starting a session — find available Kelpie devices via mDNS", explanation: "Broadcasts mDNS queries for _kelpie._tcp services and returns all discovered devices with their IDs, names, IPs, and capabilities. Alias: `devices`.", related: ["ping"] },
  ping: { purpose: "Ping a device", when: "Verifying a device is reachable before sending commands", explanation: "Sends a health check to the specified device and returns its status.", related: ["discover"] },
  pair: { purpose: "Pair the CLI with a device", when: "Before sending authenticated commands to a device for the first time, or after revoking a previous pairing", explanation: "Issues POST /v1/pair, polls /v1/pair/status until the on-device user approves, denies, or the request expires. Persistent-scope tokens are written to ~/.kelpie/tokens.json (mode 0600); session-scope tokens stay in process memory and are lost at CLI exit. Implicit pairing also runs automatically when any other command receives a 401.", errors: ["DEVICE_NOT_FOUND", "PAIR_DENIED", "PAIR_EXPIRED", "PAIR_NOT_FOUND"], related: ["discover", "ping"] },
  "report-issue": { purpose: "Store a structured automation failure report", when: "A command failed unexpectedly and you want the failure captured with params, diagnostics, and platform context", explanation: "Sends the report to the target device's report-issue endpoint and also stores a local copy under ~/.kelpie/feedback so recurring failure patterns can be summarized later.", related: ["feedback-summary", "get-capabilities"], response: reportIssueResponse },
  "feedback-summary": { purpose: "Summarize local automation feedback", when: "You want to see common failure categories, commands, or platforms from previously stored reports", explanation: "Reads locally stored feedback reports under ~/.kelpie/feedback and returns aggregate counts plus the most recent entries.", related: ["report-issue"], response: feedbackSummaryResponse },
  browser: { purpose: "Manage local macOS browser aliases", when: "You want to register, launch, inspect, or remove CLI-managed macOS browser instances on the local machine", explanation: "Provides local browser management commands backed by ~/.kelpie. These commands are separate from mDNS discovery and are intended for launching and reusing named local Kelpie macOS instances across multiple terminal sessions.", related: ["browser register", "browser launch", "browser list", "browser inspect", "browser remove"], platforms: ["macos"] },
  "browser register": { purpose: "Register a named local macOS browser alias", when: "You want a stable identifier for a local Kelpie.app instance before launching it", explanation: "Stores a named browser alias in ~/.kelpie, optionally with an explicit Kelpie.app path. Registration does not launch the app or reserve a port.", related: ["browser launch", "browser inspect", "browser remove"], platforms: ["macos"], response: successOnlyResponse },
  "browser launch": { purpose: "Launch a named local macOS browser instance", when: "You need a fresh Kelpie.app process for a specific local alias", explanation: "Resolves the alias, verifies Kelpie.app is installed, chooses a safe HTTP port if one is not provided, launches a new macOS app instance, and records the live port in ~/.kelpie so later CLI commands can target the alias directly.", errors: ["BROWSER_NOT_REGISTERED", "APP_NOT_INSTALLED", "BROWSER_LAUNCH_FAILED"], related: ["browser register", "browser list", "browser inspect"], platforms: ["macos"], response: successOnlyResponse },
  "browser list": { purpose: "List registered local macOS browser aliases", when: "You need to see which local aliases exist and whether they are currently reachable", explanation: "Lists all browser aliases stored in ~/.kelpie, including any saved runtime port and whether the local HTTP server is currently reachable.", related: ["browser inspect", "browser launch"], platforms: ["macos"], response: successOnlyResponse },
  "browser inspect": { purpose: "Inspect one local macOS browser alias", when: "You need the app path, saved runtime port, or reachability for a specific alias", explanation: "Returns the stored configuration and runtime state for one local browser alias.", related: ["browser list", "browser launch", "browser remove"], platforms: ["macos"], response: successOnlyResponse },
  "browser remove": { purpose: "Remove a local macOS browser alias", when: "A saved alias is no longer needed", explanation: "Deletes the alias and saved runtime state from ~/.kelpie. It does not terminate any running app process.", related: ["browser list", "browser register"], platforms: ["macos"], response: successOnlyResponse },

  // --- AI / Local Inference ---
  "ai catalog": { purpose: "List the approved on-device model catalog", when: "Inspecting which models a device can download and their RAM/disk/capability requirements", explanation: "Queries the device for the approved model catalog with download URLs and per-model metadata (size, min/recommended RAM, capabilities, quantization). Requires a HuggingFace token configured on the device.", errors: ["AUTH_REQUIRED", "AI_UNAVAILABLE", "PLATFORM_NOT_SUPPORTED"], related: ["ai fitness", "ai list", "ai pull"], platforms: ["ios", "android", "macos"], response: successOnlyResponse },
  "ai fitness": { purpose: "Score a model against a device's resources", when: "Deciding whether a catalog model will run well before downloading or loading it", explanation: "Evaluates a catalog model against the supplied RAM and free disk (in GB) and returns a fitness level (recommended, possible, not_recommended, no_storage) with an explanatory message.", errors: ["MISSING_PARAM", "AUTH_REQUIRED", "AI_UNAVAILABLE", "PLATFORM_NOT_SUPPORTED"], related: ["ai catalog", "ai load"], platforms: ["ios", "android", "macos"], response: successOnlyResponse },

  // --- Group ---
  "group navigate": { purpose: "Navigate all devices to a URL", when: "Testing the same page across multiple devices simultaneously", explanation: "Sends navigate to all matched devices in parallel. Returns per-device results.", related: ["group screenshot", "group click"] },
  "group screenshot": { purpose: "Screenshot all devices", when: "Capturing the visual state across all devices at once", explanation: "Takes screenshots on all matched devices in parallel and saves each to a file.", related: ["group navigate"] },
  "group click": { purpose: "Click on all devices", when: "Performing the same click action across all devices", explanation: "Clicks the element matching the selector on all matched devices.", related: ["group fill", "group navigate"] },
  "group fill": { purpose: "Fill on all devices", when: "Entering the same value into a form field across all devices", explanation: "Fills the element matching the selector with the given value on all devices.", related: ["group click"] },
};
