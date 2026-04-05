#include "kelpie/error_codes.h"

#include <string_view>

#include "kelpie/protocol.h"

namespace kelpie {

const char* ErrorCodeToString(ErrorCode code) {
  switch (code) {
    case ErrorCode::kElementNotFound:
      return "ELEMENT_NOT_FOUND";
    case ErrorCode::kElementNotVisible:
      return "ELEMENT_NOT_VISIBLE";
    case ErrorCode::kTimeout:
      return "TIMEOUT";
    case ErrorCode::kNavigationError:
      return "NAVIGATION_ERROR";
    case ErrorCode::kInvalidSelector:
      return "INVALID_SELECTOR";
    case ErrorCode::kInvalidParams:
      return "INVALID_PARAMS";
    case ErrorCode::kWebviewError:
      return "WEBVIEW_ERROR";
    case ErrorCode::kIframeAccessDenied:
      return "IFRAME_ACCESS_DENIED";
    case ErrorCode::kWatchNotFound:
      return "WATCH_NOT_FOUND";
    case ErrorCode::kAnnotationExpired:
      return "ANNOTATION_EXPIRED";
    case ErrorCode::kPlatformNotSupported:
      return "PLATFORM_NOT_SUPPORTED";
    case ErrorCode::kPermissionRequired:
      return "PERMISSION_REQUIRED";
    case ErrorCode::kShadowRootClosed:
      return "SHADOW_ROOT_CLOSED";
  }
  return "UNKNOWN_ERROR";
}

std::optional<ErrorCode> ErrorCodeFromString(std::string_view value) {
  if (value == "ELEMENT_NOT_FOUND") {
    return ErrorCode::kElementNotFound;
  }
  if (value == "ELEMENT_NOT_VISIBLE") {
    return ErrorCode::kElementNotVisible;
  }
  if (value == "TIMEOUT") {
    return ErrorCode::kTimeout;
  }
  if (value == "NAVIGATION_ERROR") {
    return ErrorCode::kNavigationError;
  }
  if (value == "INVALID_SELECTOR") {
    return ErrorCode::kInvalidSelector;
  }
  if (value == "INVALID_PARAMS") {
    return ErrorCode::kInvalidParams;
  }
  if (value == "WEBVIEW_ERROR") {
    return ErrorCode::kWebviewError;
  }
  if (value == "IFRAME_ACCESS_DENIED") {
    return ErrorCode::kIframeAccessDenied;
  }
  if (value == "WATCH_NOT_FOUND") {
    return ErrorCode::kWatchNotFound;
  }
  if (value == "ANNOTATION_EXPIRED") {
    return ErrorCode::kAnnotationExpired;
  }
  if (value == "PLATFORM_NOT_SUPPORTED") {
    return ErrorCode::kPlatformNotSupported;
  }
  if (value == "PERMISSION_REQUIRED") {
    return ErrorCode::kPermissionRequired;
  }
  if (value == "SHADOW_ROOT_CLOSED") {
    return ErrorCode::kShadowRootClosed;
  }
  return std::nullopt;
}

std::int32_t ErrorCodeHttpStatus(ErrorCode code) {
  switch (code) {
    case ErrorCode::kElementNotFound:
      return 404;
    case ErrorCode::kElementNotVisible:
      return 400;
    case ErrorCode::kTimeout:
      return 408;
    case ErrorCode::kNavigationError:
      return 502;
    case ErrorCode::kInvalidSelector:
      return 400;
    case ErrorCode::kInvalidParams:
      return 400;
    case ErrorCode::kWebviewError:
      return 500;
    case ErrorCode::kIframeAccessDenied:
      return 403;
    case ErrorCode::kWatchNotFound:
      return 404;
    case ErrorCode::kAnnotationExpired:
      return 400;
    case ErrorCode::kPlatformNotSupported:
      return 501;
    case ErrorCode::kPermissionRequired:
      return 403;
    case ErrorCode::kShadowRootClosed:
      return 403;
  }
  return 500;
}

}  // namespace kelpie

extern "C" {

const char* kelpie_error_code_name(KelpieErrorCode code) {
  return kelpie::ErrorCodeToString(static_cast<kelpie::ErrorCode>(code));
}

int32_t kelpie_error_http_status(KelpieErrorCode code) {
  return kelpie::ErrorCodeHttpStatus(static_cast<kelpie::ErrorCode>(code));
}

}  // extern "C"
