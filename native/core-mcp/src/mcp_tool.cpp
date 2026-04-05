#include "kelpie/mcp_tool.h"

#include <utility>

namespace kelpie {
namespace {

using P = Platform;

const std::vector<P> kAllPlatforms = {P::kIos, P::kAndroid, P::kMacos, P::kLinux, P::kWindows};
const StringList kAllEngines = {"webkit", "chromium", "gecko"};
const StringList kWebkitOnly = {"webkit"};
const std::vector<P> kApplePlatforms = {P::kIos, P::kMacos};
const std::vector<P> kMobilePlatforms = {P::kIos, P::kAndroid};
const std::vector<P> kOrientationPlatforms = {P::kIos, P::kAndroid, P::kMacos};
const std::vector<P> kRendererPlatforms = {P::kIos, P::kAndroid, P::kMacos, P::kLinux,
                                           P::kWindows};

ToolAvailability DefaultAvailability() {
  return ToolAvailability{
      kAllPlatforms,
      kAllEngines,
      false,
      true,
      {},
  };
}

ToolAvailability UiAvailability(const std::vector<P>& platforms, const StringList& engines,
                                StringList capabilities) {
  return ToolAvailability{
      platforms,
      engines,
      true,
      false,
      std::move(capabilities),
  };
}

ToolAvailability CapabilityAvailability(const std::vector<P>& platforms, const StringList& engines,
                                        StringList capabilities) {
  return ToolAvailability{
      platforms,
      engines,
      false,
      true,
      std::move(capabilities),
  };
}

McpTool Tool(std::string name, std::string endpoint, std::string description,
             ToolAvailability availability = DefaultAvailability()) {
  return McpTool{std::move(name), std::move(endpoint), std::move(description), std::move(availability)};
}

}  // namespace

bool SupportsPlatform(const ToolAvailability& availability, Platform platform) {
  for (const Platform supported_platform : availability.platforms) {
    if (supported_platform == platform) {
      return true;
    }
  }
  return false;
}

bool SupportsEngine(const ToolAvailability& availability, std::string_view engine) {
  for (const std::string& supported_engine : availability.engines) {
    if (supported_engine == engine) {
      return true;
    }
  }
  return false;
}

bool HasRuntimeCaveat(const ToolAvailability& availability) {
  return availability.requires_ui || !availability.required_capabilities.empty() ||
         !availability.allowed_headless;
}

std::vector<McpTool> CreateDefaultMcpTools() {
  return {
      Tool("kelpie_navigate", "navigate", "Navigate device browser to a URL"),
      Tool("kelpie_back", "back", "Go back in browser history"),
      Tool("kelpie_forward", "forward", "Go forward in browser history"),
      Tool("kelpie_reload", "reload", "Reload the current page"),
      Tool("kelpie_get_current_url", "get-current-url", "Get the current URL and page title"),
      Tool("kelpie_set_home", "set-home", "Set the device home page URL. Persisted across app restarts."),
      Tool("kelpie_get_home", "get-home", "Get the device home page URL"),
      Tool("kelpie_set_fullscreen", "set-fullscreen", "Enable or disable fullscreen mode for the desktop browser window."),
      Tool("kelpie_get_fullscreen", "get-fullscreen", "Get whether the desktop browser window is currently fullscreen."),
      Tool("kelpie_debug_screens", "debug-screens", "Get screen/scene/external display diagnostics. Shows UIScreen count, connected scenes, and external display manager state."),
      Tool("kelpie_set_debug_overlay", "set-debug-overlay", "Enable or disable the on-screen debug overlay showing screen/scene/connection info"),
      Tool("kelpie_get_debug_overlay", "get-debug-overlay", "Get current debug overlay state"),
      Tool("kelpie_screenshot", "screenshot", "Take a screenshot of the device browser"),
      Tool("kelpie_get_dom", "get-dom", "Get the DOM tree as HTML"),
      Tool("kelpie_query_selector", "query-selector", "Find a single element matching a CSS selector"),
      Tool("kelpie_query_selector_all", "query-selector-all", "Find all elements matching a CSS selector"),
      Tool("kelpie_get_element_text", "get-element-text", "Get text content of an element"),
      Tool("kelpie_get_attributes", "get-attributes", "Get all attributes of an element"),
      Tool("kelpie_click", "click", "Click an element. Shows a blue touch indicator at the element location."),
      Tool("kelpie_tap", "tap", "Tap at specific coordinates. Shows a blue touch indicator at the tap point."),
      Tool("kelpie_fill", "fill", "Fill a form field with a value. Shows a touch indicator at the field."),
      Tool("kelpie_type", "type", "Type text character by character"),
      Tool("kelpie_select_option", "select-option", "Select an option from a dropdown"),
      Tool("kelpie_check", "check", "Check a checkbox"),
      Tool("kelpie_uncheck", "uncheck", "Uncheck a checkbox"),
      Tool("kelpie_scroll", "scroll", "Scroll by pixel delta"),
      Tool("kelpie_scroll2", "scroll2", "Scroll to make an element visible (resolution-aware). Shows a touch indicator at the target element."),
      Tool("kelpie_scroll_to_top", "scroll-to-top", "Scroll to the top of the page"),
      Tool("kelpie_scroll_to_bottom", "scroll-to-bottom", "Scroll to the bottom of the page"),
      Tool("kelpie_get_viewport", "get-viewport", "Get viewport dimensions and device pixel ratio"),
      Tool("kelpie_get_device_info", "get-device-info", "Get full device information"),
      Tool("kelpie_get_capabilities", "get-capabilities", "Get device capabilities"),
      Tool("kelpie_wait_for_element", "wait-for-element", "Wait for an element to appear or reach a state"),
      Tool("kelpie_wait_for_navigation", "wait-for-navigation", "Wait for a navigation to complete"),
      Tool("kelpie_find_element", "find-element", "Find an element by text content or role"),
      Tool("kelpie_find_button", "find-button", "Find a button by its text"),
      Tool("kelpie_find_link", "find-link", "Find a link by its text"),
      Tool("kelpie_find_input", "find-input", "Find an input field by label, placeholder, or name"),
      Tool("kelpie_evaluate", "evaluate", "Evaluate JavaScript in the page context"),
      Tool("kelpie_toast", "toast", "Show a toast message overlay on the device screen. Use this to narrate actions, explain what you are doing, or communicate status to anyone watching the device. The message appears in a semi-transparent card at the bottom of the viewport for 3 seconds."),
      Tool("kelpie_get_console_messages", "get-console-messages", "Get browser console messages"),
      Tool("kelpie_get_js_errors", "get-js-errors", "Get JavaScript errors from the page"),
      Tool("kelpie_get_network_log", "get-network-log", "Get network request log"),
      Tool("kelpie_get_resource_timeline", "get-resource-timeline", "Get resource loading timeline"),
      Tool("kelpie_clear_console", "clear-console", "Clear console messages"),
      Tool("kelpie_get_accessibility_tree", "get-accessibility-tree", "Get the accessibility tree for the page"),
      Tool("kelpie_screenshot_annotated", "screenshot-annotated", "Take a screenshot with numbered element annotations"),
      Tool("kelpie_click_annotation", "click-annotation", "Click an annotated element by index"),
      Tool("kelpie_fill_annotation", "fill-annotation", "Fill an annotated element by index"),
      Tool("kelpie_get_visible_elements", "get-visible-elements", "Get all visible elements in the viewport"),
      Tool("kelpie_get_page_text", "get-page-text", "Extract readable text content from the page"),
      Tool("kelpie_get_form_state", "get-form-state", "Get the state of all forms on the page"),
      Tool("kelpie_get_dialog", "get-dialog", "Get the currently showing dialog"),
      Tool("kelpie_handle_dialog", "handle-dialog", "Accept or dismiss a dialog"),
      Tool("kelpie_set_dialog_auto_handler", "set-dialog-auto-handler", "Set automatic dialog handling"),
      Tool("kelpie_get_tabs", "get-tabs", "Get all open tabs"),
      Tool("kelpie_new_tab", "new-tab", "Open a new tab"),
      Tool("kelpie_switch_tab", "switch-tab", "Switch to a specific tab"),
      Tool("kelpie_close_tab", "close-tab", "Close a tab"),
      Tool("kelpie_get_iframes", "get-iframes", "Get all iframes on the page"),
      Tool("kelpie_switch_to_iframe", "switch-to-iframe", "Switch context to an iframe"),
      Tool("kelpie_switch_to_main", "switch-to-main", "Switch back to the main frame"),
      Tool("kelpie_get_iframe_context", "get-iframe-context", "Get current iframe context"),
      Tool("kelpie_get_cookies", "get-cookies", "Get cookies"),
      Tool("kelpie_set_cookie", "set-cookie", "Set a cookie"),
      Tool("kelpie_delete_cookies", "delete-cookies", "Delete cookies"),
      Tool("kelpie_get_storage", "get-storage", "Get localStorage or sessionStorage entries"),
      Tool("kelpie_set_storage", "set-storage", "Set a storage entry"),
      Tool("kelpie_clear_storage", "clear-storage", "Clear storage"),
      Tool("kelpie_watch_mutations", "watch-mutations", "Start watching DOM mutations"),
      Tool("kelpie_get_mutations", "get-mutations", "Get recorded DOM mutations"),
      Tool("kelpie_stop_watching", "stop-watching", "Stop watching DOM mutations"),
      Tool("kelpie_query_shadow_dom", "query-shadow-dom", "Query inside a shadow DOM"),
      Tool("kelpie_get_shadow_roots", "get-shadow-roots", "Get all shadow root hosts on the page"),
      Tool("kelpie_get_clipboard", "get-clipboard", "Get clipboard contents"),
      Tool("kelpie_set_clipboard", "set-clipboard", "Set clipboard text"),
      Tool("kelpie_set_geolocation", "set-geolocation", "Override device geolocation"),
      Tool("kelpie_clear_geolocation", "clear-geolocation", "Clear geolocation override"),
      Tool("kelpie_set_request_interception", "set-request-interception", "Set request interception rules"),
      Tool("kelpie_get_intercepted_requests", "get-intercepted-requests", "Get intercepted requests"),
      Tool("kelpie_clear_request_interception", "clear-request-interception", "Clear all interception rules"),
      Tool("kelpie_show_keyboard", "show-keyboard", "Show the on-screen keyboard",
           UiAvailability(kMobilePlatforms, kAllEngines, {"soft-keyboard"})),
      Tool("kelpie_hide_keyboard", "hide-keyboard", "Hide the on-screen keyboard",
           UiAvailability(kMobilePlatforms, kAllEngines, {"soft-keyboard"})),
      Tool("kelpie_get_keyboard_state", "get-keyboard-state", "Get keyboard visibility and state",
           UiAvailability(kMobilePlatforms, kAllEngines, {"soft-keyboard"})),
      Tool("kelpie_resize_viewport", "resize-viewport", "Resize the browser viewport"),
      Tool("kelpie_reset_viewport", "reset-viewport", "Reset viewport to device default"),
      Tool("kelpie_is_element_obscured", "is-element-obscured", "Check if an element is obscured by keyboard or other elements",
           CapabilityAvailability(kMobilePlatforms, kAllEngines, {"obscured-element-detection"})),
      Tool("kelpie_set_orientation", "set-orientation", "Force the device into portrait, landscape, or auto orientation. Useful for testing responsive layouts and orientation-dependent features.",
           CapabilityAvailability(kOrientationPlatforms, kAllEngines, {"orientation-control"})),
      Tool("kelpie_get_orientation", "get-orientation", "Get the current device orientation and lock state",
           CapabilityAvailability(kOrientationPlatforms, kAllEngines, {"orientation-control"})),
      Tool("kelpie_safari_auth", "safari-auth", "Open the current page (or a specific URL) in a Safari-backed authentication session. This lets the user authenticate using Safari's saved passwords and cookies, then syncs the session back into the browser. Use this when a login page requires credentials the user has saved in Safari, or when OAuth providers block in-app browsers. The user will see a Safari sheet and must complete authentication manually — the tool returns once they finish or cancel.",
           UiAvailability(kApplePlatforms, kWebkitOnly, {"safari-auth-session"})),
      Tool("kelpie_set_renderer", "set-renderer", "Switch the browser rendering engine when renderer switching is supported on the current platform. Available engines are platform-dependent and iOS alternative engines remain region-gated.",
           CapabilityAvailability(kRendererPlatforms, kAllEngines, {"renderer-switching"})),
      Tool("kelpie_get_renderer", "get-renderer", "Get the current rendering engine and the engines available on the current platform. iOS alternative engines remain region-gated.",
           CapabilityAvailability(kRendererPlatforms, kAllEngines, {"renderer-switching"})),
  };
}

}  // namespace kelpie
