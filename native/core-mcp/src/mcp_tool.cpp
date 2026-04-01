#include "mollotov/mcp_tool.h"

#include <utility>

namespace mollotov {
namespace {

using P = Platform;

const std::vector<P> kAllPlatforms = {P::kIos, P::kAndroid, P::kMacos, P::kLinux, P::kWindows};
const StringList kAllEngines = {"webkit", "chromium", "gecko"};
const StringList kWebkitOnly = {"webkit"};
const std::vector<P> kApplePlatforms = {P::kIos, P::kMacos};
const std::vector<P> kMobilePlatforms = {P::kIos, P::kAndroid};
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
      Tool("mollotov_navigate", "navigate", "Navigate device browser to a URL"),
      Tool("mollotov_back", "back", "Go back in browser history"),
      Tool("mollotov_forward", "forward", "Go forward in browser history"),
      Tool("mollotov_reload", "reload", "Reload the current page"),
      Tool("mollotov_get_current_url", "get-current-url", "Get the current URL and page title"),
      Tool("mollotov_set_home", "set-home", "Set the device home page URL. Persisted across app restarts."),
      Tool("mollotov_get_home", "get-home", "Get the device home page URL"),
      Tool("mollotov_set_fullscreen", "set-fullscreen", "Enable or disable fullscreen mode for the desktop browser window."),
      Tool("mollotov_get_fullscreen", "get-fullscreen", "Get whether the desktop browser window is currently fullscreen."),
      Tool("mollotov_debug_screens", "debug-screens", "Get screen/scene/external display diagnostics. Shows UIScreen count, connected scenes, and external display manager state."),
      Tool("mollotov_set_debug_overlay", "set-debug-overlay", "Enable or disable the on-screen debug overlay showing screen/scene/connection info"),
      Tool("mollotov_get_debug_overlay", "get-debug-overlay", "Get current debug overlay state"),
      Tool("mollotov_screenshot", "screenshot", "Take a screenshot of the device browser"),
      Tool("mollotov_get_dom", "get-dom", "Get the DOM tree as HTML"),
      Tool("mollotov_query_selector", "query-selector", "Find a single element matching a CSS selector"),
      Tool("mollotov_query_selector_all", "query-selector-all", "Find all elements matching a CSS selector"),
      Tool("mollotov_get_element_text", "get-element-text", "Get text content of an element"),
      Tool("mollotov_get_attributes", "get-attributes", "Get all attributes of an element"),
      Tool("mollotov_click", "click", "Click an element. Shows a blue touch indicator at the element location."),
      Tool("mollotov_tap", "tap", "Tap at specific coordinates. Shows a blue touch indicator at the tap point."),
      Tool("mollotov_fill", "fill", "Fill a form field with a value. Shows a touch indicator at the field."),
      Tool("mollotov_type", "type", "Type text character by character"),
      Tool("mollotov_select_option", "select-option", "Select an option from a dropdown"),
      Tool("mollotov_check", "check", "Check a checkbox"),
      Tool("mollotov_uncheck", "uncheck", "Uncheck a checkbox"),
      Tool("mollotov_scroll", "scroll", "Scroll by pixel delta"),
      Tool("mollotov_scroll2", "scroll2", "Scroll to make an element visible (resolution-aware). Shows a touch indicator at the target element."),
      Tool("mollotov_scroll_to_top", "scroll-to-top", "Scroll to the top of the page"),
      Tool("mollotov_scroll_to_bottom", "scroll-to-bottom", "Scroll to the bottom of the page"),
      Tool("mollotov_get_viewport", "get-viewport", "Get viewport dimensions and device pixel ratio"),
      Tool("mollotov_get_device_info", "get-device-info", "Get full device information"),
      Tool("mollotov_get_capabilities", "get-capabilities", "Get device capabilities"),
      Tool("mollotov_wait_for_element", "wait-for-element", "Wait for an element to appear or reach a state"),
      Tool("mollotov_wait_for_navigation", "wait-for-navigation", "Wait for a navigation to complete"),
      Tool("mollotov_find_element", "find-element", "Find an element by text content or role"),
      Tool("mollotov_find_button", "find-button", "Find a button by its text"),
      Tool("mollotov_find_link", "find-link", "Find a link by its text"),
      Tool("mollotov_find_input", "find-input", "Find an input field by label, placeholder, or name"),
      Tool("mollotov_evaluate", "evaluate", "Evaluate JavaScript in the page context"),
      Tool("mollotov_toast", "toast", "Show a toast message overlay on the device screen. Use this to narrate actions, explain what you are doing, or communicate status to anyone watching the device. The message appears in a semi-transparent card at the bottom of the viewport for 3 seconds."),
      Tool("mollotov_get_console_messages", "get-console-messages", "Get browser console messages"),
      Tool("mollotov_get_js_errors", "get-js-errors", "Get JavaScript errors from the page"),
      Tool("mollotov_get_network_log", "get-network-log", "Get network request log"),
      Tool("mollotov_get_resource_timeline", "get-resource-timeline", "Get resource loading timeline"),
      Tool("mollotov_clear_console", "clear-console", "Clear console messages"),
      Tool("mollotov_get_accessibility_tree", "get-accessibility-tree", "Get the accessibility tree for the page"),
      Tool("mollotov_screenshot_annotated", "screenshot-annotated", "Take a screenshot with numbered element annotations"),
      Tool("mollotov_click_annotation", "click-annotation", "Click an annotated element by index"),
      Tool("mollotov_fill_annotation", "fill-annotation", "Fill an annotated element by index"),
      Tool("mollotov_get_visible_elements", "get-visible-elements", "Get all visible elements in the viewport"),
      Tool("mollotov_get_page_text", "get-page-text", "Extract readable text content from the page"),
      Tool("mollotov_get_form_state", "get-form-state", "Get the state of all forms on the page"),
      Tool("mollotov_get_dialog", "get-dialog", "Get the currently showing dialog"),
      Tool("mollotov_handle_dialog", "handle-dialog", "Accept or dismiss a dialog"),
      Tool("mollotov_set_dialog_auto_handler", "set-dialog-auto-handler", "Set automatic dialog handling"),
      Tool("mollotov_get_tabs", "get-tabs", "Get all open tabs"),
      Tool("mollotov_new_tab", "new-tab", "Open a new tab"),
      Tool("mollotov_switch_tab", "switch-tab", "Switch to a specific tab"),
      Tool("mollotov_close_tab", "close-tab", "Close a tab"),
      Tool("mollotov_get_iframes", "get-iframes", "Get all iframes on the page"),
      Tool("mollotov_switch_to_iframe", "switch-to-iframe", "Switch context to an iframe"),
      Tool("mollotov_switch_to_main", "switch-to-main", "Switch back to the main frame"),
      Tool("mollotov_get_iframe_context", "get-iframe-context", "Get current iframe context"),
      Tool("mollotov_get_cookies", "get-cookies", "Get cookies"),
      Tool("mollotov_set_cookie", "set-cookie", "Set a cookie"),
      Tool("mollotov_delete_cookies", "delete-cookies", "Delete cookies"),
      Tool("mollotov_get_storage", "get-storage", "Get localStorage or sessionStorage entries"),
      Tool("mollotov_set_storage", "set-storage", "Set a storage entry"),
      Tool("mollotov_clear_storage", "clear-storage", "Clear storage"),
      Tool("mollotov_watch_mutations", "watch-mutations", "Start watching DOM mutations"),
      Tool("mollotov_get_mutations", "get-mutations", "Get recorded DOM mutations"),
      Tool("mollotov_stop_watching", "stop-watching", "Stop watching DOM mutations"),
      Tool("mollotov_query_shadow_dom", "query-shadow-dom", "Query inside a shadow DOM"),
      Tool("mollotov_get_shadow_roots", "get-shadow-roots", "Get all shadow root hosts on the page"),
      Tool("mollotov_get_clipboard", "get-clipboard", "Get clipboard contents"),
      Tool("mollotov_set_clipboard", "set-clipboard", "Set clipboard text"),
      Tool("mollotov_set_geolocation", "set-geolocation", "Override device geolocation"),
      Tool("mollotov_clear_geolocation", "clear-geolocation", "Clear geolocation override"),
      Tool("mollotov_set_request_interception", "set-request-interception", "Set request interception rules"),
      Tool("mollotov_get_intercepted_requests", "get-intercepted-requests", "Get intercepted requests"),
      Tool("mollotov_clear_request_interception", "clear-request-interception", "Clear all interception rules"),
      Tool("mollotov_show_keyboard", "show-keyboard", "Show the on-screen keyboard",
           UiAvailability(kMobilePlatforms, kAllEngines, {"soft-keyboard"})),
      Tool("mollotov_hide_keyboard", "hide-keyboard", "Hide the on-screen keyboard",
           UiAvailability(kMobilePlatforms, kAllEngines, {"soft-keyboard"})),
      Tool("mollotov_get_keyboard_state", "get-keyboard-state", "Get keyboard visibility and state",
           UiAvailability(kMobilePlatforms, kAllEngines, {"soft-keyboard"})),
      Tool("mollotov_resize_viewport", "resize-viewport", "Resize the browser viewport"),
      Tool("mollotov_reset_viewport", "reset-viewport", "Reset viewport to device default"),
      Tool("mollotov_is_element_obscured", "is-element-obscured", "Check if an element is obscured by keyboard or other elements",
           CapabilityAvailability(kMobilePlatforms, kAllEngines, {"obscured-element-detection"})),
      Tool("mollotov_set_orientation", "set-orientation", "Force the device into portrait, landscape, or auto orientation. Useful for testing responsive layouts and orientation-dependent features.",
           CapabilityAvailability(kMobilePlatforms, kAllEngines, {"orientation-control"})),
      Tool("mollotov_get_orientation", "get-orientation", "Get the current device orientation and lock state",
           CapabilityAvailability(kMobilePlatforms, kAllEngines, {"orientation-control"})),
      Tool("mollotov_safari_auth", "safari-auth", "Open the current page (or a specific URL) in a Safari-backed authentication session. This lets the user authenticate using Safari's saved passwords and cookies, then syncs the session back into the browser. Use this when a login page requires credentials the user has saved in Safari, or when OAuth providers block in-app browsers. The user will see a Safari sheet and must complete authentication manually — the tool returns once they finish or cancel.",
           UiAvailability(kApplePlatforms, kWebkitOnly, {"safari-auth-session"})),
      Tool("mollotov_set_renderer", "set-renderer", "Switch the browser rendering engine when renderer switching is supported on the current platform. Available engines are platform-dependent and iOS alternative engines remain region-gated.",
           CapabilityAvailability(kRendererPlatforms, kAllEngines, {"renderer-switching"})),
      Tool("mollotov_get_renderer", "get-renderer", "Get the current rendering engine and the engines available on the current platform. iOS alternative engines remain region-gated.",
           CapabilityAvailability(kRendererPlatforms, kAllEngines, {"renderer-switching"})),
  };
}

}  // namespace mollotov
