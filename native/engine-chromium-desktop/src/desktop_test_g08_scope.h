#pragma once
#if defined(KELPIE_TEST_G08_ROI_WITNESS)
#include <winsock2.h>
#include <windows.h>
#include <iphlpapi.h>
#include <cstdlib>
#include <cstddef>
#include <iterator>
#include <limits>
#include <regex>
#include <string>
#include <vector>

namespace kelpie {
// A fixture URL and PID are private harness inputs, never report fields. This
// guard pins the exact live listener process, including creation time and path.
class TestG08Scope {
 public:
  TestG08Scope() {
    const auto url = Environment("KELPIE_TEST_G08_URL");
    const auto pid = Environment("KELPIE_TEST_G08_FIXTURE_PID");
    const auto path = Environment("KELPIE_TEST_G08_FIXTURE_EXE");
    if (url.empty() || pid.empty() || path.empty()) return;
    expected_url_ = url;
    std::smatch match;
    if (!std::regex_match(expected_url_, match,
        std::regex("^http://127\\.0\\.0\\.1:([1-9][0-9]{0,4})/g08/[a-f0-9]{32}$"))) return;
    if (!std::regex_match(pid, std::regex("^[1-9][0-9]{0,9}$"))) return;
    try {
      const auto port = std::stoull(match[1].str()), process = std::stoull(pid);
      if (port > 65535 || process == 0 || process > std::numeric_limits<DWORD>::max()) return;
      port_ = static_cast<unsigned short>(port); pid_ = static_cast<DWORD>(process);
    } catch (...) { return; }
    const auto needed = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path.c_str(), -1, nullptr, 0);
    if (needed <= 1 || needed > 32768) return;
    std::wstring wide(static_cast<std::size_t>(needed), L'\0');
    if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path.c_str(), -1, wide.data(), needed)) return;
    wide.pop_back();
    process_ = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, FALSE, pid_);
    if (!process_) return;
    wchar_t actual[32768]; DWORD count = static_cast<DWORD>(std::size(actual));
    if (!QueryFullProcessImageNameW(process_, 0, actual, &count) ||
        CompareStringOrdinal(actual, static_cast<int>(count), wide.c_str(), static_cast<int>(wide.size()), TRUE) != CSTR_EQUAL ||
        !GetProcessTimes(process_, &creation_, &exit_, &kernel_, &user_)) return;
    initialized_ = true;
  }
  ~TestG08Scope() { if (process_) CloseHandle(process_); }
  TestG08Scope(const TestG08Scope&) = delete;
  TestG08Scope& operator=(const TestG08Scope&) = delete;
  bool ListenerOwned() const {
    if (!initialized_ || WaitForSingleObject(process_, 0) != WAIT_TIMEOUT) return false;
    FILETIME creation{}, exit{}, kernel{}, user{};
    if (!GetProcessTimes(process_, &creation, &exit, &kernel, &user) ||
        CompareFileTime(&creation, &creation_) != 0) return false;
    ULONG size = 0;
    if (GetExtendedTcpTable(nullptr, &size, FALSE, AF_INET, TCP_TABLE_OWNER_PID_LISTENER, 0) != ERROR_INSUFFICIENT_BUFFER ||
        size == 0 || size > 1024 * 1024) return false;
    std::vector<unsigned char> storage(size);
    if (GetExtendedTcpTable(storage.data(), &size, FALSE, AF_INET, TCP_TABLE_OWNER_PID_LISTENER, 0) != NO_ERROR) return false;
    const auto* table = reinterpret_cast<const MIB_TCPTABLE_OWNER_PID*>(storage.data());
    if (size < offsetof(MIB_TCPTABLE_OWNER_PID, table) || table->dwNumEntries >
        (size - offsetof(MIB_TCPTABLE_OWNER_PID, table)) / sizeof(MIB_TCPROW_OWNER_PID)) return false;
    unsigned matches = 0;
    for (DWORD index = 0; index < table->dwNumEntries; ++index) {
      const auto& row = table->table[index];
      if (row.dwLocalAddr == htonl(INADDR_LOOPBACK) && ntohs(static_cast<u_short>(row.dwLocalPort)) == port_) {
        if (row.dwOwningPid != pid_) return false;
        ++matches;
      }
    }
    // Close the PID-reuse window while inspecting the socket table.
    return matches == 1 && WaitForSingleObject(process_, 0) == WAIT_TIMEOUT;
  }
  bool MatchesUrl(const std::string& url) const { return initialized_ && url == expected_url_; }
 private:
  static std::string Environment(const char* name) {
    char* value = nullptr; std::size_t size = 0;
    if (_dupenv_s(&value, &size, name) != 0 || !value) return {};
    std::string result;
    if (size > 1 && size <= 32768) result.assign(value, size - 1);
    std::free(value);
    return result;
  }
  std::string expected_url_;
  HANDLE process_ = nullptr;
  DWORD pid_ = 0;
  unsigned short port_ = 0;
  FILETIME creation_{}, exit_{}, kernel_{}, user_{};
  bool initialized_ = false;
};
}  // namespace kelpie
#endif
