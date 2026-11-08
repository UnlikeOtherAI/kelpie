#include "inference_transport.h"
#include "windows_utf.h"
#include <windows.h>
#include <winhttp.h>
#include <algorithm>
#include <chrono>
#include <cwctype>
#include <memory>

namespace kelpie::windows {
using json = nlohmann::json;
namespace {
struct Close { void operator()(void* value) const { if (value) WinHttpCloseHandle(value); } };
using Internet = std::unique_ptr<void, Close>;
void Require(BOOL ok) {
  if (!ok) throw InferenceError(GetLastError() == ERROR_WINHTTP_TIMEOUT ? "ENDPOINT_TIMEOUT" : "ENDPOINT_UNREACHABLE",
                                "The inference server did not respond; check its address and availability");
}
}
InferenceURL ParseInferenceURL(const std::string& input) {
  auto raw = input;
  const auto begin = raw.find_first_not_of(" \t\r\n");
  if (begin == std::string::npos) throw InferenceError("INVALID_ENDPOINT_URL", "Enter an HTTP or HTTPS endpoint");
  raw = raw.substr(begin, raw.find_last_not_of(" \t\r\n") - begin + 1);
  if (raw.find_first_of("?#\r\n\t \\") != std::string::npos)
    throw InferenceError("INVALID_ENDPOINT_URL", "Endpoint must not contain a query, fragment or whitespace");
  auto decoded = utf::Utf8ToWide(raw);
  if (!decoded) throw InferenceError("INVALID_ENDPOINT_URL", "Endpoint must contain valid UTF-8");
  auto wide = *decoded;
  URL_COMPONENTS parts{}; parts.dwStructSize = sizeof(parts);
  parts.dwHostNameLength = parts.dwUrlPathLength = parts.dwUserNameLength = parts.dwPasswordLength = static_cast<DWORD>(-1);
  if (!WinHttpCrackUrl(wide.c_str(), wide.size(), 0, &parts) || parts.dwHostNameLength == 0 ||
      parts.dwUserNameLength || parts.dwPasswordLength || !parts.nPort ||
      (parts.nScheme != INTERNET_SCHEME_HTTP && parts.nScheme != INTERNET_SCHEME_HTTPS))
    throw InferenceError("INVALID_ENDPOINT_URL", "Use an HTTP or HTTPS URL without credentials");
  std::wstring host(parts.lpszHostName, parts.dwHostNameLength);
  std::transform(host.begin(), host.end(), host.begin(), towlower);
  std::wstring path(parts.lpszUrlPath ? parts.lpszUrlPath : L"", parts.dwUrlPathLength);
  for (size_t at; (at = path.find(L"//")) != std::wstring::npos;) path.erase(at, 1);
  while (!path.empty() && path.back() == L'/') path.pop_back();
  for (const auto* suffix : {L"/chat/completions", L"/completions", L"/models", L"/embeddings"}) {
    const std::wstring ending(suffix);
    if (path.size() >= ending.size() && path.compare(path.size() - ending.size(), ending.size(), ending) == 0) {
      path.resize(path.size() - ending.size()); break;
    }
  }
  if (path.empty()) path = L"/v1";
  const bool secure = parts.nScheme == INTERNET_SCHEME_HTTPS;
  const auto authority = host.find(L':') != std::wstring::npos && host.front() != L'[' ? L"[" + host + L"]" : host;
  auto base = std::wstring(secure ? L"https://" : L"http://") + authority;
  if (parts.nPort != (secure ? 443 : 80)) base += L":" + std::to_wstring(parts.nPort);
  base += path;
  const bool loopback = host == L"localhost" || host == L"127.0.0.1" || host == L"::1" || host == L"[::1]";
  return {utf::WideToUtf8(base).value(), host, path, parts.nPort, secure, loopback};
}
int InferenceTransport::Cancel() {
  std::lock_guard lock(mutex_);
  ++generation_;
  const auto count = requests_.size();
  for (auto request : requests_) WinHttpCloseHandle(request);
  requests_.clear();
  return static_cast<int>(count);
}
json InferenceTransport::Request(const std::string& base, const std::string& operation,
                                 const std::string& key, const json* body) {
  if (key.find_first_of("\r\n") != std::string::npos) throw InferenceError("INVALID_PARAM", "Invalid API key");
  auto url = ParseInferenceURL(base);
  const auto generation = generation_.load();
  Internet session(WinHttpOpen(L"Kelpie inference", WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
                              WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0));
  if (!session) throw InferenceError("ENDPOINT_UNREACHABLE", "Could not start the inference connection");
  const int timeout = body ? 180000 : 8000;
  Require(WinHttpSetTimeouts(session.get(), 8000, 8000, timeout, timeout));
  Internet connection(WinHttpConnect(session.get(), url.host.c_str(), url.port, 0));
  if (!connection) throw InferenceError("ENDPOINT_UNREACHABLE", "Could not connect to inference server");
  auto path = url.path + L"/" + utf::Utf8ToWideDisplay(operation);
  const auto payload = body ? body->dump() : std::string();
  for (int redirect = 0; redirect < 4; ++redirect) {
    auto* request = WinHttpOpenRequest(connection.get(), body ? L"POST" : L"GET", path.c_str(), nullptr,
        WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, url.secure ? WINHTTP_FLAG_SECURE : 0);
    if (!request) throw InferenceError("ENDPOINT_UNREACHABLE", "Could not open inference request");
    { std::lock_guard lock(mutex_); if (generation != generation_) { WinHttpCloseHandle(request);
        throw InferenceError("INFERENCE_CANCELLED", "Inference cancelled"); } requests_.insert(request); }
    auto cleanup = [this, request, generation](void*) { std::lock_guard lock(mutex_);
      if (generation == generation_ && requests_.erase(request)) WinHttpCloseHandle(request); };
    std::unique_ptr<void, decltype(cleanup)> guard(request, cleanup);
    try {
      DWORD disabled = WINHTTP_DISABLE_REDIRECTS | WINHTTP_DISABLE_COOKIES | WINHTTP_DISABLE_AUTHENTICATION;
      Require(WinHttpSetOption(request, WINHTTP_OPTION_DISABLE_FEATURE, &disabled, sizeof(disabled)));
      std::wstring headers = L"Content-Type: application/json\r\nAccept: application/json\r\n";
      if (!key.empty()) headers += L"Authorization: Bearer " + utf::Utf8ToWideDisplay(key) + L"\r\n";
      Require(WinHttpSendRequest(request, headers.c_str(), headers.size(),
          payload.empty() ? WINHTTP_NO_REQUEST_DATA : const_cast<char*>(payload.data()), payload.size(), payload.size(), 0));
      Require(WinHttpReceiveResponse(request, nullptr));
      DWORD status = 0, length = sizeof(status);
      Require(WinHttpQueryHeaders(request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
          WINHTTP_HEADER_NAME_BY_INDEX, &status, &length, WINHTTP_NO_HEADER_INDEX));
      if (status >= 300 && status < 400) {
        wchar_t location[8192]{}; length = sizeof(location);
        Require(WinHttpQueryHeaders(request, WINHTTP_QUERY_LOCATION, WINHTTP_HEADER_NAME_BY_INDEX,
                                    location, &length, WINHTTP_NO_HEADER_INDEX));
        std::wstring target(location);
        // Preserve POST only for redirects whose semantics preserve the body.
        if (body && status != 307 && status != 308)
          throw InferenceError("ENDPOINT_REDIRECT_REFUSED", "This redirect would change the inference request");
        if (target.starts_with(L"/") && !target.starts_with(L"//")) path = target;
        else {
          const auto next = ParseInferenceURL(utf::WideToUtf8(target).value());
          if (next.host != url.host || next.port != url.port || next.secure != url.secure)
            throw InferenceError("ENDPOINT_REDIRECT_REFUSED", "Refused an inference redirect to another origin");
          // Parsing a base strips operation suffixes; preserve the actual redirect path.
          const auto slash = target.find(L'/', target.find(L"://") + 3);
          path = slash == std::wstring::npos ? L"/" : target.substr(slash);
        }
        continue;
      }
      if (status == 401 || status == 403) throw InferenceError("ENDPOINT_AUTH_FAILED", "The inference server rejected its API key");
      if (!body && (status == 404 || status == 405 || status == 501))
        throw InferenceError("MODEL_DISCOVERY_UNSUPPORTED", "Enter a model ID and run a generation test");
      if (status == 429) throw InferenceError("AI_BUSY", "The inference server is busy");
      if (status == 503) throw InferenceError("ENDPOINT_LOADING", "The inference server is loading or busy");
      if (status < 200 || status >= 300) throw InferenceError("ENDPOINT_ERROR", "Inference server returned HTTP " + std::to_string(status));
      std::string response;
      const auto deadline = std::chrono::steady_clock::now() + std::chrono::minutes(15);
      char buffer[8192];
      for (;;) {
        DWORD read = 0; Require(WinHttpReadData(request, buffer, sizeof(buffer), &read));
        if (!read) break;
        if (response.size() + read > 8 * 1024 * 1024 || std::chrono::steady_clock::now() > deadline)
          throw InferenceError("ENDPOINT_MALFORMED_RESPONSE", "Inference response exceeded its limit");
        response.append(buffer, read);
      }
      auto result = json::parse(response, nullptr, false);
      if (!result.is_object()) throw InferenceError("ENDPOINT_MALFORMED_RESPONSE", "Inference server did not return a JSON object");
      return result;
    } catch (...) {
      if (generation != generation_) throw InferenceError("INFERENCE_CANCELLED", "Inference cancelled");
      throw;
    }
  }
  throw InferenceError("ENDPOINT_REDIRECT_REFUSED", "Too many inference redirects");
}
}
