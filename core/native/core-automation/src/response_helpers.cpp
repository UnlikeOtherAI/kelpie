#include "kelpie/response_helpers.h"

#include <stdexcept>

namespace kelpie {

nlohmann::json SuccessResponse(const nlohmann::json& data) {
  nlohmann::json response = {{"success", true}};
  if (data.is_null()) {
    return response;
  }
  if (!data.is_object()) {
    throw std::invalid_argument("SuccessResponse data must be an object");
  }

  for (auto it = data.begin(); it != data.end(); ++it) {
    response[it.key()] = it.value();
  }
  return response;
}

nlohmann::json ErrorResponse(ErrorCode code, std::string_view message) {
  return ErrorResponse(ErrorCodeToString(code), message);
}

nlohmann::json ErrorResponse(ErrorCode code,
                             std::string_view message,
                             const nlohmann::json& diagnostics) {
  return ErrorResponse(ErrorCodeToString(code), message, diagnostics);
}

nlohmann::json ErrorResponse(std::string_view code, std::string_view message) {
  return {
      {"success", false},
      {"error", {{"code", code}, {"message", message}}},
  };
}

nlohmann::json ErrorResponse(std::string_view code,
                             std::string_view message,
                             const nlohmann::json& diagnostics) {
  nlohmann::json error = {{"code", code}, {"message", message}};
  if (diagnostics.is_object() && !diagnostics.empty()) {
    error["diagnostics"] = diagnostics;
  }
  return {
      {"success", false},
      {"error", error},
  };
}

}  // namespace kelpie
