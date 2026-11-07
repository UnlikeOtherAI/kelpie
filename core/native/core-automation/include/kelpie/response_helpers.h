#pragma once

#include <string_view>

#include <nlohmann/json.hpp>

#include "kelpie/error_codes.h"

namespace kelpie {

nlohmann::json SuccessResponse(
    const nlohmann::json& data = nlohmann::json::object());
nlohmann::json ErrorResponse(ErrorCode code, std::string_view message);
nlohmann::json ErrorResponse(ErrorCode code,
                            std::string_view message,
                            const nlohmann::json& diagnostics);
nlohmann::json ErrorResponse(std::string_view code, std::string_view message);
nlohmann::json ErrorResponse(std::string_view code,
                            std::string_view message,
                            const nlohmann::json& diagnostics);

}  // namespace kelpie
