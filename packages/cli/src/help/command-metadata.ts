export interface CommandHelp {
  purpose: string;
  when: string;
  explanation: string;
  errors?: string[];
  related?: string[];
}

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

  // --- Screenshots ---
  screenshot: { purpose: "Capture a screenshot", when: "Verifying visual state, debugging layout, or saving a snapshot", explanation: "Takes a PNG or JPEG screenshot of the visible viewport or full page. By default saves to a file (never returns base64 to LLMs). Use --output to control the save directory.", errors: ["TIMEOUT"], related: ["screenshot-annotated"] },

  // --- DOM ---
  "get-dom": { purpose: "Get DOM tree as HTML", when: "Inspecting page structure or extracting content", explanation: "Returns the full or partial DOM tree as HTML string. Use the selector parameter to scope to a subtree, and depth to limit nesting. For large pages, prefer get-page-text or get-visible-elements.", errors: ["ELEMENT_NOT_FOUND"], related: ["query-selector", "get-page-text", "get-visible-elements"] },
  "query-selector": { purpose: "Find a single element", when: "Checking if an element exists or getting its properties", explanation: "Runs querySelector with the given CSS selector. Returns element info (tag, text, classes, rect) if found.", errors: ["ELEMENT_NOT_FOUND"], related: ["query-selector-all", "find-element"] },
  "query-selector-all": { purpose: "Find all matching elements", when: "Counting elements or collecting a list", explanation: "Runs querySelectorAll with the given CSS selector. Returns all matching elements with their properties.", related: ["query-selector"] },
  "get-element-text": { purpose: "Get text content of an element", when: "Reading text from a specific element", explanation: "Returns the textContent of the element matching the selector.", errors: ["ELEMENT_NOT_FOUND"], related: ["get-page-text", "query-selector"] },
  "get-attributes": { purpose: "Get all attributes of an element", when: "Inspecting element properties like href, src, data-* attributes", explanation: "Returns a key-value map of all HTML attributes on the matched element.", errors: ["ELEMENT_NOT_FOUND"], related: ["query-selector"] },

  // --- Interaction ---
  click: { purpose: "Click an element", when: "Activating buttons, links, or interactive elements", explanation: "Finds the element by CSS selector, scrolls it into view if needed, and performs a click. Returns the element tag and text.", errors: ["ELEMENT_NOT_FOUND", "ELEMENT_NOT_VISIBLE", "TIMEOUT"], related: ["tap", "find-button", "click-annotation"] },
  tap: { purpose: "Tap at coordinates", when: "Clicking at a specific screen position rather than an element", explanation: "Performs a tap/click at the given x,y coordinates relative to the viewport. Use when you know exact coordinates from an annotated screenshot.", errors: ["TIMEOUT"], related: ["click", "click-annotation"] },
  fill: { purpose: "Fill a form field", when: "Entering text into inputs, textareas, or contenteditable elements", explanation: "Clears the current value and sets the new value. The element must be editable. For character-by-character typing, use the type command instead.", errors: ["ELEMENT_NOT_FOUND", "ELEMENT_NOT_VISIBLE", "TIMEOUT"], related: ["type", "find-input", "fill-annotation", "get-form-state"] },
  type: { purpose: "Type text character by character", when: "Simulating real typing with keypress events, or typing into focused elements", explanation: "Types text one character at a time with optional delay between keystrokes. If selector is provided, focuses that element first. Useful for triggering autocomplete or real-time validation.", errors: ["ELEMENT_NOT_FOUND", "TIMEOUT"], related: ["fill"] },
  "select-option": { purpose: "Select a dropdown option", when: "Choosing from a <select> element", explanation: "Selects the option with the matching value attribute from a <select> element.", errors: ["ELEMENT_NOT_FOUND"], related: ["fill", "get-form-state"] },
  check: { purpose: "Check a checkbox", when: "Enabling a checkbox option", explanation: "Checks a checkbox element. No-op if already checked.", errors: ["ELEMENT_NOT_FOUND"], related: ["uncheck", "get-form-state"] },
  uncheck: { purpose: "Uncheck a checkbox", when: "Disabling a checkbox option", explanation: "Unchecks a checkbox element. No-op if already unchecked.", errors: ["ELEMENT_NOT_FOUND"], related: ["check"] },

  // --- Scrolling ---
  scroll: { purpose: "Scroll by pixel offset", when: "Scrolling a known number of pixels", explanation: "Scrolls the page by the given pixel deltas. Positive deltaY scrolls down, positive deltaX scrolls right.", related: ["scroll2", "scroll-to-top", "scroll-to-bottom"] },
  scroll2: { purpose: "Scroll until element is visible (resolution-aware)", when: "You need to interact with an element below the fold", explanation: "Scrolls the page until the target element is visible in the viewport. Unlike regular scroll, it adapts scroll distance to the device's screen size — a phone needs more scroll steps than a tablet. Use this when you need to bring an element into view before clicking or reading it.", errors: ["ELEMENT_NOT_FOUND", "TIMEOUT"], related: ["scroll", "click", "is-element-obscured"] },
  "scroll-to-top": { purpose: "Scroll to page top", when: "Returning to the beginning of the page", explanation: "Scrolls to the top of the page (scrollY = 0).", related: ["scroll-to-bottom", "scroll"] },
  "scroll-to-bottom": { purpose: "Scroll to page bottom", when: "Reaching the end of the page", explanation: "Scrolls to the bottom of the page.", related: ["scroll-to-top", "scroll"] },
  "scroll-to": { purpose: "Scroll to absolute pixel offset", when: "Debugging layout or navigating to a known Y position", explanation: "Scrolls the page so window.scrollY equals the given --y value. Optional --x offset (default 0). Works while the macOS 3D inspector is active — the inspector state is synced so exit restores the new position.", related: ["scroll", "scroll-to-top", "scroll-to-bottom"] },

  // --- Viewport & Device ---
  "get-viewport": { purpose: "Get viewport dimensions", when: "Checking screen size or device pixel ratio", explanation: "Returns viewport width, height, devicePixelRatio, platform, device name, and orientation.", related: ["resize-viewport", "get-device-info"] },
  "get-device-info": { purpose: "Get full device information", when: "Understanding device capabilities and hardware", explanation: "Returns comprehensive device info including OS version, browser engine, display properties, and network info.", related: ["get-viewport", "get-capabilities"] },
  "get-capabilities": { purpose: "Get device capabilities", when: "Checking which features the device supports", explanation: "Returns a map of capabilities like CDP support, keyboard control, geolocation override, etc.", related: ["get-device-info"] },

  // --- Wait ---
  "wait-for-element": { purpose: "Wait for an element to appear", when: "Content loads asynchronously or appears after an action", explanation: "Waits until an element matching the selector reaches the specified state (attached, visible, or hidden). Returns the element and how long the wait took.", errors: ["TIMEOUT"], related: ["wait-for-navigation"] },
  "wait-for-navigation": { purpose: "Wait for navigation to complete", when: "After triggering a navigation (e.g., form submit) and waiting for the new page", explanation: "Waits for the current navigation to finish loading.", errors: ["TIMEOUT"], related: ["navigate", "wait-for-element"] },

  // --- Smart Queries ---
  "find-element": { purpose: "Find element by text or role", when: "Searching for an element when you don't know the CSS selector", explanation: "Searches the page for an element containing the given text, optionally filtered by ARIA role. Returns the element info and a CSS selector you can use for subsequent commands.", related: ["find-button", "find-link", "find-input", "query-selector"] },
  "find-button": { purpose: "Find a button by text", when: "Looking for a button to click", explanation: "Searches for a button (button, [role=button], input[type=submit]) matching the given text. Returns element info and selector.", related: ["click", "find-element"] },
  "find-link": { purpose: "Find a link by text", when: "Looking for a link to navigate", explanation: "Searches for an anchor element matching the given text. Returns element info and selector.", related: ["click", "find-element"] },
  "find-input": { purpose: "Find an input by label", when: "Looking for a form field to fill", explanation: "Searches for an input field by its label text, placeholder, or name attribute. Returns element info including type and a selector.", related: ["fill", "find-element", "get-form-state"] },

  // --- Evaluate ---
  evaluate: { purpose: "Run JavaScript in the page", when: "Custom logic, extracting data, or manipulating the DOM directly", explanation: "Evaluates a JavaScript expression in the page context and returns the result. The expression runs in the page's global scope, not in Node.js.", errors: ["EVAL_ERROR"], related: ["get-dom", "get-page-text"] },

  // --- Console & DevTools ---
  "get-console-messages": { purpose: "Get console messages", when: "Debugging or monitoring page behavior", explanation: "Returns console messages (log, warn, error, info, debug) from the page. Filter by level or since a timestamp.", related: ["get-js-errors", "clear-console"] },
  "get-js-errors": { purpose: "Get JavaScript errors", when: "Checking for runtime errors on the page", explanation: "Returns only error-level console messages and uncaught exceptions.", related: ["get-console-messages"] },
  "clear-console": { purpose: "Clear console messages", when: "Resetting the console before monitoring a specific action", explanation: "Clears all stored console messages.", related: ["get-console-messages"] },
  "get-network-log": { purpose: "Get network requests", when: "Debugging API calls, checking request/response data", explanation: "Returns the network request log with URL, method, status, size, and timing information. Filter by type (xhr, script, image) or status.", related: ["get-resource-timeline", "set-request-interception"] },
  "get-resource-timeline": { purpose: "Get resource loading timeline", when: "Analyzing page load performance", explanation: "Returns the full resource loading timeline including DOMContentLoaded, load event times, and individual resource start/end times.", related: ["get-network-log"] },

  // --- LLM: Accessibility & Visual ---
  "get-accessibility-tree": { purpose: "Get the accessibility tree", when: "Understanding page structure semantically, or when CSS selectors are unreliable", explanation: "Returns the accessibility tree with roles, names, values, and states. This is often the best way for an LLM to understand what's on the page. Use interactableOnly to filter to actionable elements.", related: ["get-visible-elements", "get-dom"] },
  "screenshot-annotated": { purpose: "Screenshot with numbered annotations", when: "Visually identifying elements to interact with", explanation: "Takes a screenshot with numbered labels overlaid on interactive elements. Each annotation has an index you can pass to click-annotation or fill-annotation.", related: ["click-annotation", "fill-annotation", "screenshot"] },
  "click-annotation": { purpose: "Click an annotated element by index", when: "After taking an annotated screenshot, clicking a numbered element", explanation: "Clicks the element at the given annotation index from the most recent annotated screenshot.", errors: ["ELEMENT_NOT_FOUND"], related: ["screenshot-annotated", "fill-annotation"] },
  "fill-annotation": { purpose: "Fill an annotated element by index", when: "After taking an annotated screenshot, filling a numbered input", explanation: "Fills the input at the given annotation index with the provided value.", errors: ["ELEMENT_NOT_FOUND"], related: ["screenshot-annotated", "click-annotation"] },
  "get-visible-elements": { purpose: "Get all visible elements", when: "Getting a concise list of what's currently on screen", explanation: "Returns all elements currently visible in the viewport with their positions. Use interactableOnly to filter to clickable/fillable elements.", related: ["get-accessibility-tree", "get-dom"] },
  "get-page-text": { purpose: "Extract readable text from the page", when: "Reading article content, form labels, or any text on the page", explanation: "Extracts text content from the page in readable, full, or markdown mode. The readable mode strips navigation and ads. This is usually the best way for an LLM to read page content.", related: ["get-dom", "get-element-text"] },
  "get-form-state": { purpose: "Get state of all forms", when: "Understanding form fields, their values, and validation status", explanation: "Returns all forms on the page with their fields, current values, validation state, and submit button info. Use this before filling forms to understand what needs to be filled.", related: ["fill", "find-input", "check"] },

  // --- Dialogs ---
  "get-dialog": { purpose: "Get current dialog", when: "Checking if a dialog (alert, confirm, prompt) is showing", explanation: "Returns info about any currently showing JavaScript dialog.", related: ["handle-dialog", "set-dialog-auto-handler"] },
  "handle-dialog": { purpose: "Accept or dismiss a dialog", when: "Responding to an alert, confirm, or prompt dialog", explanation: "Accepts or dismisses the current dialog. For prompt dialogs, provide promptText.", errors: ["NO_DIALOG"], related: ["get-dialog"] },
  "set-dialog-auto-handler": { purpose: "Auto-handle dialogs", when: "Dialogs interrupt your workflow and you want them handled automatically", explanation: "Enables automatic handling of JavaScript dialogs as they appear.", related: ["get-dialog", "handle-dialog"] },

  // --- Tabs ---
  "get-tabs": { purpose: "Get all open tabs", when: "Listing browser tabs or finding a specific one", explanation: "Returns all open tabs with their IDs, URLs, titles, and which is active.", related: ["new-tab", "switch-tab", "close-tab"] },
  "new-tab": { purpose: "Open a new tab", when: "Opening a URL in a new tab", explanation: "Opens a new browser tab, optionally navigating to a URL.", related: ["get-tabs", "switch-tab"] },
  "switch-tab": { purpose: "Switch to a tab", when: "Changing focus to a different tab", explanation: "Switches the active tab to the one with the given tab ID.", errors: ["TAB_NOT_FOUND"], related: ["get-tabs"] },
  "close-tab": { purpose: "Close a tab", when: "Cleaning up tabs you no longer need", explanation: "Closes the tab with the given ID.", errors: ["TAB_NOT_FOUND"], related: ["get-tabs"] },

  // --- Iframes ---
  "get-iframes": { purpose: "List all iframes", when: "Finding iframes on the page to interact with their content", explanation: "Returns all iframes with their src, name, position, and whether they're cross-origin.", related: ["switch-to-iframe", "get-iframe-context"] },
  "switch-to-iframe": { purpose: "Enter an iframe context", when: "You need to interact with content inside an iframe", explanation: "Switches the execution context into the specified iframe. All subsequent commands operate within the iframe until you switch-to-main.", related: ["switch-to-main", "get-iframes"] },
  "switch-to-main": { purpose: "Exit iframe context", when: "Returning to the main page after working in an iframe", explanation: "Switches back to the main frame context.", related: ["switch-to-iframe"] },
  "get-iframe-context": { purpose: "Check current frame context", when: "Verifying whether you're in the main frame or an iframe", explanation: "Returns the current frame context (main or iframe info).", related: ["switch-to-iframe", "switch-to-main"] },

  // --- Cookies ---
  "get-cookies": { purpose: "Get cookies", when: "Inspecting auth tokens, session cookies, or preferences", explanation: "Returns cookies, optionally filtered by URL or name.", related: ["set-cookie", "delete-cookies"] },
  "set-cookie": { purpose: "Set a cookie", when: "Setting auth tokens, locale preferences, or test data", explanation: "Sets a cookie with the given name, value, and optional properties (domain, path, secure, etc).", related: ["get-cookies", "delete-cookies"] },
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
  "set-geolocation": { purpose: "Override geolocation", when: "Testing location-based features with specific coordinates", explanation: "Overrides the device's geolocation to the given latitude and longitude.", errors: ["PLATFORM_NOT_SUPPORTED"], related: ["clear-geolocation"] },
  "clear-geolocation": { purpose: "Remove geolocation override", when: "Restoring real device location", explanation: "Removes the geolocation override, restoring the device's actual location.", related: ["set-geolocation"] },

  // --- Request Interception ---
  "set-request-interception": { purpose: "Intercept network requests", when: "Blocking ads, mocking API responses, or testing error handling", explanation: "Sets rules to intercept network requests. Each rule matches a URL pattern and can block, mock, or allow the request.", errors: ["PLATFORM_NOT_SUPPORTED"], related: ["get-intercepted-requests", "clear-request-interception"] },
  "get-intercepted-requests": { purpose: "Get intercepted requests", when: "Checking which requests were caught by interception rules", explanation: "Returns requests that matched interception rules.", related: ["set-request-interception"] },
  "clear-request-interception": { purpose: "Remove interception rules", when: "Done testing with request interception", explanation: "Clears all active interception rules.", related: ["set-request-interception"] },

  // --- Keyboard & Viewport ---
  "show-keyboard": { purpose: "Show on-screen keyboard", when: "Testing keyboard interaction or form input on mobile", explanation: "Shows the on-screen keyboard, optionally focusing a specific element. Returns keyboard height and visible viewport dimensions.", related: ["hide-keyboard", "get-keyboard-state", "is-element-obscured"] },
  "hide-keyboard": { purpose: "Hide on-screen keyboard", when: "Dismissing the keyboard to interact with elements behind it", explanation: "Hides the on-screen keyboard and returns the restored viewport dimensions.", related: ["show-keyboard"] },
  "get-keyboard-state": { purpose: "Get keyboard state", when: "Checking if keyboard is visible and what element has focus", explanation: "Returns keyboard visibility, height, type, and info about the focused element including whether it's obscured by the keyboard.", related: ["show-keyboard", "is-element-obscured"] },
  "resize-viewport": { purpose: "Resize the viewport", when: "Testing responsive layouts at specific sizes", explanation: "Resizes the browser viewport to the given dimensions. Returns both the new and original viewport sizes.", related: ["reset-viewport", "get-viewport"] },
  "reset-viewport": { purpose: "Reset viewport to default", when: "Restoring the original device viewport size", explanation: "Resets the viewport to the device's default dimensions.", related: ["resize-viewport"] },
  "is-element-obscured": { purpose: "Check if element is obscured", when: "Before interacting with an element, checking if keyboard or other elements block it", explanation: "Returns whether the element is obscured, the reason, and a suggestion for how to unblock it (e.g., hide keyboard, scroll).", related: ["show-keyboard", "scroll2"] },

  // --- Discovery ---
  discover: { purpose: "Discover devices on the network", when: "Starting a session — find available Kelpie devices via mDNS", explanation: "Broadcasts mDNS queries for _kelpie._tcp services and returns all discovered devices with their IDs, names, IPs, and capabilities.", related: ["devices", "ping"] },
  devices: { purpose: "List known devices", when: "Checking which devices have been discovered", explanation: "Lists all devices currently in the local registry (from previous discover calls).", related: ["discover", "ping"] },
  ping: { purpose: "Ping a device", when: "Verifying a device is reachable before sending commands", explanation: "Sends a health check to the specified device and returns its status.", related: ["discover", "devices"] },
  browser: { purpose: "Manage local macOS browser aliases", when: "You want to register, launch, inspect, or remove CLI-managed macOS browser instances on the local machine", explanation: "Provides local browser management commands backed by ~/.kelpie. These commands are separate from mDNS discovery and are intended for launching and reusing named local Kelpie macOS instances across multiple terminal sessions.", related: ["browser register", "browser launch", "browser list", "browser inspect", "browser remove"] },
  "browser register": { purpose: "Register a named local macOS browser alias", when: "You want a stable identifier for a local Kelpie.app instance before launching it", explanation: "Stores a named browser alias in ~/.kelpie, optionally with an explicit Kelpie.app path. Registration does not launch the app or reserve a port.", related: ["browser launch", "browser inspect", "browser remove"] },
  "browser launch": { purpose: "Launch a named local macOS browser instance", when: "You need a fresh Kelpie.app process for a specific local alias", explanation: "Resolves the alias, verifies Kelpie.app is installed, chooses a safe HTTP port if one is not provided, launches a new macOS app instance, and records the live port in ~/.kelpie so later CLI commands can target the alias directly.", errors: ["BROWSER_NOT_REGISTERED", "APP_NOT_INSTALLED", "BROWSER_LAUNCH_FAILED"], related: ["browser register", "browser list", "browser inspect"] },
  "browser list": { purpose: "List registered local macOS browser aliases", when: "You need to see which local aliases exist and whether they are currently reachable", explanation: "Lists all browser aliases stored in ~/.kelpie, including any saved runtime port and whether the local HTTP server is currently reachable.", related: ["browser inspect", "browser launch"] },
  "browser inspect": { purpose: "Inspect one local macOS browser alias", when: "You need the app path, saved runtime port, or reachability for a specific alias", explanation: "Returns the stored configuration and runtime state for one local browser alias.", related: ["browser list", "browser launch", "browser remove"] },
  "browser remove": { purpose: "Remove a local macOS browser alias", when: "A saved alias is no longer needed", explanation: "Deletes the alias and saved runtime state from ~/.kelpie. It does not terminate any running app process.", related: ["browser list", "browser register"] },

  // --- Group ---
  "group navigate": { purpose: "Navigate all devices to a URL", when: "Testing the same page across multiple devices simultaneously", explanation: "Sends navigate to all matched devices in parallel. Returns per-device results.", related: ["group screenshot", "group click"] },
  "group screenshot": { purpose: "Screenshot all devices", when: "Capturing the visual state across all devices at once", explanation: "Takes screenshots on all matched devices in parallel and saves each to a file.", related: ["group navigate"] },
  "group click": { purpose: "Click on all devices", when: "Performing the same click action across all devices", explanation: "Clicks the element matching the selector on all matched devices.", related: ["group fill", "group navigate"] },
  "group fill": { purpose: "Fill on all devices", when: "Entering the same value into a form field across all devices", explanation: "Fills the element matching the selector with the given value on all devices.", related: ["group click"] },
};
