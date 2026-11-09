#pragma once

#include <optional>
#include <string>

namespace kelpie::site_preview {

// Turns a base64 viewport capture (JPEG or PNG, as DevTools returns it) into
// the stored preview JPEG: cropped to 16:10 from the top, scaled down to the
// preview size and re-encoded. Returns nullopt when the capture cannot be
// decoded or shows nothing yet. Chromium builds decode and encode with
// CefImage; the no-CEF build has no captures and always returns nullopt.
std::optional<std::string> EncodePreview(const std::string& capture_base64);

}  // namespace kelpie::site_preview
