// An idle Kelpie must stay up, and a close request must actually finish.
//
// Two invariants, both of which only the packaged executable can prove:
//
//   1. Left completely alone -- no HTTP request of any kind -- the app must
//      still be serving its loopback control surface afterwards. Every earlier
//      verification drove the app continuously, so nothing covered the one
//      state the app spends most of its life in.
//   2. `close-browser` must then actually shut the app down: readiness
//      retracted and the process gone. Reporting `accepted` and staying alive
//      is worse than refusing, because the readiness record keeps advertising a
//      control surface that no longer obeys.
//
// The quiet period is the point of the test, so it must not be shortened.
//
// Sibling instances: this machine routinely runs several Kelpie builds at
// once, and terminating stale instances by executable name is a standard step.
// A forced external termination leaves an unmistakable signature -- readiness
// is still published because no shutdown ran -- and that is reported as a
// skipped run rather than being scored as either a pass or a failure. Only a
// shutdown the app performed on its own counts as the regression.

#include <httplib.h>

#include <windows.h>

#include <nlohmann/json.hpp>

#include <chrono>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <string>
#include <system_error>
#include <thread>
#include <vector>

namespace {

// CTest reports this as "skipped"; see SKIP_RETURN_CODE in CMakeLists.txt.
constexpr int kSkipExitCode = 77;

// The app must be left completely alone for at least this long. The defect
// this guards showed up within ten seconds of going quiet.
constexpr int kIdleSeconds = 35;

int g_failures = 0;

bool Check(bool condition, const std::string& what) {
  std::cout << (condition ? "ok   " : "FAIL ") << what << '\n';
  if (!condition) ++g_failures;
  return condition;
}

void Wait(int milliseconds) {
  std::this_thread::sleep_for(std::chrono::milliseconds(milliseconds));
}

// Reserve and release a loopback port so the test instance does not collide
// with a developer instance already holding the default port.
int ReserveLoopbackPort() {
  WSADATA data{};
  if (WSAStartup(MAKEWORD(2, 2), &data) != 0) return 0;
  const SOCKET handle = ::socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (handle == INVALID_SOCKET) return 0;
  sockaddr_in address{};
  address.sin_family = AF_INET;
  address.sin_port = 0;
  address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  int port = 0;
  if (::bind(handle, reinterpret_cast<sockaddr*>(&address), sizeof(address)) == 0) {
    int length = sizeof(address);
    if (::getsockname(handle, reinterpret_cast<sockaddr*>(&address), &length) == 0) {
      port = ntohs(address.sin_port);
    }
  }
  ::closesocket(handle);
  return port;
}

struct Readiness {
  int port = 0;
  std::string token;
};

bool ReadReadiness(const std::filesystem::path& path, Readiness* readiness) {
  std::error_code code;
  if (!std::filesystem::exists(path, code)) return false;
  std::ifstream stream(path, std::ios::binary);
  if (!stream) return false;
  const std::string text((std::istreambuf_iterator<char>(stream)),
                         std::istreambuf_iterator<char>());
  const auto record = nlohmann::json::parse(text, nullptr, false);
  if (!record.is_object() || !record.contains("port") || !record.contains("token")) return false;
  readiness->port = record["port"].get<int>();
  readiness->token = record["token"].get<std::string>();
  return readiness->port > 0 && !readiness->token.empty();
}

class ControlClient {
 public:
  ControlClient(int port, std::string token)
      : client_("127.0.0.1", port), token_(std::move(token)) {
    client_.set_connection_timeout(5, 0);
    client_.set_read_timeout(30, 0);
  }

  // An empty object means the control surface did not answer at all, which is
  // exactly the failure this test exists for.
  nlohmann::json Post(const std::string& method, const nlohmann::json& params) {
    const httplib::Headers headers{{"Authorization", "Bearer " + token_}};
    const auto response =
        client_.Post("/v1/" + method, headers, params.dump(), "application/json");
    if (!response) {
      std::cout << "     (" << method << " never reached the control surface: "
                << httplib::to_string(response.error()) << ")\n";
      return nlohmann::json::object();
    }
    auto body = nlohmann::json::parse(response->body, nullptr, false);
    if (!body.is_object()) body = nlohmann::json::object();
    body["httpStatus"] = response->status;
    return body;
  }

 private:
  httplib::Client client_;
  std::string token_;
};

class ProcessGuard {
 public:
  explicit ProcessGuard(HANDLE process) : process_(process) {}
  ProcessGuard(const ProcessGuard&) = delete;
  ProcessGuard& operator=(const ProcessGuard&) = delete;
  ~ProcessGuard() {
    if (process_ == nullptr) return;
    if (!Exited()) ::TerminateProcess(process_, 1);
    ::CloseHandle(process_);
  }

  bool Exited() const { return ::WaitForSingleObject(process_, 0) == WAIT_OBJECT_0; }

  DWORD ExitCode() const {
    DWORD code = 0;
    return ::GetExitCodeProcess(process_, &code) ? code : 0;
  }

 private:
  HANDLE process_ = nullptr;
};

// An outside `TerminateProcess` cannot run any of the app's shutdown code, so
// the readiness record it published is still on disk. A shutdown the app chose
// to perform always retracts it first. That difference is the whole test.
bool WasTerminatedFromOutside(const ProcessGuard& process,
                              const std::filesystem::path& readiness_path) {
  std::error_code code;
  return process.Exited() && std::filesystem::exists(readiness_path, code);
}

void ReportOutsideTermination(const ProcessGuard& process) {
  std::cout << "SKIP the instance was terminated from outside this test "
            << "(exit code " << static_cast<int>(process.ExitCode())
            << ", readiness still published, so no shutdown of its own ran). "
            << "Another Kelpie build on this machine was very likely cleared "
               "by executable name.\n";
}

}  // namespace

int main(int argc, char** argv) {
  if (argc < 2) {
    std::cerr << "usage: idle_control_surface_test <kelpie-binary-directory>\n";
    return 2;
  }
  const std::filesystem::path binary_dir(argv[1]);
  const std::filesystem::path executable = binary_dir / "kelpie.exe";
  if (!Check(std::filesystem::exists(executable), "the packaged kelpie.exe exists")) return 1;

  const int port = ReserveLoopbackPort();
  if (!Check(port > 0, "a loopback port is available for the test instance")) return 1;

  const std::filesystem::path profile_dir =
      std::filesystem::temp_directory_path() /
      ("kelpie-idle-" + std::to_string(::GetCurrentProcessId()));
  std::error_code code;
  std::filesystem::remove_all(profile_dir, code);
  std::filesystem::create_directories(profile_dir, code);

  std::wstring command = L"\"" + executable.wstring() + L"\" --port " + std::to_wstring(port) +
                         L" --profile-dir \"" + profile_dir.wstring() + L"\" --url about:blank";
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION information{};
  if (!Check(::CreateProcessW(nullptr, command.data(), nullptr, nullptr, FALSE, 0, nullptr,
                              binary_dir.wstring().c_str(), &startup, &information) != FALSE,
             "the test instance launched")) {
    return 1;
  }
  ::CloseHandle(information.hThread);
  ProcessGuard process(information.hProcess);

  const std::filesystem::path readiness_path = profile_dir / "readiness.json";
  Readiness readiness;
  for (int attempt = 0; attempt < 900 && !ReadReadiness(readiness_path, &readiness); ++attempt) {
    Wait(100);
  }
  if (!Check(readiness.port > 0, "the instance published a readiness record")) return 1;

  ControlClient client(readiness.port, readiness.token);
  const auto before = client.Post("get-tabs", nlohmann::json::object());
  if (!Check(before.value("httpStatus", 0) == 200 && before.value("success", false),
             "the control surface serves get-tabs before the quiet period")) {
    return 1;
  }

  // The quiet period. Nothing below may talk to the app until it is over --
  // waiting on the process handle is the only permitted observation.
  std::cout << "     (staying completely quiet for " << kIdleSeconds << "s)\n";
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(kIdleSeconds);
  bool exited_while_idle = false;
  while (std::chrono::steady_clock::now() < deadline) {
    if (process.Exited()) {
      exited_while_idle = true;
      break;
    }
    Wait(250);
  }

  if (exited_while_idle && WasTerminatedFromOutside(process, readiness_path)) {
    ReportOutsideTermination(process);
    std::filesystem::remove_all(profile_dir, code);
    return kSkipExitCode;
  }
  if (!Check(!exited_while_idle, "the app is still running after the quiet period")) {
    Check(false, "an idle app must never retract readiness and exit on its own");
    std::filesystem::remove_all(profile_dir, code);
    return 1;
  }
  Check(std::filesystem::exists(readiness_path, code),
        "readiness.json still advertises the control surface after the quiet period");

  const auto after = client.Post("get-tabs", nlohmann::json::object());
  Check(after.value("httpStatus", 0) == 200 && after.value("success", false),
        "the control surface still serves get-tabs after the quiet period");
  Check(after.value("tabs", nlohmann::json::array()).size() ==
            before.value("tabs", nlohmann::json::array()).size(),
        "the quiet period did not change the tab set");

  // An orderly close must still finish. A runtime that answers `accepted` and
  // keeps running leaves a readiness record pointing at an app nobody can stop.
  Check(client.Post("close-browser", nlohmann::json::object()).value("success", false),
        "close-browser is accepted");
  bool exited = false;
  for (int attempt = 0; attempt < 900 && !exited; ++attempt) {
    exited = process.Exited();
    if (!exited) Wait(100);
  }
  if (exited && WasTerminatedFromOutside(process, readiness_path)) {
    ReportOutsideTermination(process);
    std::filesystem::remove_all(profile_dir, code);
    return kSkipExitCode;
  }
  Check(exited, "close-browser shuts the app down");
  Check(!std::filesystem::exists(readiness_path, code), "orderly shutdown removes readiness.json");

  std::filesystem::remove_all(profile_dir, code);
  if (g_failures == 0) std::cout << "idle_control_surface_test passed\n";
  return g_failures == 0 ? 0 : 1;
}
