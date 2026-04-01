#pragma once

#include <string_view>

#include <nlohmann/json.hpp>

#include "mollotov/error_codes.h"

namespace mollotov {

nlohmann::json SuccessResponse(
    const nlohmann::json& data = nlohmann::json::object());
nlohmann::json ErrorResponse(ErrorCode code, std::string_view message);
nlohmann::json ErrorResponse(std::string_view code, std::string_view message);

}  // namespace mollotov
