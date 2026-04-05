#include "windows_app.h"

#include <set>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <winsock2.h>
#include <ws2tcpip.h>

#include "kelpie/error_codes.h"
#include "kelpie/platform.h"
#include "kelpie/response_helpers.h"

namespace kelpie::windows {
namespace {

constexpr char kAppVersion[] = "0.1.0";

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return {};
  }
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, nullptr, 0);
  std::wstring output(static_cast<std::size_t>(size > 0 ? size - 1 : 0), L'\0');
  if (size > 1) {
    MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, output.data(), size - 1);
  }
  return output;
}

std::set<std::string> UnsupportedMethods(const McpRegistry& registry) {
  std::set<std::string> methods;
  for (const auto& tool : registry.all_tools()) {
    methods.insert(tool.http_endpoint);
  }
  methods.insert("get-capabilities");
  methods.insert("get-renderer");
  methods.insert("set-renderer");
  return methods;
}

}  // namespace

void WindowsApp::StartHttpServer() {
  StopHttpServer();
  config_.port = static_cast<int>(FindAvailablePort(static_cast<std::uint16_t>(config_.port)));
  RefreshDeviceInfo();

  http_server_ = std::make_unique<httplib::Server>();
  http_server_->Get("/health", [](const httplib::Request&, httplib::Response& response) {
    response.set_header("Access-Control-Allow-Origin", "*");
    response.set_content(R"({"status":"ok"})", "application/json");
  });
  http_server_->Options(R"(.*)", [](const httplib::Request&, httplib::Response& response) {
    response.set_header("Access-Control-Allow-Origin", "*");
    response.set_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    response.set_header("Access-Control-Allow-Headers", "Content-Type");
  });
  http_server_->Post(R"(/v1/(.+))", [this](const httplib::Request& request, httplib::Response& response) {
    response.set_header("Access-Control-Allow-Origin", "*");
    json body = json::object();
    if (!request.body.empty()) {
      body = json::parse(request.body, nullptr, false);
      if (body.is_discarded()) {
        response.status = 400;
        response.set_content(ErrorResponse(ErrorCode::kInvalidParams, "Invalid JSON body").dump(),
                             "application/json");
        return;
      }
    }

    int status_code = 200;
    const json payload = HandleApiMethod(request.matches[1].str(), body, status_code);
    response.status = status_code;
    response.set_content(payload.dump(), "application/json");
  });

  http_thread_ = std::thread([this] {
    http_running_ = true;
    http_server_->listen("0.0.0.0", config_.port);
    http_running_ = false;
  });
}

void WindowsApp::StopHttpServer() {
  if (http_server_ != nullptr) {
    http_server_->stop();
  }
  if (http_thread_.joinable()) {
    http_thread_.join();
  }
  http_server_.reset();
}

std::uint16_t WindowsApp::FindAvailablePort(std::uint16_t preferred_port) const {
  WSADATA data{};
  WSAStartup(MAKEWORD(2, 2), &data);
  for (std::uint16_t port = preferred_port; port < preferred_port + 32; ++port) {
    SOCKET sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_ANY);
    address.sin_port = htons(port);
    const bool available = bind(sock, reinterpret_cast<sockaddr*>(&address), sizeof(address)) == 0;
    closesocket(sock);
    if (available) {
      WSACleanup();
      return port;
    }
  }
  WSACleanup();
  return preferred_port;
}

void WindowsApp::StartMdns() {
  mdns_->Start({
      device_info_.name,
      static_cast<std::uint16_t>(device_info_.port),
      ToTxtRecord(device_info_),
  });
}

void WindowsApp::StopMdns() {
  mdns_->Stop();
}

DeviceInfo WindowsApp::BuildDeviceInfo() const {
  return device_info_provider_.Collect(config_.port, config_.width, config_.height, kAppVersion);
}

WindowsApp::json WindowsApp::HandleApiMethod(const std::string& method, const json& body, int& status_code) {
  static const std::set<std::string> supported_methods = {
      "navigate", "back", "forward", "reload", "get-current-url", "get-device-info", "toast",
      "get-bookmarks", "get-history", "get-network-log", "clear-history", "clear-bookmarks",
      "clear-network-log", "get-capabilities", "get-renderer", "set-renderer",
  };
  if (supported_methods.count(method) != 0) {
    return HandleSupportedMethod(method, body, status_code);
  }
  if (UnsupportedMethods(mcp_registry_).count(method) != 0) {
    return UnsupportedResponse(method, status_code);
  }
  return UnknownMethodResponse(method, status_code);
}

WindowsApp::json WindowsApp::HandleSupportedMethod(const std::string& method,
                                                   const json& body,
                                                   int& status_code) {
  if (method == "navigate") {
    const std::string url = body.value("url", "");
    if (url.empty()) {
      status_code = ErrorCodeHttpStatus(ErrorCode::kInvalidParams);
      return ErrorResponse(ErrorCode::kInvalidParams, "url is required");
    }
    OnNavigateRequested(url);
    return SuccessResponse({{"url", url}});
  }
  if (method == "back") {
    OnBackRequested();
    return SuccessResponse();
  }
  if (method == "forward") {
    OnForwardRequested();
    return SuccessResponse();
  }
  if (method == "reload") {
    OnReloadRequested();
    return SuccessResponse();
  }
  if (method == "get-current-url") {
    return CurrentUrlResponse();
  }
  if (method == "get-device-info") {
    RefreshDeviceInfo();
    return SuccessResponse({{"device", ToJson(device_info_)}});
  }
  if (method == "toast") {
    const std::wstring message = Utf8ToWide(body.value("message", ""));
    if (message.empty()) {
      status_code = ErrorCodeHttpStatus(ErrorCode::kInvalidParams);
      return ErrorResponse(ErrorCode::kInvalidParams, "message is required");
    }
    shell_->ShowToast(message);
    return SuccessResponse({{"message", body.value("message", "")}});
  }
  if (method == "get-bookmarks") {
    return SuccessResponse({{"items", json::parse(bookmark_store_.ToJson())}});
  }
  if (method == "get-history") {
    return SuccessResponse({{"items", json::parse(history_store_.ToJson())}});
  }
  if (method == "get-network-log") {
    return SuccessResponse({{"items", json::parse(network_store_.ToJson())}});
  }
  if (method == "clear-bookmarks") {
    bookmark_store_.RemoveAll();
    return SuccessResponse();
  }
  if (method == "clear-history") {
    history_store_.Clear();
    return SuccessResponse();
  }
  if (method == "clear-network-log") {
    network_store_.Clear();
    return SuccessResponse();
  }
  if (method == "get-capabilities") {
    const auto capabilities = mcp_registry_.get_capabilities(Platform::kWindows, "chromium");
    return SuccessResponse({
        {"supported", capabilities.supported},
        {"partial", capabilities.partial},
        {"unsupported", capabilities.unsupported},
    });
  }
  if (method == "get-renderer") {
    return SuccessResponse({{"current", "chromium"}, {"available", json::array({"chromium"})}});
  }

  status_code = ErrorCodeHttpStatus(ErrorCode::kPlatformNotSupported);
  return ErrorResponse(ErrorCode::kPlatformNotSupported, "Windows only supports chromium");
}

WindowsApp::json WindowsApp::UnsupportedResponse(const std::string& method, int& status_code) const {
  status_code = ErrorCodeHttpStatus(ErrorCode::kPlatformNotSupported);
  return ErrorResponse(ErrorCode::kPlatformNotSupported, method + " is not yet implemented on Windows");
}

WindowsApp::json WindowsApp::UnknownMethodResponse(const std::string& method, int& status_code) const {
  status_code = 404;
  return ErrorResponse("NOT_FOUND", "Unknown method: " + method);
}

WindowsApp::json WindowsApp::CurrentUrlResponse() const {
  return SuccessResponse({
      {"url", browser_view_->CurrentUrl()},
      {"title", browser_view_->CurrentTitle()},
      {"is_loading", browser_view_->IsLoading()},
      {"can_go_back", browser_view_->CanGoBack()},
      {"can_go_forward", browser_view_->CanGoForward()},
  });
}

}  // namespace kelpie::windows
