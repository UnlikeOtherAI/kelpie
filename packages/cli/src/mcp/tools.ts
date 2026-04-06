import { z } from "zod";

const platforms = ["ios", "android", "macos", "linux", "windows"] as const;

// --- Shared schema fragments ---

const device = z.string().describe("Device ID, name, or IP address");
const selector = z.string().describe("CSS selector");
const url = z.string().describe("URL");
const timeout = z.number().optional().describe("Timeout in milliseconds");
const message = z.string().optional().describe("Optional message to show on device screen as a toast overlay while this action runs. Use this to narrate what you are doing, e.g. 'Clicking the login button' or 'Scrolling to pricing section'. The toast appears at the bottom of the viewport with a semi-transparent background.");
const point = z.object({
  x: z.number().describe("Viewport X coordinate"),
  y: z.number().describe("Viewport Y coordinate"),
});

const filterProps = {
  platform: z.enum(platforms).optional().describe("Filter by platform"),
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

// --- Browser tool definitions (84 tools) ---

export const browserTools: BrowserToolDef[] = [
  // Navigation
  { name: "kelpie_navigate", description: "Navigate device browser to a URL", method: "navigate", schema: { device, url: url.describe("URL to navigate to"), message }, bodyFromArgs: passthrough },
  { name: "kelpie_back", description: "Go back in browser history", method: "back", schema: { device }, bodyFromArgs: passthrough },
  { name: "kelpie_forward", description: "Go forward in browser history", method: "forward", schema: { device }, bodyFromArgs: passthrough },
  { name: "kelpie_reload", description: "Reload the current page", method: "reload", schema: { device }, bodyFromArgs: passthrough },
  { name: "kelpie_get_current_url", description: "Get the current URL and page title", method: "getCurrentUrl", schema: { device }, bodyFromArgs: passthrough },
  { name: "kelpie_set_home", description: "Set the device home page URL. Persisted across app restarts.", method: "setHome", schema: { device, url: url.describe("Home page URL") }, bodyFromArgs: passthrough },
  { name: "kelpie_get_home", description: "Get the device home page URL", method: "getHome", schema: { device }, bodyFromArgs: passthrough },

  // Debug
  { name: "kelpie_debug_screens", description: "Get screen/scene/external display diagnostics. Shows UIScreen count, connected scenes, and external display manager state.", method: "debugScreens", schema: { device }, bodyFromArgs: passthrough },
  { name: "kelpie_set_debug_overlay", description: "Enable or disable the on-screen debug overlay showing screen/scene/connection info", method: "setDebugOverlay", schema: { device, enabled: z.boolean().describe("Enable or disable the debug overlay") }, bodyFromArgs: passthrough },
  { name: "kelpie_get_debug_overlay", description: "Get current debug overlay state", method: "getDebugOverlay", schema: { device }, bodyFromArgs: passthrough },

  // Screenshots
  { name: "kelpie_screenshot", description: "Take a screenshot of the device browser", method: "screenshot", schema: { device, fullPage: z.boolean().optional().describe("Capture full page"), format: z.enum(["png", "jpeg"]).optional().describe("Image format"), quality: z.number().optional().describe("JPEG quality 0-100") }, bodyFromArgs: passthrough },

  // DOM
  { name: "kelpie_get_dom", description: "Get the DOM tree as HTML", method: "getDOM", schema: { device, selector: selector.optional().describe("Root selector"), depth: z.number().optional().describe("Max depth") }, bodyFromArgs: passthrough },
  { name: "kelpie_query_selector", description: "Find a single element matching a CSS selector", method: "querySelector", schema: { device, selector }, bodyFromArgs: passthrough },
  { name: "kelpie_query_selector_all", description: "Find all elements matching a CSS selector", method: "querySelectorAll", schema: { device, selector }, bodyFromArgs: passthrough },
  { name: "kelpie_get_element_text", description: "Get text content of an element", method: "getElementText", schema: { device, selector }, bodyFromArgs: passthrough },
  { name: "kelpie_get_attributes", description: "Get all attributes of an element", method: "getAttributes", schema: { device, selector }, bodyFromArgs: passthrough },

  // Interaction
  { name: "kelpie_click", description: "Click an element. Shows a blue touch indicator at the element location.", method: "click", schema: { device, selector, timeout, message }, bodyFromArgs: passthrough },
  { name: "kelpie_tap", description: "Tap at specific coordinates. Shows a blue touch indicator at the tap point.", method: "tap", schema: { device, x: z.number().describe("X coordinate"), y: z.number().describe("Y coordinate"), message }, bodyFromArgs: passthrough },
  { name: "kelpie_fill", description: "Fill a form field with a value. Shows a touch indicator at the field.", method: "fill", schema: { device, selector, value: z.string().describe("Value to fill"), mode: z.enum(["instant", "typing"]).optional().describe("Fill mode: instant (default) sets value immediately, typing types character by character"), delay: z.number().optional().describe("Delay between keystrokes in ms when mode is typing (default 50)"), timeout, message }, bodyFromArgs: passthrough },
  { name: "kelpie_type", description: "Type text character by character", method: "type", schema: { device, selector: selector.optional(), text: z.string().describe("Text to type"), delay: z.number().optional().describe("Delay between keystrokes in ms") }, bodyFromArgs: passthrough },
  { name: "kelpie_select_option", description: "Select an option from a dropdown", method: "selectOption", schema: { device, selector, value: z.string().describe("Option value to select") }, bodyFromArgs: passthrough },
  { name: "kelpie_check", description: "Check a checkbox", method: "check", schema: { device, selector }, bodyFromArgs: passthrough },
  { name: "kelpie_uncheck", description: "Uncheck a checkbox", method: "uncheck", schema: { device, selector }, bodyFromArgs: passthrough },
  { name: "kelpie_swipe", description: "Swipe between two viewport coordinates with a visible trail overlay", method: "swipe", schema: { device, from: point.describe("Swipe start point"), to: point.describe("Swipe end point"), durationMs: z.number().optional().describe("Swipe duration in milliseconds"), steps: z.number().optional().describe("Interpolation steps for the swipe"), color: z.string().optional().describe("Swipe overlay color, e.g. #3B82F6") }, bodyFromArgs: passthrough },
  { name: "kelpie_show_commentary", description: "Show a commentary text pill overlay inside the page viewport", method: "showCommentary", schema: { device, text: z.string().describe("Commentary text to display"), durationMs: z.number().optional().describe("How long to show the commentary. Use 0 to keep it visible until hidden."), position: z.enum(["top", "center", "bottom"]).optional().describe("Commentary position") }, bodyFromArgs: passthrough },
  { name: "kelpie_hide_commentary", description: "Hide the active commentary overlay", method: "hideCommentary", schema: { device }, bodyFromArgs: passthrough },
  { name: "kelpie_highlight", description: "Draw a colored highlight ring around an element", method: "highlight", schema: { device, selector, color: z.string().optional().describe("Highlight color, e.g. #EF4444"), thickness: z.number().optional().describe("Highlight stroke width in pixels"), padding: z.number().optional().describe("Padding around the highlighted element in pixels"), animation: z.enum(["appear", "draw"]).optional().describe("Highlight animation style"), durationMs: z.number().optional().describe("How long to keep the highlight visible. Use 0 to keep it until hidden.") }, bodyFromArgs: passthrough },
  { name: "kelpie_hide_highlight", description: "Hide the active highlight overlay", method: "hideHighlight", schema: { device }, bodyFromArgs: passthrough },
  { name: "kelpie_play_script", description: "Run a timed recording script made of navigation, interaction, overlay, and wait actions", method: "playScript", schema: { device, actions: z.array(z.record(z.string(), z.any())).describe("Ordered list of script action objects"), overlayColor: z.string().optional().describe("Default overlay color for taps, typing, and swipes"), defaultWaitBetweenActions: z.number().optional().describe("Implicit wait inserted between actions in milliseconds"), continueOnError: z.boolean().optional().describe("Continue script playback after non-fatal action failures") }, bodyFromArgs: passthrough },
  { name: "kelpie_abort_script", description: "Abort the currently running recording script", method: "abortScript", schema: { device }, bodyFromArgs: passthrough },
  { name: "kelpie_get_script_status", description: "Get the current recording script playback status", method: "getScriptStatus", schema: { device }, bodyFromArgs: passthrough },

  // Scrolling
  { name: "kelpie_scroll", description: "Scroll by pixel delta", method: "scroll", schema: { device, deltaX: z.number().describe("Horizontal pixels"), deltaY: z.number().describe("Vertical pixels"), message }, bodyFromArgs: passthrough },
  { name: "kelpie_scroll2", description: "Scroll to make an element visible (resolution-aware). Shows a touch indicator at the target element.", method: "scroll2", schema: { device, selector, position: z.enum(["top", "center", "bottom"]).optional().describe("Target position in viewport"), maxScrolls: z.number().optional().describe("Max scroll attempts"), message }, bodyFromArgs: passthrough },
  { name: "kelpie_scroll_to_top", description: "Scroll to the top of the page", method: "scrollToTop", schema: { device }, bodyFromArgs: passthrough },
  { name: "kelpie_scroll_to_bottom", description: "Scroll to the bottom of the page", method: "scrollToBottom", schema: { device }, bodyFromArgs: passthrough },
  { name: "kelpie_scroll_to_y", description: "Scroll to an absolute pixel offset. Works in 3D inspector mode on macOS.", method: "scrollToY", schema: { device, y: z.number().describe("Vertical pixel offset from top"), x: z.number().optional().describe("Horizontal pixel offset from left (default 0)"), message }, bodyFromArgs: passthrough },

  // Viewport & Device
  { name: "kelpie_get_viewport", description: "Get viewport dimensions and device pixel ratio", method: "getViewport", schema: { device }, bodyFromArgs: passthrough },
  { name: "kelpie_get_viewport_presets", description: "List named viewport presets available for the current device or window geometry. Linux does not support viewport presets yet.", method: "getViewportPresets", schema: { device }, bodyFromArgs: passthrough },
  { name: "kelpie_get_device_info", description: "Get full device information", method: "getDeviceInfo", schema: { device }, bodyFromArgs: passthrough },
  { name: "kelpie_get_capabilities", description: "Get device capabilities", method: "getCapabilities", schema: { device }, bodyFromArgs: passthrough },

  // Wait
  { name: "kelpie_wait_for_element", description: "Wait for an element to appear or reach a state", method: "waitForElement", schema: { device, selector, timeout, state: z.enum(["attached", "visible", "hidden"]).optional().describe("Target state") }, bodyFromArgs: passthrough },
  { name: "kelpie_wait_for_navigation", description: "Wait for a navigation to complete", method: "waitForNavigation", schema: { device, timeout }, bodyFromArgs: passthrough },

  // Smart queries
  { name: "kelpie_find_element", description: "Find an element by text content or role", method: "findElement", schema: { device, text: z.string().describe("Text to search for"), role: z.string().optional().describe("ARIA role filter"), selector: selector.optional() }, bodyFromArgs: passthrough },
  { name: "kelpie_find_button", description: "Find a button by its text", method: "findButton", schema: { device, text: z.string().describe("Button text") }, bodyFromArgs: passthrough },
  { name: "kelpie_find_link", description: "Find a link by its text", method: "findLink", schema: { device, text: z.string().describe("Link text") }, bodyFromArgs: passthrough },
  { name: "kelpie_find_input", description: "Find an input field by label, placeholder, or name", method: "findInput", schema: { device, label: z.string().optional().describe("Input label"), placeholder: z.string().optional().describe("Input placeholder"), name: z.string().optional().describe("Input name attribute") }, bodyFromArgs: passthrough },

  // Evaluate
  { name: "kelpie_evaluate", description: "Evaluate JavaScript in the page context", method: "evaluate", schema: { device, expression: z.string().describe("JavaScript expression to evaluate"), message }, bodyFromArgs: passthrough },

  // Toast
  { name: "kelpie_toast", description: "Show a toast message overlay on the device screen. Use this to narrate actions, explain what you are doing, or communicate status to anyone watching the device. The message appears in a semi-transparent card at the bottom of the viewport for 3 seconds.", method: "toast", schema: { device, message: z.string().describe("Message to display on the device screen") }, bodyFromArgs: passthrough },

  // Console
  { name: "kelpie_get_console_messages", description: "Get browser console messages", method: "getConsoleMessages", schema: { device, level: z.enum(["log", "warn", "error", "info", "debug"]).optional().describe("Filter by level"), since: z.string().optional().describe("ISO timestamp cutoff"), limit: z.number().optional().describe("Max messages") }, bodyFromArgs: passthrough },
  { name: "kelpie_get_js_errors", description: "Get JavaScript errors from the page", method: "getJSErrors", schema: { device }, bodyFromArgs: passthrough },

  // Network
  { name: "kelpie_get_network_log", description: "Get network request log", method: "getNetworkLog", schema: { device, type: z.string().optional().describe("Filter by resource type"), status: z.enum(["success", "error", "pending"]).optional(), since: z.string().optional(), limit: z.number().optional() }, bodyFromArgs: passthrough },
  { name: "kelpie_get_resource_timeline", description: "Get resource loading timeline", method: "getResourceTimeline", schema: { device }, bodyFromArgs: passthrough },
  { name: "kelpie_clear_console", description: "Clear console messages", method: "clearConsole", schema: { device }, bodyFromArgs: passthrough },

  // Accessibility
  { name: "kelpie_get_accessibility_tree", description: "Get the accessibility tree for the page", method: "getAccessibilityTree", schema: { device, root: z.string().optional().describe("Root selector"), interactableOnly: z.boolean().optional(), maxDepth: z.number().optional() }, bodyFromArgs: passthrough },

  // Annotated screenshots
  { name: "kelpie_screenshot_annotated", description: "Take a screenshot with numbered element annotations", method: "screenshotAnnotated", schema: { device, fullPage: z.boolean().optional(), format: z.enum(["png", "jpeg"]).optional(), interactableOnly: z.boolean().optional(), labelStyle: z.enum(["numbered", "badge"]).optional() }, bodyFromArgs: passthrough },
  { name: "kelpie_click_annotation", description: "Click an annotated element by index", method: "clickAnnotation", schema: { device, index: z.number().describe("Annotation index") }, bodyFromArgs: passthrough },
  { name: "kelpie_fill_annotation", description: "Fill an annotated element by index", method: "fillAnnotation", schema: { device, index: z.number().describe("Annotation index"), value: z.string().describe("Value to fill") }, bodyFromArgs: passthrough },

  // 3D DOM inspector (macOS only)
  { name: "kelpie_snapshot_3d_enter", description: "Enter the 3D DOM inspector view. Applies 3D transforms to the current page to visualize stacking depth. macOS only.", method: "snapshot3dEnter", schema: { device }, bodyFromArgs: passthrough },
  { name: "kelpie_snapshot_3d_exit", description: "Exit the 3D DOM inspector and restore the normal page view. macOS only.", method: "snapshot3dExit", schema: { device }, bodyFromArgs: passthrough },
  { name: "kelpie_snapshot_3d_status", description: "Return whether the 3D DOM inspector is currently active. macOS only.", method: "snapshot3dStatus", schema: { device }, bodyFromArgs: passthrough },
  { name: "kelpie_snapshot_3d_set_mode", description: "Switch the 3D inspector interaction mode between rotate (orbit the scene) and scroll (pan the page). macOS only.", method: "snapshot3dSetMode", schema: { device, mode: z.enum(["rotate", "scroll"]).describe("Interaction mode") }, bodyFromArgs: passthrough },
  { name: "kelpie_snapshot_3d_zoom", description: "Zoom the 3D inspector scene. Provide either a signed 'delta' (e.g. 0.1 to zoom in, -0.1 to zoom out) or 'direction' ('in' | 'out'). macOS only.", method: "snapshot3dZoom", schema: { device, delta: z.number().optional().describe("Signed zoom delta (positive=in, negative=out)"), direction: z.enum(["in", "out"]).optional().describe("Zoom direction") }, bodyFromArgs: passthrough },
  { name: "kelpie_snapshot_3d_reset_view", description: "Reset the 3D inspector camera to its default rotation and scale. macOS only.", method: "snapshot3dResetView", schema: { device }, bodyFromArgs: passthrough },

  // Visible elements
  { name: "kelpie_get_visible_elements", description: "Get all visible elements in the viewport", method: "getVisibleElements", schema: { device, interactableOnly: z.boolean().optional(), includeText: z.boolean().optional() }, bodyFromArgs: passthrough },

  // Page text
  { name: "kelpie_get_page_text", description: "Extract readable text content from the page", method: "getPageText", schema: { device, mode: z.enum(["readable", "full", "markdown"]).optional().describe("Extraction mode"), selector: selector.optional() }, bodyFromArgs: passthrough },

  // Form state
  { name: "kelpie_get_form_state", description: "Get the state of all forms on the page", method: "getFormState", schema: { device, selector: selector.optional() }, bodyFromArgs: passthrough },

  // Dialogs
  { name: "kelpie_get_dialog", description: "Get the currently showing dialog", method: "getDialog", schema: { device }, bodyFromArgs: passthrough },
  { name: "kelpie_handle_dialog", description: "Accept or dismiss a dialog", method: "handleDialog", schema: { device, action: z.enum(["accept", "dismiss"]).describe("Dialog action"), promptText: z.string().optional().describe("Text for prompt dialogs") }, bodyFromArgs: passthrough },
  { name: "kelpie_set_dialog_auto_handler", description: "Set automatic dialog handling", method: "setDialogAutoHandler", schema: { device, enabled: z.boolean().describe("Enable auto-handling"), defaultAction: z.enum(["accept", "dismiss", "queue"]).optional(), promptText: z.string().optional() }, bodyFromArgs: passthrough },

  // Tabs
  { name: "kelpie_get_tabs", description: "Get all open tabs", method: "getTabs", schema: { device }, bodyFromArgs: passthrough },
  { name: "kelpie_new_tab", description: "Open a new tab", method: "newTab", schema: { device, url: url.optional().describe("URL to open in new tab") }, bodyFromArgs: passthrough },
  { name: "kelpie_switch_tab", description: "Switch to a specific tab", method: "switchTab", schema: { device, tabId: z.number().describe("Tab ID to switch to") }, bodyFromArgs: passthrough },
  { name: "kelpie_close_tab", description: "Close a tab", method: "closeTab", schema: { device, tabId: z.number().describe("Tab ID to close") }, bodyFromArgs: passthrough },

  // Iframes
  { name: "kelpie_get_iframes", description: "Get all iframes on the page", method: "getIframes", schema: { device }, bodyFromArgs: passthrough },
  { name: "kelpie_switch_to_iframe", description: "Switch context to an iframe", method: "switchToIframe", schema: { device, iframeId: z.number().optional().describe("Iframe ID"), selector: selector.optional() }, bodyFromArgs: passthrough },
  { name: "kelpie_switch_to_main", description: "Switch back to the main frame", method: "switchToMain", schema: { device }, bodyFromArgs: passthrough },
  { name: "kelpie_get_iframe_context", description: "Get current iframe context", method: "getIframeContext", schema: { device }, bodyFromArgs: passthrough },

  // Cookies
  { name: "kelpie_get_cookies", description: "Get cookies", method: "getCookies", schema: { device, url: url.optional().describe("Filter by URL"), name: z.string().optional().describe("Filter by name") }, bodyFromArgs: passthrough },
  { name: "kelpie_set_cookie", description: "Set a cookie", method: "setCookie", schema: { device, name: z.string().describe("Cookie name"), value: z.string().describe("Cookie value"), domain: z.string().optional(), path: z.string().optional(), httpOnly: z.boolean().optional(), secure: z.boolean().optional(), sameSite: z.string().optional(), expires: z.string().optional() }, bodyFromArgs: passthrough },
  { name: "kelpie_delete_cookies", description: "Delete cookies", method: "deleteCookies", schema: { device, name: z.string().optional().describe("Cookie name"), domain: z.string().optional(), deleteAll: z.boolean().optional() }, bodyFromArgs: passthrough },

  // Storage
  { name: "kelpie_get_storage", description: "Get localStorage or sessionStorage entries", method: "getStorage", schema: { device, type: z.enum(["local", "session"]).optional().describe("Storage type"), key: z.string().optional() }, bodyFromArgs: passthrough },
  { name: "kelpie_set_storage", description: "Set a storage entry", method: "setStorage", schema: { device, type: z.enum(["local", "session"]).optional(), key: z.string().describe("Storage key"), value: z.string().describe("Storage value") }, bodyFromArgs: passthrough },
  { name: "kelpie_clear_storage", description: "Clear storage", method: "clearStorage", schema: { device, type: z.enum(["local", "session", "both"]).optional() }, bodyFromArgs: passthrough },

  // Mutations
  { name: "kelpie_watch_mutations", description: "Start watching DOM mutations", method: "watchMutations", schema: { device, selector: selector.optional(), attributes: z.boolean().optional(), childList: z.boolean().optional(), subtree: z.boolean().optional(), characterData: z.boolean().optional() }, bodyFromArgs: passthrough },
  { name: "kelpie_get_mutations", description: "Get recorded DOM mutations", method: "getMutations", schema: { device, watchId: z.string().describe("Watch ID"), clear: z.boolean().optional() }, bodyFromArgs: passthrough },
  { name: "kelpie_stop_watching", description: "Stop watching DOM mutations", method: "stopWatching", schema: { device, watchId: z.string().describe("Watch ID") }, bodyFromArgs: passthrough },

  // Shadow DOM
  { name: "kelpie_query_shadow_dom", description: "Query inside a shadow DOM", method: "queryShadowDOM", schema: { device, hostSelector: z.string().describe("Shadow host selector"), shadowSelector: z.string().describe("Selector within shadow root"), pierce: z.boolean().optional() }, bodyFromArgs: passthrough },
  { name: "kelpie_get_shadow_roots", description: "Get all shadow root hosts on the page", method: "getShadowRoots", schema: { device }, bodyFromArgs: passthrough },

  // Clipboard
  { name: "kelpie_get_clipboard", description: "Get clipboard contents", method: "getClipboard", schema: { device }, bodyFromArgs: passthrough },
  { name: "kelpie_set_clipboard", description: "Set clipboard text", method: "setClipboard", schema: { device, text: z.string().describe("Text to copy to clipboard") }, bodyFromArgs: passthrough },

  // Geolocation
  { name: "kelpie_set_geolocation", description: "Override device geolocation", method: "setGeolocation", schema: { device, latitude: z.number().describe("Latitude"), longitude: z.number().describe("Longitude"), accuracy: z.number().optional().describe("Accuracy in meters") }, bodyFromArgs: passthrough },
  { name: "kelpie_clear_geolocation", description: "Clear geolocation override", method: "clearGeolocation", schema: { device }, bodyFromArgs: passthrough },

  // Request interception
  { name: "kelpie_set_request_interception", description: "Set request interception rules", method: "setRequestInterception", schema: { device, rules: z.array(z.object({ pattern: z.string(), action: z.enum(["block", "mock", "allow"]), mockResponse: z.object({ status: z.number(), headers: z.record(z.string(), z.string()), body: z.string() }).optional() })).describe("Interception rules") }, bodyFromArgs: passthrough },
  { name: "kelpie_get_intercepted_requests", description: "Get intercepted requests", method: "getInterceptedRequests", schema: { device, since: z.string().optional(), limit: z.number().optional() }, bodyFromArgs: passthrough },
  { name: "kelpie_clear_request_interception", description: "Clear all interception rules", method: "clearRequestInterception", schema: { device }, bodyFromArgs: passthrough },

  // Keyboard & Viewport
  { name: "kelpie_show_keyboard", description: "Show the on-screen keyboard", method: "showKeyboard", schema: { device, selector: selector.optional(), keyboardType: z.enum(["default", "email", "number", "phone", "url"]).optional() }, bodyFromArgs: passthrough },
  { name: "kelpie_hide_keyboard", description: "Hide the on-screen keyboard", method: "hideKeyboard", schema: { device }, bodyFromArgs: passthrough },
  { name: "kelpie_get_keyboard_state", description: "Get keyboard visibility and state", method: "getKeyboardState", schema: { device }, bodyFromArgs: passthrough },
  { name: "kelpie_resize_viewport", description: "Resize the browser viewport", method: "resizeViewport", schema: { device, width: z.number().optional().describe("Viewport width"), height: z.number().optional().describe("Viewport height") }, bodyFromArgs: passthrough },
  { name: "kelpie_reset_viewport", description: "Reset viewport to device default", method: "resetViewport", schema: { device }, bodyFromArgs: passthrough },
  { name: "kelpie_set_viewport_preset", description: "Activate a named viewport preset such as Compact / Base, Standard / Pro, or foldable sizes. Linux does not support viewport presets yet.", method: "setViewportPreset", schema: { device, presetId: z.string().describe("Viewport preset id returned by getViewportPresets") }, bodyFromArgs: passthrough },
  { name: "kelpie_is_element_obscured", description: "Check if an element is obscured by keyboard or other elements", method: "isElementObscured", schema: { device, selector }, bodyFromArgs: passthrough },

  // Orientation
  { name: "kelpie_set_orientation", description: "Force the device into portrait, landscape, or auto orientation. Useful for testing responsive layouts and orientation-dependent features.", method: "setOrientation", schema: { device, orientation: z.enum(["portrait", "landscape", "auto"]).describe("Target orientation. 'auto' unlocks rotation.") }, bodyFromArgs: passthrough },
  { name: "kelpie_get_orientation", description: "Get the current device orientation and lock state", method: "getOrientation", schema: { device }, bodyFromArgs: passthrough },

  // Safari Auth
  { name: "kelpie_safari_auth", description: "Open the current page (or a specific URL) in a Safari-backed authentication session. This lets the user authenticate using Safari's saved passwords and cookies, then syncs the session back into the browser. Use this when a login page requires credentials the user has saved in Safari, or when OAuth providers block in-app browsers. The user will see a Safari sheet and must complete authentication manually — the tool returns once they finish or cancel.", method: "safariAuth", schema: { device, url: url.optional().describe("URL to authenticate. Defaults to the current page URL."), message }, bodyFromArgs: passthrough },

  // Renderer (macOS only)
  { name: "kelpie_set_renderer", description: "Switch the browser rendering engine (macOS only). Available engines: 'webkit' (Safari/WebKit), 'chromium' (Chrome/CEF), 'gecko' (Firefox — requires Firefox.app installed). Cookies are migrated automatically so login sessions are preserved.", method: "setRenderer", schema: { device, engine: z.enum(["webkit", "chromium", "gecko"]).describe("Rendering engine to activate"), message }, bodyFromArgs: passthrough },
  { name: "kelpie_get_renderer", description: "Get the current rendering engine and available engines (macOS only)", method: "getRenderer", schema: { device }, bodyFromArgs: passthrough },

  // AI / Local Inference
  { name: "kelpie_ai_status", description: "Get the local inference engine status — whether a model is loaded, which model, its capabilities, and memory usage", method: "ai-status", schema: { device }, bodyFromArgs: passthrough },
  { name: "kelpie_ai_load", description: "Load a model on a device for local inference. Pass a model ID or an ollama: prefixed ID. Only one model at a time — auto-unloads the current model.", method: "ai-load", schema: { device, model: z.string().describe("Model ID (e.g. 'gemma-4-e2b-q4') or Ollama model (e.g. 'ollama:llava:7b')") }, bodyFromArgs: passthrough },
  { name: "kelpie_ai_unload", description: "Unload the current model from a device, freeing memory", method: "ai-unload", schema: { device }, bodyFromArgs: passthrough },
  { name: "kelpie_ai_ask", description: "Ask the locally-loaded model a question about the current page. Use 'context' to auto-gather page data or provide 'text' directly. Runs entirely on-device.", method: "ai-infer", schema: { device, prompt: z.string().optional().describe("Question or instruction"), audio: z.string().optional().describe("Base64 WAV audio (16kHz mono, max 30s)"), context: z.enum(["page_text", "screenshot", "dom", "accessibility"]).optional().describe("Auto-gather page context"), text: z.string().optional().describe("Raw text input"), maxTokens: z.number().optional().describe("Max tokens (default 512)"), temperature: z.number().optional().describe("Temperature (default 0.7)") }, bodyFromArgs: passthrough },
  { name: "kelpie_ai_record", description: "Control audio recording on the device for voice input to the AI model", method: "ai-record", schema: { device, action: z.enum(["start", "stop", "status"]).optional().describe("Recording action (default: start)") }, bodyFromArgs: passthrough },
];

// --- CLI tool definitions (20 tools) ---

export const cliTools: CliToolDef[] = [
  // Discovery
  { name: "kelpie_discover", description: "Discover devices on the local network via mDNS", method: "discover", kind: "discovery", schema: { timeout: z.number().optional().describe("Discovery timeout in ms (default 3000)") }, bodyFromArgs: filterBody },
  { name: "kelpie_list_devices", description: "List all discovered devices", method: "listDevices", kind: "discovery", schema: {}, bodyFromArgs: filterBody },

  // Group commands
  { name: "kelpie_group_navigate", description: "Navigate all (or filtered) devices to a URL", method: "navigate", kind: "group", schema: { ...filterProps, url: url.describe("URL to navigate to") }, bodyFromArgs: filterBody },
  { name: "kelpie_group_screenshot", description: "Take screenshots on all (or filtered) devices", method: "screenshot", kind: "group", schema: { ...filterProps }, bodyFromArgs: filterBody },
  { name: "kelpie_group_find_button", description: "Find a button across all devices", method: "findButton", kind: "smartQuery", schema: { ...filterProps, text: z.string().describe("Button text") }, bodyFromArgs: filterBody },
  { name: "kelpie_group_fill", description: "Fill a form field on all devices", method: "fill", kind: "group", schema: { ...filterProps, selector, value: z.string().describe("Value to fill") }, bodyFromArgs: filterBody },
  { name: "kelpie_group_click", description: "Click an element on all devices", method: "click", kind: "group", schema: { ...filterProps, selector }, bodyFromArgs: filterBody },
  { name: "kelpie_group_scroll2", description: "Resolution-aware scroll on all devices", method: "scroll2", kind: "group", schema: { ...filterProps, selector }, bodyFromArgs: filterBody },
  { name: "kelpie_group_find_element", description: "Find an element across all devices", method: "findElement", kind: "smartQuery", schema: { ...filterProps, text: z.string().describe("Text to search for") }, bodyFromArgs: filterBody },
  { name: "kelpie_group_find_link", description: "Find a link across all devices", method: "findLink", kind: "smartQuery", schema: { ...filterProps, text: z.string().describe("Link text") }, bodyFromArgs: filterBody },
  { name: "kelpie_group_find_input", description: "Find an input across all devices", method: "findInput", kind: "smartQuery", schema: { ...filterProps, label: z.string().optional().describe("Input label") }, bodyFromArgs: filterBody },
  { name: "kelpie_group_a11y", description: "Get accessibility tree from all devices", method: "getAccessibilityTree", kind: "group", schema: { ...filterProps }, bodyFromArgs: filterBody },
  { name: "kelpie_group_dom", description: "Get DOM from all devices", method: "getDOM", kind: "group", schema: { ...filterProps }, bodyFromArgs: filterBody },
  { name: "kelpie_group_eval", description: "Evaluate JavaScript on all devices", method: "evaluate", kind: "group", schema: { ...filterProps, expression: z.string().describe("JavaScript expression") }, bodyFromArgs: filterBody },
  { name: "kelpie_group_console", description: "Get console messages from all devices", method: "getConsoleMessages", kind: "group", schema: { ...filterProps }, bodyFromArgs: filterBody },
  { name: "kelpie_group_errors", description: "Get JavaScript errors from all devices", method: "getJSErrors", kind: "group", schema: { ...filterProps }, bodyFromArgs: filterBody },
  { name: "kelpie_group_form_state", description: "Get form state from all devices", method: "getFormState", kind: "group", schema: { ...filterProps }, bodyFromArgs: filterBody },
  { name: "kelpie_group_visible", description: "Get visible elements from all devices", method: "getVisibleElements", kind: "group", schema: { ...filterProps }, bodyFromArgs: filterBody },
  { name: "kelpie_group_keyboard_show", description: "Show keyboard on all devices", method: "showKeyboard", kind: "group", schema: { ...filterProps }, bodyFromArgs: filterBody },
  { name: "kelpie_group_keyboard_hide", description: "Hide keyboard on all devices", method: "hideKeyboard", kind: "group", schema: { ...filterProps }, bodyFromArgs: filterBody },

  // AI Model Management
  { name: "kelpie_ai_models", description: "List all approved models and their download status", method: "aiModels", kind: "discovery", schema: {}, bodyFromArgs: filterBody },
  { name: "kelpie_ai_pull", description: "Download a model from HuggingFace to the local model store", method: "aiPull", kind: "discovery", schema: { model: z.string().describe("Model ID or HuggingFace repo path") }, bodyFromArgs: filterBody },
  { name: "kelpie_ai_remove", description: "Delete a downloaded model from the local store", method: "aiRemove", kind: "discovery", schema: { model: z.string().describe("Model ID to remove") }, bodyFromArgs: filterBody },
];
