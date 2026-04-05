#include "kelpie/desktop_router.h"

#include <algorithm>
#include <stdexcept>

#include "kelpie/error_codes.h"
#include "kelpie/response_helpers.h"

namespace kelpie {
namespace {

int StatusForResponse(const nlohmann::json& response) {
  if (response.value("success", false)) {
    return 200;
  }
  const nlohmann::json error = response.value("error", nlohmann::json::object());
  const std::string code = error.value("code", std::string());
  if (code == "NOT_FOUND") {
    return 404;
  }
  if (const auto parsed = ErrorCodeFromString(code); parsed.has_value()) {
    return ErrorCodeHttpStatus(*parsed);
  }
  return 400;
}

}  // namespace

void DesktopRouter::Register(std::string method, Handler handler) {
  handlers_[std::move(method)] = std::move(handler);
}

bool DesktopRouter::Has(std::string_view method) const {
  return handlers_.find(std::string(method)) != handlers_.end();
}

DesktopRouter::Result DesktopRouter::Dispatch(std::string_view method, const json& params) const {
  const auto it = handlers_.find(std::string(method));
  if (it == handlers_.end()) {
    const json body = ErrorResponse("NOT_FOUND", std::string("Unknown method: ") + std::string(method));
    return {404, body};
  }

  try {
    const json body = it->second(params);
    return {StatusForResponse(body), body};
  } catch (const std::invalid_argument& exception) {
    const json body = ErrorResponse(ErrorCode::kInvalidParams, exception.what());
    return {StatusForResponse(body), body};
  } catch (const std::exception& exception) {
    const json body = ErrorResponse(ErrorCode::kWebviewError, exception.what());
    return {StatusForResponse(body), body};
  }
}

std::vector<std::string> DesktopRouter::RegisteredMethods() const {
  std::vector<std::string> methods;
  methods.reserve(handlers_.size());
  for (const auto& entry : handlers_) {
    methods.push_back(entry.first);
  }
  std::sort(methods.begin(), methods.end());
  return methods;
}

}  // namespace kelpie
