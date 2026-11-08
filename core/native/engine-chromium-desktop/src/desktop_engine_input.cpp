// DesktopEngine trusted native input and JavaScript dialogs. They live
// together because a dialog opened by input is what ends that input's wait.
#include "desktop_engine_control_support.h"

#include <chrono>
#include <memory>
#include <optional>

#include "desktop_input_planner.h"

namespace kelpie {

using namespace engine_control;

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
  // A page handler that calls alert()/confirm()/prompt() suspends the renderer,
  // so Chromium withholds the input reply until the dialog is handled -- which
  // the caller can only do once this request returns. The open dialog is the
  // proof the input landed.
  const auto impl = impl_;
  const auto dialog_opened = [impl, lease] {
    auto showing = std::make_shared<bool>(false);
    impl->RunOnUi([impl, lease, showing] {
      if (auto* tab = impl->FindTab(lease)) *showing = tab->dialogs.Current(tab->browser).value("showing", false);
      return BrowserControlResult::Success();
    }, std::chrono::seconds(1));
    return *showing;
  };
  bool opened_dialog = false;
  for (const auto& command : plan.commands) {
    const auto method = command.find("method");
    const auto params = command.find("params");
    if (method == command.end() || !method->is_string() || params == command.end() || !params->is_object()) {
      return BrowserControlResult::Failure("INTERNAL", "Input planner emitted an invalid DevTools command");
    }
    const auto remaining = RemainingTimeout(started_at, timeout);
    if (remaining <= Timeout::zero()) return DeadlineExceeded();
    Json ignored;
    const auto result =
        RunDevTools(impl, lease, method->get<std::string>(), *params, &ignored, remaining, dialog_opened);
    if (result.error_code == "INTERRUPTED") {
      opened_dialog = true;
      break;
    }
    if (!result.ok) return result;
  }
  if (opened_dialog) {
    if (output) *output = {{"trusted", true}, {"dialogOpened", true}};
    return BrowserControlResult::Success();
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
