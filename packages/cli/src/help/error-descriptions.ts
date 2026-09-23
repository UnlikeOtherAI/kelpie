export const errorDescriptions: Record<string, string> = {
  ELEMENT_NOT_FOUND: "No matching element was found for the selector, annotation, or lookup request.",
  ELEMENT_NOT_VISIBLE: "The target element exists but is not currently hittable because it is hidden, off-screen, or obscured.",
  TIMEOUT: "The operation did not complete before the timeout expired.",
  NAVIGATION_ERROR: "The browser could not complete the requested navigation.",
  INVALID_URL: "The provided URL is missing or malformed.",
  INVALID_SELECTOR: "The provided CSS selector is syntactically invalid.",
  INVALID_PARAM: "A provided parameter value is invalid.",
  INVALID_PARAMS: "One or more required parameters are missing or invalid.",
  NO_WEBVIEW: "No active browser renderer is attached yet.",
  NO_URL: "There is no current URL available for this action.",
  TAB_NOT_FOUND: "No open tab matched the requested tab ID.",
  PLATFORM_NOT_SUPPORTED: "This command is not implemented on the current platform or runtime.",
  BROWSER_NOT_REGISTERED: "The named local browser alias does not exist.",
  APP_NOT_INSTALLED: "Kelpie.app could not be found at the expected path.",
  BROWSER_LAUNCH_FAILED: "The local Kelpie app could not be launched successfully.",
  DEVICE_NOT_FOUND: "No discovered device matched the requested identifier.",
  NO_DEVICES: "No devices matched the discovery or filter criteria.",
  NO_DIALOG: "No JavaScript dialog is currently open.",
  RECORDING_IN_PROGRESS: "A recording or scripted session is already running and blocks the requested action.",
  MODEL_NOT_FOUND: "The requested model ID does not exist in the local catalog.",
  DOWNLOAD_FAILED: "The requested model download did not finish successfully.",
  NETWORK_ERROR: "The CLI could not reach the device over HTTP.",
  INVALID_PARTITION:
    "The partition string failed validation. It must be 1-128 characters from [A-Za-z0-9._-], " +
    "contain at least one letter or digit, and must not be \".\", \"..\", \"default\" " +
    "(case-insensitive) or start with \"ephemeral-\".",
  PARTITION_UNSUPPORTED:
    "The platform or rendering engine cannot isolate storage per tab. Read the reason field: " +
    "\"chromium-engine\" means switch to WebKit with set-renderer and retry, " +
    "\"webview-multi-profile-missing\" means the Android System WebView needs updating to M114+, " +
    "and \"platform-single-tab\" means the platform has no partition support at all.",
  PARTITION_DELETING:
    "The named partition is being torn down. Retry once delete-partition returns; " +
    "the retry binds to a fresh, empty store.",
  PARTITION_IN_USE:
    "The engine refused to delete the partition even after its tabs were closed. " +
    "The partition id is free to reuse; the abandoned store is listed by get-partitions " +
    "as orphan:<uuid> and can be deleted with that id.",
  ENGINE_SWITCH_BLOCKED_BY_PARTITION:
    "set-renderer cannot switch to Chromium while partitioned tabs are open, because " +
    "partitioned storage has no CEF equivalent to migrate into. Close those tabs or call " +
    "delete-partition first.",
  WINDOW_MINIMIZED:
    "The desktop browser window is minimised or has no visible area, so a screenshot has no " +
    "current image. Restore the window and retry; other commands keep working meanwhile.",
};
