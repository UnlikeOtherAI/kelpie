#pragma once
#include "kelpie/response_helpers.h"
#include <nlohmann/json.hpp>
#include <string>

namespace kelpie {
// Error precedence may change, but a dispatched mutation's uncertainty must not.
inline nlohmann::json ReplaceScriptErrorPreservingUncertainty(
    const nlohmann::json& previous, const std::string& code, const std::string& message) {
  const bool uncertain = previous.value("mayHaveCompleted", false);
  auto result = ErrorResponse(code, message);
  if (uncertain) result["mayHaveCompleted"] = true;
  return result;
}
}
