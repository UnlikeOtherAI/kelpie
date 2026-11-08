#include "kelpie/desktop_mcp_server.h"

#include <cassert>
#include <cstdlib>
#undef assert
#define assert(expression) do { if (!(expression)) std::abort(); } while (false)

#include <optional>
#include <string>
#include <vector>

#include "kelpie/desktop_router.h"
#include "kelpie/screenshot_fit.h"

namespace {
using json = nlohmann::json;
constexpr std::size_t kLimit = 100;

// Base64 length the fake renderer produces per encoding; nullopt fails the capture.
struct Sizes {
  std::size_t png = 10;
  std::optional<std::size_t> q80 = 10, q60 = 10, q40 = 10;
};
}  // namespace

int main() {
  // The shared ladder: first capture, then JPEG 80/60/40 until one fits.
  std::vector<std::optional<int>> asked;
  const auto ladder = [&](std::vector<std::optional<std::size_t>> sizes) {
    asked.clear();
    return kelpie::FitScreenshot(kLimit, [&](std::optional<int> quality) {
      asked.push_back(quality);
      return sizes[asked.size() - 1];
    });
  };
  assert(ladder({kLimit}) == kelpie::ScreenshotFit::kFits && asked.size() == 1 && !asked[0]);
  assert(ladder({kLimit + 1, kLimit + 1, kLimit}) == kelpie::ScreenshotFit::kFits &&
         asked == std::vector<std::optional<int>>({std::nullopt, 80, 60}));
  assert(ladder({kLimit + 1, kLimit + 1, kLimit + 1, kLimit + 1}) == kelpie::ScreenshotFit::kTooLarge && asked.size() == 4 && asked[3] == 40);
  assert(ladder({kLimit + 1, std::nullopt}) == kelpie::ScreenshotFit::kFailed && asked.size() == 2);
  assert(kelpie::kAccountScreenshotBase64Limit == 640 * 1024);

  Sizes sizes;
  std::vector<json> captures;
  kelpie::DesktopRouter router;
  router.Register("screenshot", [&](const json& params) {
    captures.push_back(params);
    const std::string format = params.value("format", std::string("png"));
    std::optional<std::size_t> size = sizes.png;
    if (format == "jpeg") {
      const int quality = params.at("quality");
      size = quality == 80 ? sizes.q80 : quality == 60 ? sizes.q60 : sizes.q40;
    }
    if (!size) return json{{"success", false}, {"error", {{"code", "TAB_STALE"}}}};
    return json{{"success", true}, {"image", std::string(*size, format == "jpeg" ? 'J' : 'P')}, {"format", format}};
  });
  kelpie::DesktopMcpServer server;
  server.SetRouter(&router);
  kelpie::DesktopMcpServer::Config account;
  account.platform = kelpie::Platform::kWindows;
  account.screenshot_base64_limit = kLimit;
  int authorizations = 0;
  int refuse_after = 1000;
  const auto authorize = [&] { return ++authorizations <= refuse_after; };
  const json request = {{"version", 1}, {"method", "tab.screenshot"}, {"tabId", "owned"}, {"params", json::object()}};
  const auto run = [&](const kelpie::DesktopMcpServer::Config& config) {
    captures.clear(); authorizations = 0;
    return server.HandleBrowserRequestAuthorized(request, config, authorize, kelpie::TabLease{"owned", 1, "doc-1"});
  };

  // A PNG within the budget passes through unchanged after one capture.
  auto response = run(account);
  assert(response["ok"] == true && response["value"]["mimeType"] == "image/png");
  assert(response["value"]["data"] == std::string(10, 'P') && captures.size() == 1);
  assert(!captures[0].contains("format") && !captures[0].contains("quality"));

  // An oversized PNG is retaken as JPEG and reported as image/jpeg.
  sizes = {kLimit + 1, kLimit + 1, kLimit, kLimit};
  response = run(account);
  assert(response["ok"] == true && response["value"]["mimeType"] == "image/jpeg");
  assert(response["value"]["data"] == std::string(kLimit, 'J') && captures.size() == 3);
  assert(captures[1]["quality"] == 80 && captures[2]["format"] == "jpeg" && captures[2]["quality"] == 60);
  // Every retake re-ran the job authorization fence.
  const int fenced = authorizations;
  assert(fenced >= 3);

  // Nothing fits: a read-only refusal, and the gateway accepts the next request.
  sizes = {kLimit + 1, kLimit + 1, kLimit + 1, kLimit + 1};
  response = run(account);
  assert(response["ok"] == false && response["error"]["code"] == "SCREENSHOT_TOO_LARGE");
  assert(response["error"]["mayHaveCompleted"] == false && captures.size() == 4 && captures[3]["quality"] == 40);

  // A fence that fails before a retake stops capturing; no JPEG is taken.
  refuse_after = fenced - 2;
  response = run(account);
  assert(response["ok"] == false && response["error"]["code"] == "CANCELLED" && captures.size() == 1);
  refuse_after = 1000;

  // A failed retake (e.g. stale lease) is a failure, never an oversized image.
  sizes = {kLimit + 1, std::nullopt, kLimit, kLimit};
  response = run(account);
  assert(response["ok"] == false && response["error"]["code"] == "COMMAND_FAILED" && captures.size() == 2);

  // Local callers configure no budget and keep the original capture.
  sizes = {kLimit + 1, kLimit, kLimit, kLimit};
  response = run(kelpie::DesktopMcpServer::Config{});
  assert(response["ok"] == true && response["value"]["mimeType"] == "image/png" && captures.size() == 1);
  return 0;
}
