#include "site_preview_codec.h"

namespace kelpie::site_preview {

// Without Chromium there is no capture to encode.
std::optional<std::string> EncodePreview(const std::string&) { return std::nullopt; }

}  // namespace kelpie::site_preview
