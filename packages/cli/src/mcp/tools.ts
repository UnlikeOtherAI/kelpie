import { z } from "zod";

// --- Shared schema fragments ---

const device = z.string().describe("Device ID, name, or IP address");
const selector = z.string().describe("CSS selector");
const url = z.string().describe("URL");
const timeout = z.number().optional().describe("Timeout in milliseconds");
const message = z.string().optional().describe("Optional message to show on device screen as a toast overlay while this action runs. Use this to narrate what you are doing, e.g. 'Clicking the login button' or 'Scrolling to pricing section'. The toast appears at the bottom of the viewport with a semi-transparent background.");

const filterProps = {
  platform: z.enum(["ios", "android"]).optional().describe("Filter by platform"),
  include: z.string().optional().describe("Comma-separated device IDs or names to include"),
  exclude: z.string().optional().describe("Comma-separated device IDs or names to exclude"),
};

// --- Tool definition types ---

export interface BrowserToolDef {
  name: string;
  description: string;
  method: string;
  schema: Record<string, z.ZodType>;
  bodyFromArgs: (args: Record<string, unknown>) => Record<string, unknown>;
}

export interface CliToolDef {
  name: string;
  description: string;
  method: string;
  kind: "group" | "smartQuery" | "discovery";
  schema: Record<string, z.ZodType>;
  bodyFromArgs: (args: Record<string, unknown>) => Record<string, unknown>;
}

function passthrough(args: Record<string, unknown>): Record<string, unknown> {
  const { device: _d, ...rest } = args;
  return rest;
}

function filterBody(args: Record<string, unknown>): Record<string, unknown> {
  const { platform: _p, include: _i, exclude: _e, ...rest } = args;
  return rest;
}

// --- Browser tool definitions (82 tools) ---

export const browserTools: BrowserToolDef[] = [
  // Navigation
  { name: "mollotov_navigate", description: "Navigate device browser to a URL", method: "navigate", schema: { device, url: url.describe("URL to navigate to"), message }, bodyFromArgs: passthrough },
  { name: "mollotov_back", description: "Go back in browser history", method: "back", schema: { device }, bodyFromArgs: passthrough },
  { name: "mollotov_forward", description: "Go forward in browser history", method: "forward", schema: { device }, bodyFromArgs: passthrough },
  { name: "mollotov_reload", description: "Reload the current page", method: "reload", schema: { device }, bodyFromArgs: passthrough },
  { name: "mollotov_get_current_url", description: "Get the current URL and page title", method: "getCurrentUrl", schema: { device }, bodyFromArgs: passthrough },

  // Screenshots
  { name: "mollotov_screenshot", description: "Take a screenshot of the device browser", method: "screenshot", schema: { device, fullPage: z.boolean().optional().describe("Capture full page"), format: z.enum(["png", "jpeg"]).optional().describe("Image format"), quality: z.number().optional().describe("JPEG quality 0-100") }, bodyFromArgs: passthrough },

  // DOM
  { name: "mollotov_get_dom", description: "Get the DOM tree as HTML", method: "getDOM", schema: { device, selector: selector.optional().describe("Root selector"), depth: z.number().optional().describe("Max depth") }, bodyFromArgs: passthrough },
  { name: "mollotov_query_selector", description: "Find a single element matching a CSS selector", method: "querySelector", schema: { device, selector }, bodyFromArgs: passthrough },
  { name: "mollotov_query_selector_all", description: "Find all elements matching a CSS selector", method: "querySelectorAll", schema: { device, selector }, bodyFromArgs: passthrough },
  { name: "mollotov_get_element_text", description: "Get text content of an element", method: "getElementText", schema: { device, selector }, bodyFromArgs: passthrough },
  { name: "mollotov_get_attributes", description: "Get all attributes of an element", method: "getAttributes", schema: { device, selector }, bodyFromArgs: passthrough },

  // Interaction
  { name: "mollotov_click", description: "Click an element. Shows a blue touch indicator at the element location.", method: "click", schema: { device, selector, timeout, message }, bodyFromArgs: passthrough },
  { name: "mollotov_tap", description: "Tap at specific coordinates. Shows a blue touch indicator at the tap point.", method: "tap", schema: { device, x: z.number().describe("X coordinate"), y: z.number().describe("Y coordinate"), message }, bodyFromArgs: passthrough },
  { name: "mollotov_fill", description: "Fill a form field with a value. Shows a touch indicator at the field.", method: "fill", schema: { device, selector, value: z.string().describe("Value to fill"), timeout, message }, bodyFromArgs: passthrough },
  { name: "mollotov_type", description: "Type text character by character", method: "type", schema: { device, selector: selector.optional(), text: z.string().describe("Text to type"), delay: z.number().optional().describe("Delay between keystrokes in ms") }, bodyFromArgs: passthrough },
  { name: "mollotov_select_option", description: "Select an option from a dropdown", method: "selectOption", schema: { device, selector, value: z.string().describe("Option value to select") }, bodyFromArgs: passthrough },
  { name: "mollotov_check", description: "Check a checkbox", method: "check", schema: { device, selector }, bodyFromArgs: passthrough },
  { name: "mollotov_uncheck", description: "Uncheck a checkbox", method: "uncheck", schema: { device, selector }, bodyFromArgs: passthrough },

  // Scrolling
  { name: "mollotov_scroll", description: "Scroll by pixel delta", method: "scroll", schema: { device, deltaX: z.number().describe("Horizontal pixels"), deltaY: z.number().describe("Vertical pixels"), message }, bodyFromArgs: passthrough },
  { name: "mollotov_scroll2", description: "Scroll to make an element visible (resolution-aware). Shows a touch indicator at the target element.", method: "scroll2", schema: { device, selector, position: z.enum(["top", "center", "bottom"]).optional().describe("Target position in viewport"), maxScrolls: z.number().optional().describe("Max scroll attempts"), message }, bodyFromArgs: passthrough },
  { name: "mollotov_scroll_to_top", description: "Scroll to the top of the page", method: "scrollToTop", schema: { device }, bodyFromArgs: passthrough },
  { name: "mollotov_scroll_to_bottom", description: "Scroll to the bottom of the page", method: "scrollToBottom", schema: { device }, bodyFromArgs: passthrough },

  // Viewport & Device
  { name: "mollotov_get_viewport", description: "Get viewport dimensions and device pixel ratio", method: "getViewport", schema: { device }, bodyFromArgs: passthrough },
  { name: "mollotov_get_device_info", description: "Get full device information", method: "getDeviceInfo", schema: { device }, bodyFromArgs: passthrough },
  { name: "mollotov_get_capabilities", description: "Get device capabilities", method: "getCapabilities", schema: { device }, bodyFromArgs: passthrough },

  // Wait
  { name: "mollotov_wait_for_element", description: "Wait for an element to appear or reach a state", method: "waitForElement", schema: { device, selector, timeout, state: z.enum(["attached", "visible", "hidden"]).optional().describe("Target state") }, bodyFromArgs: passthrough },
  { name: "mollotov_wait_for_navigation", description: "Wait for a navigation to complete", method: "waitForNavigation", schema: { device, timeout }, bodyFromArgs: passthrough },

  // Smart queries
  { name: "mollotov_find_element", description: "Find an element by text content or role", method: "findElement", schema: { device, text: z.string().describe("Text to search for"), role: z.string().optional().describe("ARIA role filter"), selector: selector.optional() }, bodyFromArgs: passthrough },
  { name: "mollotov_find_button", description: "Find a button by its text", method: "findButton", schema: { device, text: z.string().describe("Button text") }, bodyFromArgs: passthrough },
  { name: "mollotov_find_link", description: "Find a link by its text", method: "findLink", schema: { device, text: z.string().describe("Link text") }, bodyFromArgs: passthrough },
  { name: "mollotov_find_input", description: "Find an input field by label, placeholder, or name", method: "findInput", schema: { device, label: z.string().optional().describe("Input label"), placeholder: z.string().optional().describe("Input placeholder"), name: z.string().optional().describe("Input name attribute") }, bodyFromArgs: passthrough },

  // Evaluate
  { name: "mollotov_evaluate", description: "Evaluate JavaScript in the page context", method: "evaluate", schema: { device, expression: z.string().describe("JavaScript expression to evaluate"), message }, bodyFromArgs: passthrough },

  // Toast
  { name: "mollotov_toast", description: "Show a toast message overlay on the device screen. Use this to narrate actions, explain what you are doing, or communicate status to anyone watching the device. The message appears in a semi-transparent card at the bottom of the viewport for 3 seconds.", method: "toast", schema: { device, message: z.string().describe("Message to display on the device screen") }, bodyFromArgs: passthrough },

  // Console
  { name: "mollotov_get_console_messages", description: "Get browser console messages", method: "getConsoleMessages", schema: { device, level: z.enum(["log", "warn", "error", "info", "debug"]).optional().describe("Filter by level"), since: z.string().optional().describe("ISO timestamp cutoff"), limit: z.number().optional().describe("Max messages") }, bodyFromArgs: passthrough },
  { name: "mollotov_get_js_errors", description: "Get JavaScript errors from the page", method: "getJSErrors", schema: { device }, bodyFromArgs: passthrough },

  // Network
  { name: "mollotov_get_network_log", description: "Get network request log", method: "getNetworkLog", schema: { device, type: z.string().optional().describe("Filter by resource type"), status: z.enum(["success", "error", "pending"]).optional(), since: z.string().optional(), limit: z.number().optional() }, bodyFromArgs: passthrough },
  { name: "mollotov_get_resource_timeline", description: "Get resource loading timeline", method: "getResourceTimeline", schema: { device }, bodyFromArgs: passthrough },
  { name: "mollotov_clear_console", description: "Clear console messages", method: "clearConsole", schema: { device }, bodyFromArgs: passthrough },

  // Accessibility
  { name: "mollotov_get_accessibility_tree", description: "Get the accessibility tree for the page", method: "getAccessibilityTree", schema: { device, root: z.string().optional().describe("Root selector"), interactableOnly: z.boolean().optional(), maxDepth: z.number().optional() }, bodyFromArgs: passthrough },

  // Annotated screenshots
  { name: "mollotov_screenshot_annotated", description: "Take a screenshot with numbered element annotations", method: "screenshotAnnotated", schema: { device, fullPage: z.boolean().optional(), format: z.enum(["png", "jpeg"]).optional(), interactableOnly: z.boolean().optional(), labelStyle: z.enum(["numbered", "badge"]).optional() }, bodyFromArgs: passthrough },
  { name: "mollotov_click_annotation", description: "Click an annotated element by index", method: "clickAnnotation", schema: { device, index: z.number().describe("Annotation index") }, bodyFromArgs: passthrough },
  { name: "mollotov_fill_annotation", description: "Fill an annotated element by index", method: "fillAnnotation", schema: { device, index: z.number().describe("Annotation index"), value: z.string().describe("Value to fill") }, bodyFromArgs: passthrough },

  // Visible elements
  { name: "mollotov_get_visible_elements", description: "Get all visible elements in the viewport", method: "getVisibleElements", schema: { device, interactableOnly: z.boolean().optional(), includeText: z.boolean().optional() }, bodyFromArgs: passthrough },

  // Page text
  { name: "mollotov_get_page_text", description: "Extract readable text content from the page", method: "getPageText", schema: { device, mode: z.enum(["readable", "full", "markdown"]).optional().describe("Extraction mode"), selector: selector.optional() }, bodyFromArgs: passthrough },

  // Form state
  { name: "mollotov_get_form_state", description: "Get the state of all forms on the page", method: "getFormState", schema: { device, selector: selector.optional() }, bodyFromArgs: passthrough },

  // Dialogs
  { name: "mollotov_get_dialog", description: "Get the currently showing dialog", method: "getDialog", schema: { device }, bodyFromArgs: passthrough },
  { name: "mollotov_handle_dialog", description: "Accept or dismiss a dialog", method: "handleDialog", schema: { device, action: z.enum(["accept", "dismiss"]).describe("Dialog action"), promptText: z.string().optional().describe("Text for prompt dialogs") }, bodyFromArgs: passthrough },
  { name: "mollotov_set_dialog_auto_handler", description: "Set automatic dialog handling", method: "setDialogAutoHandler", schema: { device, enabled: z.boolean().describe("Enable auto-handling"), defaultAction: z.enum(["accept", "dismiss", "queue"]).optional(), promptText: z.string().optional() }, bodyFromArgs: passthrough },

  // Tabs
  { name: "mollotov_get_tabs", description: "Get all open tabs", method: "getTabs", schema: { device }, bodyFromArgs: passthrough },
  { name: "mollotov_new_tab", description: "Open a new tab", method: "newTab", schema: { device, url: url.optional().describe("URL to open in new tab") }, bodyFromArgs: passthrough },
  { name: "mollotov_switch_tab", description: "Switch to a specific tab", method: "switchTab", schema: { device, tabId: z.number().describe("Tab ID to switch to") }, bodyFromArgs: passthrough },
  { name: "mollotov_close_tab", description: "Close a tab", method: "closeTab", schema: { device, tabId: z.number().describe("Tab ID to close") }, bodyFromArgs: passthrough },

  // Iframes
  { name: "mollotov_get_iframes", description: "Get all iframes on the page", method: "getIframes", schema: { device }, bodyFromArgs: passthrough },
  { name: "mollotov_switch_to_iframe", description: "Switch context to an iframe", method: "switchToIframe", schema: { device, iframeId: z.number().optional().describe("Iframe ID"), selector: selector.optional() }, bodyFromArgs: passthrough },
  { name: "mollotov_switch_to_main", description: "Switch back to the main frame", method: "switchToMain", schema: { device }, bodyFromArgs: passthrough },
  { name: "mollotov_get_iframe_context", description: "Get current iframe context", method: "getIframeContext", schema: { device }, bodyFromArgs: passthrough },

  // Cookies
  { name: "mollotov_get_cookies", description: "Get cookies", method: "getCookies", schema: { device, url: url.optional().describe("Filter by URL"), name: z.string().optional().describe("Filter by name") }, bodyFromArgs: passthrough },
  { name: "mollotov_set_cookie", description: "Set a cookie", method: "setCookie", schema: { device, name: z.string().describe("Cookie name"), value: z.string().describe("Cookie value"), domain: z.string().optional(), path: z.string().optional(), httpOnly: z.boolean().optional(), secure: z.boolean().optional(), sameSite: z.string().optional(), expires: z.string().optional() }, bodyFromArgs: passthrough },
  { name: "mollotov_delete_cookies", description: "Delete cookies", method: "deleteCookies", schema: { device, name: z.string().optional().describe("Cookie name"), domain: z.string().optional(), deleteAll: z.boolean().optional() }, bodyFromArgs: passthrough },

  // Storage
  { name: "mollotov_get_storage", description: "Get localStorage or sessionStorage entries", method: "getStorage", schema: { device, type: z.enum(["local", "session"]).optional().describe("Storage type"), key: z.string().optional() }, bodyFromArgs: passthrough },
  { name: "mollotov_set_storage", description: "Set a storage entry", method: "setStorage", schema: { device, type: z.enum(["local", "session"]).optional(), key: z.string().describe("Storage key"), value: z.string().describe("Storage value") }, bodyFromArgs: passthrough },
  { name: "mollotov_clear_storage", description: "Clear storage", method: "clearStorage", schema: { device, type: z.enum(["local", "session", "both"]).optional() }, bodyFromArgs: passthrough },

  // Mutations
  { name: "mollotov_watch_mutations", description: "Start watching DOM mutations", method: "watchMutations", schema: { device, selector: selector.optional(), attributes: z.boolean().optional(), childList: z.boolean().optional(), subtree: z.boolean().optional(), characterData: z.boolean().optional() }, bodyFromArgs: passthrough },
  { name: "mollotov_get_mutations", description: "Get recorded DOM mutations", method: "getMutations", schema: { device, watchId: z.string().describe("Watch ID"), clear: z.boolean().optional() }, bodyFromArgs: passthrough },
  { name: "mollotov_stop_watching", description: "Stop watching DOM mutations", method: "stopWatching", schema: { device, watchId: z.string().describe("Watch ID") }, bodyFromArgs: passthrough },

  // Shadow DOM
  { name: "mollotov_query_shadow_dom", description: "Query inside a shadow DOM", method: "queryShadowDOM", schema: { device, hostSelector: z.string().describe("Shadow host selector"), shadowSelector: z.string().describe("Selector within shadow root"), pierce: z.boolean().optional() }, bodyFromArgs: passthrough },
  { name: "mollotov_get_shadow_roots", description: "Get all shadow root hosts on the page", method: "getShadowRoots", schema: { device }, bodyFromArgs: passthrough },

  // Clipboard
  { name: "mollotov_get_clipboard", description: "Get clipboard contents", method: "getClipboard", schema: { device }, bodyFromArgs: passthrough },
  { name: "mollotov_set_clipboard", description: "Set clipboard text", method: "setClipboard", schema: { device, text: z.string().describe("Text to copy to clipboard") }, bodyFromArgs: passthrough },

  // Geolocation
  { name: "mollotov_set_geolocation", description: "Override device geolocation", method: "setGeolocation", schema: { device, latitude: z.number().describe("Latitude"), longitude: z.number().describe("Longitude"), accuracy: z.number().optional().describe("Accuracy in meters") }, bodyFromArgs: passthrough },
  { name: "mollotov_clear_geolocation", description: "Clear geolocation override", method: "clearGeolocation", schema: { device }, bodyFromArgs: passthrough },

  // Request interception
  { name: "mollotov_set_request_interception", description: "Set request interception rules", method: "setRequestInterception", schema: { device, rules: z.array(z.object({ pattern: z.string(), action: z.enum(["block", "mock", "allow"]), mockResponse: z.object({ status: z.number(), headers: z.record(z.string()), body: z.string() }).optional() })).describe("Interception rules") }, bodyFromArgs: passthrough },
  { name: "mollotov_get_intercepted_requests", description: "Get intercepted requests", method: "getInterceptedRequests", schema: { device, since: z.string().optional(), limit: z.number().optional() }, bodyFromArgs: passthrough },
  { name: "mollotov_clear_request_interception", description: "Clear all interception rules", method: "clearRequestInterception", schema: { device }, bodyFromArgs: passthrough },

  // Keyboard & Viewport
  { name: "mollotov_show_keyboard", description: "Show the on-screen keyboard", method: "showKeyboard", schema: { device, selector: selector.optional(), keyboardType: z.enum(["default", "email", "number", "phone", "url"]).optional() }, bodyFromArgs: passthrough },
  { name: "mollotov_hide_keyboard", description: "Hide the on-screen keyboard", method: "hideKeyboard", schema: { device }, bodyFromArgs: passthrough },
  { name: "mollotov_get_keyboard_state", description: "Get keyboard visibility and state", method: "getKeyboardState", schema: { device }, bodyFromArgs: passthrough },
  { name: "mollotov_resize_viewport", description: "Resize the browser viewport", method: "resizeViewport", schema: { device, width: z.number().optional().describe("Viewport width"), height: z.number().optional().describe("Viewport height") }, bodyFromArgs: passthrough },
  { name: "mollotov_reset_viewport", description: "Reset viewport to device default", method: "resetViewport", schema: { device }, bodyFromArgs: passthrough },
  { name: "mollotov_is_element_obscured", description: "Check if an element is obscured by keyboard or other elements", method: "isElementObscured", schema: { device, selector }, bodyFromArgs: passthrough },

  // Orientation
  { name: "mollotov_set_orientation", description: "Force the device into portrait, landscape, or auto orientation. Useful for testing responsive layouts and orientation-dependent features.", method: "setOrientation", schema: { device, orientation: z.enum(["portrait", "landscape", "auto"]).describe("Target orientation. 'auto' unlocks rotation.") }, bodyFromArgs: passthrough },
  { name: "mollotov_get_orientation", description: "Get the current device orientation and lock state", method: "getOrientation", schema: { device }, bodyFromArgs: passthrough },

  // Safari Auth
  { name: "mollotov_safari_auth", description: "Open the current page (or a specific URL) in a Safari-backed authentication session. This lets the user authenticate using Safari's saved passwords and cookies, then syncs the session back into the browser. Use this when a login page requires credentials the user has saved in Safari, or when OAuth providers block in-app browsers. The user will see a Safari sheet and must complete authentication manually — the tool returns once they finish or cancel.", method: "safariAuth", schema: { device, url: url.optional().describe("URL to authenticate. Defaults to the current page URL."), message }, bodyFromArgs: passthrough },
];

// --- CLI tool definitions (20 tools) ---

export const cliTools: CliToolDef[] = [
  // Discovery
  { name: "mollotov_discover", description: "Discover devices on the local network via mDNS", method: "discover", kind: "discovery", schema: { timeout: z.number().optional().describe("Discovery timeout in ms (default 3000)") }, bodyFromArgs: filterBody },
  { name: "mollotov_list_devices", description: "List all discovered devices", method: "listDevices", kind: "discovery", schema: {}, bodyFromArgs: filterBody },

  // Group commands
  { name: "mollotov_group_navigate", description: "Navigate all (or filtered) devices to a URL", method: "navigate", kind: "group", schema: { ...filterProps, url: url.describe("URL to navigate to") }, bodyFromArgs: filterBody },
  { name: "mollotov_group_screenshot", description: "Take screenshots on all (or filtered) devices", method: "screenshot", kind: "group", schema: { ...filterProps }, bodyFromArgs: filterBody },
  { name: "mollotov_group_find_button", description: "Find a button across all devices", method: "findButton", kind: "smartQuery", schema: { ...filterProps, text: z.string().describe("Button text") }, bodyFromArgs: filterBody },
  { name: "mollotov_group_fill", description: "Fill a form field on all devices", method: "fill", kind: "group", schema: { ...filterProps, selector, value: z.string().describe("Value to fill") }, bodyFromArgs: filterBody },
  { name: "mollotov_group_click", description: "Click an element on all devices", method: "click", kind: "group", schema: { ...filterProps, selector }, bodyFromArgs: filterBody },
  { name: "mollotov_group_scroll2", description: "Resolution-aware scroll on all devices", method: "scroll2", kind: "group", schema: { ...filterProps, selector }, bodyFromArgs: filterBody },
  { name: "mollotov_group_find_element", description: "Find an element across all devices", method: "findElement", kind: "smartQuery", schema: { ...filterProps, text: z.string().describe("Text to search for") }, bodyFromArgs: filterBody },
  { name: "mollotov_group_find_link", description: "Find a link across all devices", method: "findLink", kind: "smartQuery", schema: { ...filterProps, text: z.string().describe("Link text") }, bodyFromArgs: filterBody },
  { name: "mollotov_group_find_input", description: "Find an input across all devices", method: "findInput", kind: "smartQuery", schema: { ...filterProps, label: z.string().optional().describe("Input label") }, bodyFromArgs: filterBody },
  { name: "mollotov_group_a11y", description: "Get accessibility tree from all devices", method: "getAccessibilityTree", kind: "group", schema: { ...filterProps }, bodyFromArgs: filterBody },
  { name: "mollotov_group_dom", description: "Get DOM from all devices", method: "getDOM", kind: "group", schema: { ...filterProps }, bodyFromArgs: filterBody },
  { name: "mollotov_group_eval", description: "Evaluate JavaScript on all devices", method: "evaluate", kind: "group", schema: { ...filterProps, expression: z.string().describe("JavaScript expression") }, bodyFromArgs: filterBody },
  { name: "mollotov_group_console", description: "Get console messages from all devices", method: "getConsoleMessages", kind: "group", schema: { ...filterProps }, bodyFromArgs: filterBody },
  { name: "mollotov_group_errors", description: "Get JavaScript errors from all devices", method: "getJSErrors", kind: "group", schema: { ...filterProps }, bodyFromArgs: filterBody },
  { name: "mollotov_group_form_state", description: "Get form state from all devices", method: "getFormState", kind: "group", schema: { ...filterProps }, bodyFromArgs: filterBody },
  { name: "mollotov_group_visible", description: "Get visible elements from all devices", method: "getVisibleElements", kind: "group", schema: { ...filterProps }, bodyFromArgs: filterBody },
  { name: "mollotov_group_keyboard_show", description: "Show keyboard on all devices", method: "showKeyboard", kind: "group", schema: { ...filterProps }, bodyFromArgs: filterBody },
  { name: "mollotov_group_keyboard_hide", description: "Hide keyboard on all devices", method: "hideKeyboard", kind: "group", schema: { ...filterProps }, bodyFromArgs: filterBody },
];
