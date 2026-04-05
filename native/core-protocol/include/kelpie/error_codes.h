#pragma once

#include <cstdint>
#include <optional>
#include <string_view>

namespace kelpie {

enum class ErrorCode {
  kElementNotFound = 0,
  kElementNotVisible,
  kTimeout,
  kNavigationError,
  kInvalidSelector,
  kInvalidParams,
  kWebviewError,
  kIframeAccessDenied,
  kWatchNotFound,
  kAnnotationExpired,
  kPlatformNotSupported,
  kPermissionRequired,
  kShadowRootClosed,
};

const char* ErrorCodeToString(ErrorCode code);
std::optional<ErrorCode> ErrorCodeFromString(std::string_view value);
std::int32_t ErrorCodeHttpStatus(ErrorCode code);

}  // namespace kelpie
