#include <cassert>
#include <cmath>
#include <iostream>
#include <string>
#include <vector>

#include "desktop_cookie_planner.h"
#include "desktop_input_planner.h"

using kelpie::desktop_cookie::Json;

namespace {

nlohmann::json Target(std::string kind = "text", std::string value = "old") {
  return {{"found", true}, {"visible", true}, {"enabled", true}, {"occluded", false}, {"editable", kind == "text"},
          {"kind", std::move(kind)}, {"value", std::move(value)}, {"checked", false}, {"x", 10.0}, {"y", 20.0},
          {"options", nlohmann::json::array()}};
}

void TestCookiePlanner() {
  struct ExpiryCase { nlohmann::json input; bool valid; double expected = 0; };
  const std::vector<ExpiryCase> cases = {
      {"2024-02-29T23:59:59.125Z", true, 1709251199.125}, {"2023-02-29T00:00:00Z", false},
      {"2024-13-01T00:00:00Z", false}, {"2024-01-01T00:00:60Z", false}, {"2024-01-01T00:00:00+00:00", false},
      {42.5, true, 42.5}, {std::numeric_limits<double>::infinity(), false}};
  for (const auto& test : cases) {
    const auto parsed = kelpie::desktop_cookie::ParseExpirySeconds(test.input);
    assert(parsed.has_value() == test.valid);
    if (parsed) assert(std::abs(*parsed - test.expected) < 0.0001);
  }
  auto set = kelpie::desktop_cookie::PlanSetCookie({{"name", "a"}, {"value", ""}, {"domain", ".example.test"},
      {"expires", "2024-02-29T23:59:59.125Z"}, {"tabId", "tab-1"}, {"generation", 2}, {"timeout", 1000}});
  assert(set.ok && !set.params.contains("tabId") && !set.params.contains("generation") && !set.params.contains("timeout"));
  assert(set.params["expires"].is_number_float());
  assert(!kelpie::desktop_cookie::PlanSetCookie({{"name", "a"}, {"domain", "example.test"}, {"expires", "2023-02-29T00:00:00Z"}}).ok);
  assert(!kelpie::desktop_cookie::PlanSetCookie({{"name", "a"}, {"domain", "example.test"}, {"sameSite", "lax"}}).ok);

  const auto domain_delete = kelpie::desktop_cookie::PlanDeleteCookies({{"domain", ".example.test"}});
  assert(domain_delete.ok && domain_delete.action == kelpie::desktop_cookie::DeletePlan::Action::kDelete && !domain_delete.params.contains("url"));
  assert(kelpie::desktop_cookie::PlanDeleteCookies({{"deleteAll", true}, {"name", "ignored"}}).ok);
  assert(!kelpie::desktop_cookie::PlanDeleteCookies({{"url", "https://example.test"}}).ok);
  assert(!kelpie::desktop_cookie::PlanDeleteCookies({{"name", ""}}).ok);

  const auto url_query = kelpie::desktop_cookie::PlanGetCookies({{"url", "https://bücher.example/app"}, {"name", "session"}});
  assert(url_query.ok && url_query.params == nlohmann::json({{"urls", nlohmann::json::array({"https://bücher.example/app"})}}));
  assert(kelpie::desktop_cookie::MatchesFilter({{"name", "session"}, {"domain", ".example.test"}}, {{"name", "session"}}));
  assert(!kelpie::desktop_cookie::MatchesFilter({{"name", "other"}}, {{"name", "session"}}));
  assert(!kelpie::desktop_cookie::PlanGetCookies({{"url", 3}}).ok);
}

void TestInputPlanner() {
  std::string error;
  auto parsed = kelpie::desktop_input::ParseTarget(Target(), &error);
  assert(parsed && error.empty());
  const auto fill = kelpie::desktop_input::PlanTrustedInput({{"type", "fill"}, {"value", "new"}}, parsed);
  assert(fill.ok && fill.commands.size() == 7 && fill.expected == nlohmann::json({{"kind", "value"}, {"value", "new"}}));
  const auto& control_up = fill.commands[3]["params"];
  assert(control_up["type"] == "keyUp" && control_up["windowsVirtualKeyCode"] == 17);
  assert(kelpie::desktop_input::MatchesExpectedState(*kelpie::desktop_input::ParseTarget(Target("text", "new"), &error), fill.expected));
  assert(!kelpie::desktop_input::MatchesExpectedState(*parsed, fill.expected));

  auto checkbox = Target("checkbox"); checkbox["editable"] = false; checkbox["checked"] = false;
  auto checked = kelpie::desktop_input::ParseTarget(checkbox, &error);
  const auto check = kelpie::desktop_input::PlanTrustedInput({{"type", "setChecked"}, {"checked", true}}, checked);
  assert(check.ok && check.commands.size() == 2 && check.expected["kind"] == "checked");
  checkbox["checked"] = true;
  assert(kelpie::desktop_input::MatchesExpectedState(*kelpie::desktop_input::ParseTarget(checkbox, &error), check.expected));

  auto select = Target("select-one", "first"); select["editable"] = false;
  select["options"] = nlohmann::json::array({{{"value", "first"}, {"disabled", false}, {"selected", true}},
                                                {{"value", "disabled"}, {"disabled", true}, {"selected", false}},
                                                {{"value", "last"}, {"disabled", false}, {"selected", false}}});
  auto selected = kelpie::desktop_input::ParseTarget(select, &error);
  const auto choose = kelpie::desktop_input::PlanTrustedInput({{"type", "selectOption"}, {"value", "last"}}, selected);
  assert(choose.ok && choose.commands.size() == 8);
  for (const auto& command : choose.commands) if (command["method"] == "Input.dispatchKeyEvent") assert(command["params"].contains("windowsVirtualKeyCode"));
  assert(!kelpie::desktop_input::PlanTrustedInput({{"type", "selectOption"}, {"value", "disabled"}}, selected).ok);

  auto hidden = Target(); hidden["visible"] = false;
  assert(kelpie::desktop_input::PlanTrustedInput({{"type", "click"}}, kelpie::desktop_input::ParseTarget(hidden, &error)).error_code == "ELEMENT_NOT_INTERACTABLE");
  assert(kelpie::desktop_input::PlanTrustedInput({{"type", "fill"}, {"value", "x"}}, std::nullopt).error_code == "ELEMENT_NOT_FOUND");
  auto focused = Target("text", "beforeafter"); focused["selectionStart"] = 6; focused["selectionEnd"] = 6;
  const auto typed = kelpie::desktop_input::PlanTrustedInput({{"type", "type"}, {"text", "-"}}, kelpie::desktop_input::ParseTarget(focused, &error));
  assert(typed.ok && typed.commands.size() == 1 && typed.expected["value"] == "before-after");
  auto readonly_textarea = Target("textarea"); readonly_textarea["editable"] = false;
  assert(kelpie::desktop_input::PlanTrustedInput({{"type", "fill"}, {"value", "x"}}, kelpie::desktop_input::ParseTarget(readonly_textarea, &error)).error_code == "UNSUPPORTED");
  assert(kelpie::desktop_input::PlanTrustedInput({{"type", "key"}, {"key", "Enter"}}, std::nullopt).ok);
  assert(!kelpie::desktop_input::PlanTrustedInput({{"type", "key"}, {"key", "UnmappedKey"}}, std::nullopt).ok);
}

}  // namespace

int main() {
  TestCookiePlanner();
  TestInputPlanner();
  std::cout << "desktop input/cookie planners passed\n";
}
