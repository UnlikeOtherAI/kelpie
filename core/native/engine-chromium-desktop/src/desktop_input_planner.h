#pragma once

#include <optional>
#include <string>
#include <vector>

#include <nlohmann/json.hpp>

namespace kelpie::desktop_input {

using Json = nlohmann::json;

struct Target {
  bool found = false;
  bool visible = false;
  bool enabled = false;
  bool occluded = true;
  bool editable = false;
  std::string kind;
  std::string value;
  bool checked = false;
  std::optional<std::size_t> selection_start;
  std::optional<std::size_t> selection_end;
  double x = 0;
  double y = 0;
  struct Option { std::string value; bool disabled = false; bool selected = false; };
  std::vector<Option> options;
};

struct Plan {
  bool ok = false;
  std::string error_code;
  std::string message;
  std::vector<Json> commands;
  // The caller evaluates the same target after native input and uses this
  // object for an exact state check. kind is value or checked.
  Json expected = Json::object();
};

std::string TargetInspectionScript(const std::optional<std::string>& selector, bool scroll_into_view);
std::optional<Target> ParseTarget(const Json& value, std::string* error);

// Produces only DevTools Input.* commands. It never changes page state through
// JavaScript. All form-state changes are caused by trusted native input.
Plan PlanTrustedInput(const Json& request, const std::optional<Target>& target);

bool MatchesExpectedState(const Target& target, const Json& expected);

}  // namespace kelpie::desktop_input
