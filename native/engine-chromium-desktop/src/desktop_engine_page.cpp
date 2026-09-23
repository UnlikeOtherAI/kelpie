#include "desktop_engine_impl.h"

#include <memory>
#include <optional>
#include <string>

#include "desktop_cookie_planner.h"
#include "desktop_input_planner.h"

// Page state and input for the desktop engine: cookies, trusted native input
// and JavaScript dialogs. Each is planned by a pure planner and carried out
// through the engine's DevTools and Evaluate calls.
namespace kelpie {
namespace {

BrowserControlResult DeadlineExceeded() {
  return BrowserControlResult::Failure("TIMEOUT", "Browser operation timed out before the next native operation");
}

BrowserControlResult PlannerError(const std::string& code, const std::string& message) {
  return BrowserControlResult::Failure(code.empty() ? "INVALID_PARAMS" : code, message);
}

}  // namespace

BrowserControlResult DesktopEngine::GetCookies(TabLease lease, const Json& query, Json* cookies, Timeout timeout) {
  if (!cookies) return BrowserControlResult::Failure("INTERNAL", "cookies is required");
  const auto planned = desktop_cookie::PlanGetCookies(query);
  if (!planned.ok) return PlannerError("INVALID_PARAMS", planned.error);
  Json response;
  const std::string method = query.contains("url") ? "Network.getCookies" : "Network.getAllCookies";
  const auto result = DevTools(lease, method, planned.params, &response, timeout);
  if (!result.ok) return result;
  const auto listed = response.find("cookies");
  if (listed == response.end() || !listed->is_array()) {
    return BrowserControlResult::Failure("CDP_MALFORMED_RESULT", method + " did not return cookies");
  }
  Json filtered = Json::array();
  for (const auto& cookie : *listed) if (desktop_cookie::MatchesFilter(cookie, query)) filtered.push_back(cookie);
  *cookies = std::move(filtered);
  return result;
}

BrowserControlResult DesktopEngine::SetCookies(TabLease lease, const Json& cookies, Json* output, Timeout timeout) {
  const Json values = cookies.is_array() ? cookies : Json::array({cookies});
  if (values.empty()) return BrowserControlResult::Failure("INVALID_PARAMS", "At least one cookie is required");
  const auto started_at = std::chrono::steady_clock::now();
  std::size_t set = 0;
  for (const auto& value : values) {
    const auto planned = desktop_cookie::PlanSetCookie(value);
    if (!planned.ok) return PlannerError("INVALID_PARAMS", planned.error);
    const auto remaining = RemainingTimeout(started_at, timeout);
    if (remaining <= Timeout::zero()) return DeadlineExceeded();
    Json response;
    const auto result = DevTools(lease, "Network.setCookie", planned.params, &response, remaining);
    if (!result.ok) return result;
    const auto success = response.find("success");
    if (success == response.end() || !success->is_boolean() || !success->get<bool>()) {
      return BrowserControlResult::Failure("DEVTOOLS_ERROR", "Chromium rejected the cookie");
    }
    ++set;
  }
  if (output) *output = {{"set", set}};
  return BrowserControlResult::Success();
}

BrowserControlResult DesktopEngine::DeleteCookies(TabLease lease, const Json& query, Json* output, Timeout timeout) {
  const auto planned = desktop_cookie::PlanDeleteCookies(query);
  if (!planned.ok) return PlannerError("INVALID_PARAMS", planned.error);
  const auto started_at = std::chrono::steady_clock::now();
  const auto remaining = RemainingTimeout(started_at, timeout);
  if (remaining <= Timeout::zero()) return DeadlineExceeded();
  Json response;
  const std::string method = planned.action == desktop_cookie::DeletePlan::Action::kClearAll
      ? "Network.clearBrowserCookies" : "Network.deleteCookies";
  const auto result = DevTools(lease, method, planned.params, &response, remaining);
  if (result.ok && output) *output = std::move(response);
  return result;
}

BrowserControlResult DesktopEngine::DispatchTrustedInput(TabLease lease, const Json& input, Json* output, Timeout timeout) {
  if (!input.is_object()) return BrowserControlResult::Failure("INVALID_PARAMS", "Input must be an object");
  const auto type = input.find("type");
  if (type == input.end() || !type->is_string()) return BrowserControlResult::Failure("INVALID_PARAMS", "Input type is required");
  const auto started_at = std::chrono::steady_clock::now();
  const auto has_selector = input.contains("selector");
  std::optional<std::string> selector;
  if (has_selector) {
    if (!input["selector"].is_string() || input["selector"].get<std::string>().empty()) {
      return BrowserControlResult::Failure("INVALID_PARAMS", "selector must be a non-empty string");
    }
    selector = input["selector"].get<std::string>();
  }
  if (type->get<std::string>() != "key" && type->get<std::string>() != "type" && !selector) {
    return BrowserControlResult::Failure("INVALID_PARAMS", "selector is required for this input type");
  }

  std::optional<desktop_input::Target> target;
  const auto inspect = [&](bool scroll) -> BrowserControlResult {
    const auto remaining = RemainingTimeout(started_at, timeout);
    if (remaining <= Timeout::zero()) return DeadlineExceeded();
    Json inspected;
    const auto result = Evaluate(lease, desktop_input::TargetInspectionScript(selector, scroll), &inspected, remaining);
    if (!result.ok) return result;
    std::string error;
    target = desktop_input::ParseTarget(inspected, &error);
    return target ? BrowserControlResult::Success() : BrowserControlResult::Failure("CDP_MALFORMED_RESULT", error);
  };

  if (type->get<std::string>() != "key") {
    const auto result = inspect(selector.has_value());
    if (!result.ok) return result;
  }
  const auto plan = desktop_input::PlanTrustedInput(input, target);
  if (!plan.ok) return PlannerError(plan.error_code, plan.message);
  for (const auto& command : plan.commands) {
    const auto method = command.find("method");
    const auto params = command.find("params");
    if (method == command.end() || !method->is_string() || params == command.end() || !params->is_object()) {
      return BrowserControlResult::Failure("INTERNAL", "Input planner emitted an invalid DevTools command");
    }
    const auto remaining = RemainingTimeout(started_at, timeout);
    if (remaining <= Timeout::zero()) return DeadlineExceeded();
    Json ignored;
    const auto result = DevTools(lease, method->get<std::string>(), *params, &ignored, remaining);
    if (!result.ok) return result;
  }
  if (!plan.expected.empty()) {
    const auto result = inspect(false);
    if (!result.ok) return result;
    if (!desktop_input::MatchesExpectedState(*target, plan.expected)) {
      return BrowserControlResult::Failure("INPUT_STATE_MISMATCH", "Native input did not produce the requested state");
    }
  }
  if (output) {
    *output = {{"trusted", true}};
    if (plan.expected.contains("kind") && plan.expected.contains("value")) {
      (*output)[plan.expected["kind"].get<std::string>()] = plan.expected["value"];
    }
  }
  return BrowserControlResult::Success();
}
BrowserControlResult DesktopEngine::GetDialog(TabLease lease, Json* dialog, Timeout timeout) {
  const auto impl = impl_;
  if (!dialog) return BrowserControlResult::Failure("INTERNAL", "dialog is required");
  auto state = std::make_shared<Json>();
  const auto result = impl->RunOnUi([impl, lease, state] {
    auto* tab = impl->FindTab(lease);
    if (!tab) return BrowserControlResult::Failure("TAB_NOT_FOUND", "The tab does not exist or is stale");
    *state = tab->dialogs.Current(tab->browser);
    return BrowserControlResult::Success(impl->Snapshot(*tab));
  }, timeout);
  if (result.ok) *dialog = *state;
  return result;
}

BrowserControlResult DesktopEngine::HandleDialog(TabLease lease, const Json& action, Json* output, Timeout timeout) {
  const auto impl = impl_;
  auto state = std::make_shared<Json>();
  const auto result = impl->RunOnUi([impl, lease, action, state] {
    auto* tab = impl->FindTab(lease);
    if (!tab) return BrowserControlResult::Failure("TAB_NOT_FOUND", "The tab does not exist or is stale");
    if (!tab->dialogs.Handle(tab->browser, action, state.get())) {
      return BrowserControlResult::Failure("UNSUPPORTED", "No matching JavaScript dialog is open");
    }
    return BrowserControlResult::Success(impl->Snapshot(*tab));
  }, timeout);
  if (result.ok && output) *output = *state;
  return result;
}

}  // namespace kelpie
