#include "mollotov/automation_c_api.h"

#include <cstring>
#include <new>
#include <string>

#include <nlohmann/json.hpp>

#include "mollotov/handler_context.h"
#include "mollotov/response_helpers.h"

struct MollotovHandlerContext {
  mollotov::HandlerContext context;
};

namespace {

using json = nlohmann::json;

const char* SafeCString(const char* value) {
  return value == nullptr ? "" : value;
}

char* CopyString(const std::string& value) {
  char* buffer = new (std::nothrow) char[value.size() + 1];
  if (buffer == nullptr) {
    return nullptr;
  }
  std::memcpy(buffer, value.c_str(), value.size() + 1);
  return buffer;
}

json ParseResponseObject(const char* json_data) {
  if (json_data == nullptr || json_data[0] == '\0') {
    return json::object();
  }

  const json parsed = json::parse(json_data, nullptr, false);
  if (!parsed.is_object()) {
    throw std::invalid_argument("response data must be a JSON object");
  }
  return parsed;
}

}  // namespace

extern "C" {

void mollotov_free_string(char* str) {
  delete[] str;
}

MollotovHandlerContextRef mollotov_handler_context_create(void) {
  return new (std::nothrow) MollotovHandlerContext();
}

char* mollotov_handler_context_evaluate_js(MollotovHandlerContextRef ref,
                                           const char* script) {
  if (ref == nullptr) {
    return nullptr;
  }
  try {
    return CopyString(ref->context.EvaluateJsReturningString(SafeCString(script)));
  } catch (...) {
    return nullptr;
  }
}

char* mollotov_success_response(const char* json_data) {
  try {
    return CopyString(mollotov::SuccessResponse(ParseResponseObject(json_data)).dump());
  } catch (...) {
    return nullptr;
  }
}

char* mollotov_error_response(const char* code, const char* message) {
  try {
    return CopyString(
        mollotov::ErrorResponse(SafeCString(code), SafeCString(message)).dump());
  } catch (...) {
    return nullptr;
  }
}

void mollotov_handler_context_destroy(MollotovHandlerContextRef ref) {
  delete ref;
}

}  // extern "C"
