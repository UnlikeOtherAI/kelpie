#include "account_transport.h"
#include <windows.h>
#include <winhttp.h>
#include <chrono>
#include <memory>

namespace kelpie::account {
namespace {
struct CloseInternet { void operator()(void* h) const { if (h) WinHttpCloseHandle(h); } };
using Internet = std::unique_ptr<void, CloseInternet>;
std::wstring Wide(const std::string& s) {
  const int size=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,s.data(),static_cast<int>(s.size()),nullptr,0);
  std::wstring result(size,0);
  MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,s.data(),static_cast<int>(s.size()),result.data(),size);
  return result;
}
void Require(BOOL ok) { if (!ok) throw AccountFailure(0); }
}
void AccountTransport::Cancel() {
  std::lock_guard lock(mutex_);
  ++generation_; cancelled_=true;
  if (active_) WinHttpCloseHandle(active_);
  active_ = nullptr;
}
AccountResponse AccountTransport::Request(const std::string& path, const std::string& method,
    const std::string& token, const std::string& body, const std::string& version) {
  if (!path.starts_with("/oauth/") || path.find("..") != std::string::npos ||
      token.find_first_of("\r\n") != std::string::npos || version.find_first_of("\r\n") != std::string::npos)
    throw AccountFailure(400);
  unsigned generation;
  { std::lock_guard lock(mutex_); if (cancelled_) throw AccountFailure(0); generation = generation_; }
  Internet session(WinHttpOpen(L"Kelpie Windows", WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
      WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0));
  if (!session) throw AccountFailure(0);
  Require(WinHttpSetTimeouts(session.get(), 2500, 2500, 2500, 2500));
  Internet connection(WinHttpConnect(session.get(), L"authentication.unlikeotherai.com", 443, 0));
  if (!connection) throw AccountFailure(0);
  auto request = WinHttpOpenRequest(connection.get(), Wide(method).c_str(), Wide(path).c_str(),
      nullptr, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, WINHTTP_FLAG_SECURE);
  if (!request) throw AccountFailure(0);
  {
    std::lock_guard lock(mutex_);
    if (generation != generation_ || active_) { WinHttpCloseHandle(request); throw AccountFailure(0); }
    active_ = request;
  }
  // Cancel owns closing an active handle; the scope guard closes it only if still owned.
  auto cleanup = [this, request, generation](void*) { std::lock_guard lock(mutex_);
    if (active_ == request && generation_ == generation) { WinHttpCloseHandle(request); active_ = nullptr; } };
  std::unique_ptr<void, decltype(cleanup)> guard(request, cleanup);
  DWORD disabled = WINHTTP_DISABLE_COOKIES | WINHTTP_DISABLE_REDIRECTS;
  Require(WinHttpSetOption(request, WINHTTP_OPTION_DISABLE_FEATURE, &disabled, sizeof(disabled)));
  std::wstring headers = L"Content-Type: application/json\r\nCache-Control: no-store\r\n";
  if (!token.empty()) headers += L"Authorization: Bearer " + Wide(token) + L"\r\n";
  if (!version.empty()) headers += L"If-Match: " + Wide(version) + L"\r\n";
  Require(WinHttpSendRequest(request, headers.c_str(), static_cast<DWORD>(headers.size()),
      body.empty() ? WINHTTP_NO_REQUEST_DATA : const_cast<char*>(body.data()),
      static_cast<DWORD>(body.size()), static_cast<DWORD>(body.size()), 0));
  Require(WinHttpReceiveResponse(request, nullptr));
  DWORD status = 0, length = sizeof(status);
  Require(WinHttpQueryHeaders(request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
      WINHTTP_HEADER_NAME_BY_INDEX, &status, &length, WINHTTP_NO_HEADER_INDEX));
  if (status < 200 || status >= 300) throw AccountFailure(static_cast<int>(status));
  AccountResponse result;
  wchar_t etag[512]{}; length = sizeof(etag);
  if (WinHttpQueryHeaders(request, WINHTTP_QUERY_ETAG, WINHTTP_HEADER_NAME_BY_INDEX,
      etag, &length, WINHTTP_NO_HEADER_INDEX)) result.version.assign(etag, etag + wcslen(etag));
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(8);
  char buffer[8192];
  for (;;) {
    DWORD read = 0;
    Require(WinHttpReadData(request, buffer, sizeof(buffer), &read));
    if (!read) break;
    if (result.body.size()+read > 2*1024*1024 || std::chrono::steady_clock::now() > deadline)
      throw AccountFailure(0);
    result.body.append(buffer, read);
  }
  return result;
}
}  // namespace kelpie::account
