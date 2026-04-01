#include "mollotov/automation_c_api.h"
#include "mollotov/response_helpers.h"

#include <cassert>
#include <iostream>
#include <stdexcept>

#include <nlohmann/json.hpp>

namespace {

using json = nlohmann::json;

void TestSuccessResponseMergesObjects() {
  const json response = mollotov::SuccessResponse(
      {{"url", "https://example.com"}, {"title", "Example"}});
  assert(response["success"] == true);
  assert(response["url"] == "https://example.com");
  assert(response["title"] == "Example");
}

void TestSuccessResponseRejectsNonObjectPayload() {
  bool threw = false;
  try {
    (void)mollotov::SuccessResponse(json::array({1, 2, 3}));
  } catch (const std::invalid_argument&) {
    threw = true;
  }
  assert(threw);
}

void TestErrorResponseFormatsCodes() {
  const json enum_response =
      mollotov::ErrorResponse(mollotov::ErrorCode::kInvalidParams, "Bad request");
  assert(enum_response["success"] == false);
  assert(enum_response["error"]["code"] == "INVALID_PARAMS");
  assert(enum_response["error"]["message"] == "Bad request");

  const json string_response = mollotov::ErrorResponse("NO_WEBVIEW", "No WebView");
  assert(string_response["error"]["code"] == "NO_WEBVIEW");
  assert(string_response["error"]["message"] == "No WebView");
}

void TestResponseCApiFormatting() {
  char* success = mollotov_success_response(R"({"value":"ok"})");
  assert(success != nullptr);
  const json success_json = json::parse(success);
  mollotov_free_string(success);
  assert(success_json["success"] == true);
  assert(success_json["value"] == "ok");

  char* empty = mollotov_success_response(nullptr);
  assert(empty != nullptr);
  const json empty_json = json::parse(empty);
  mollotov_free_string(empty);
  assert(empty_json == json({{"success", true}}));

  char* invalid = mollotov_success_response(R"([1,2,3])");
  assert(invalid == nullptr);

  char* error = mollotov_error_response("NO_WEBVIEW", "No WebView");
  assert(error != nullptr);
  const json error_json = json::parse(error);
  mollotov_free_string(error);
  assert(error_json["success"] == false);
  assert(error_json["error"]["code"] == "NO_WEBVIEW");
}

}  // namespace

int main() {
  try {
    TestSuccessResponseMergesObjects();
    TestSuccessResponseRejectsNonObjectPayload();
    TestErrorResponseFormatsCodes();
    TestResponseCApiFormatting();
    return 0;
  } catch (const std::exception& exception) {
    std::cerr << exception.what() << '\n';
    return 1;
  }
}
