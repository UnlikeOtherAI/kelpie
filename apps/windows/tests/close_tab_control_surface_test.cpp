// Closing a tab must never retire the application's control surface.
//
// Every tab browser is a child window of the one application shell window, so
// CEF's default per-browser close notification lands on the shell and reads as
// "close the application": the loopback listener drains, readiness.json is left
// advertising a dead port, and the app keeps running while uncontrollable.
// Nothing below the process boundary catches that -- close-tab answers
// `success` either way -- so this test drives the shipped executable over its
// real HTTP control surface and requires the surface to still answer after
// every tab close.

#include <httplib.h>

#include <windows.h>

#include <nlohmann/json.hpp>

#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <string>
#include <system_error>
#include <thread>
#include <vector>

namespace {

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

std::vector<nlohmann::json> TabsOf(const nlohmann::json& response) {
  std::vector<nlohmann::json> tabs;
  if (!response.contains("tabs") || !response["tabs"].is_array()) return tabs;
  for (const auto& tab : response["tabs"]) tabs.push_back(tab);
  return tabs;
}

std::string ActiveTabId(const std::vector<nlohmann::json>& tabs) {
  for (const auto& tab : tabs) {
    if (tab.value("active", false)) return tab.value("id", std::string());
  }
  return std::string();
}

// The regression assertion. `close-tab` reports success even when it has just
// torn the listener down, so every close is followed by a real request.
std::vector<nlohmann::json> RequireStillServing(ControlClient& client, const std::string& stage) {
  const auto response = client.Post("get-tabs", nlohmann::json::object());
  Check(response.value("httpStatus", 0) == 200 && response.value("success", false),
        "the control surface still serves get-tabs after " + stage);
  return TabsOf(response);
}

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

 private:
  HANDLE process_ = nullptr;
};

}  // namespace

int main(int argc, char** argv) {
  if (argc < 2) {
    std::cerr << "usage: close_tab_control_surface_test <kelpie-binary-directory>\n";
    return 2;
  }
  const std::filesystem::path binary_dir(argv[1]);
  const std::filesystem::path executable = binary_dir / "kelpie.exe";
  if (!Check(std::filesystem::exists(executable), "the packaged kelpie.exe exists")) return 1;

  const int port = ReserveLoopbackPort();
  if (!Check(port > 0, "a loopback port is available for the test instance")) return 1;

  const std::filesystem::path profile_dir =
      std::filesystem::temp_directory_path() /
      ("kelpie-close-tab-" + std::to_string(::GetCurrentProcessId()));
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
  auto tabs = RequireStillServing(client, "startup");
  if (!Check(tabs.size() == 1, "the instance starts with exactly one tab")) return 1;
  const std::string first_tab = tabs.front().value("id", std::string());

  const auto second = client.Post("new-tab", {{"url", "about:blank"}});
  const auto third = client.Post("new-tab", {{"url", "about:blank"}});
  if (!Check(second.value("success", false) && third.value("success", false),
             "two further tabs open")) {
    return 1;
  }
  const std::string second_tab = second.value("tabId", std::string());
  const std::string third_tab = third.value("tabId", std::string());

  // Closing a background tab must leave both the control surface and the
  // visible selection untouched.
  Check(client.Post("close-tab", {{"tabId", third_tab}}).value("success", false),
        "closing a background tab reports success");
  Wait(3000);
  tabs = RequireStillServing(client, "closing a background tab");
  Check(tabs.size() == 2, "closing a background tab leaves the other two tabs");
  Check(ActiveTabId(tabs) == first_tab, "closing a background tab keeps the selection");
  Check(!process.Exited(), "the app is still running after a background tab close");

  // Closing the active tab must move focus to a survivor, not close the app.
  Check(client.Post("switch-tab", {{"tabId", second_tab}}).value("success", false),
        "the second tab can be activated");
  Check(ActiveTabId(TabsOf(client.Post("get-tabs", nlohmann::json::object()))) == second_tab,
        "the second tab is the active tab");
  Check(client.Post("close-tab", {{"tabId", second_tab}}).value("success", false),
        "closing the active tab reports success");
  Wait(3000);
  tabs = RequireStillServing(client, "closing the active tab");
  Check(tabs.size() == 1, "closing the active tab leaves the surviving tab");
  Check(ActiveTabId(tabs) == first_tab, "closing the active tab moves focus to a survivor");

  // Closing the last tab must leave one blank usable tab -- never zero tabs and
  // never an exit.
  Check(client.Post("close-tab", {{"tabId", first_tab}}).value("success", false),
        "closing the last tab reports success");
  Wait(3000);
  tabs = RequireStillServing(client, "closing the last tab");
  Check(tabs.size() == 1, "closing the last tab leaves exactly one replacement tab");
  if (!tabs.empty()) {
    Check(tabs.front().value("id", std::string()) != first_tab,
          "the replacement tab is a new tab");
    Check(tabs.front().value("active", false), "the replacement tab is active");
  }
  Check(!process.Exited(), "the app is still running after the last tab closed");
  Check(std::filesystem::exists(readiness_path),
        "readiness.json still advertises the live control surface");

  // Orderly shutdown must still exit and must still retract readiness.
  client.Post("close-browser", nlohmann::json::object());
  bool exited = false;
  for (int attempt = 0; attempt < 600 && !exited; ++attempt) {
    exited = process.Exited();
    if (!exited) Wait(100);
  }
  Check(exited, "close-browser shuts the app down");
  Check(!std::filesystem::exists(readiness_path), "orderly shutdown removes readiness.json");

  std::filesystem::remove_all(profile_dir, code);
  if (g_failures == 0) std::cout << "close_tab_control_surface_test passed\n";
  return g_failures == 0 ? 0 : 1;
}
