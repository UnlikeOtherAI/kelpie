#include "mollotov/handler_context.h"

#include <stdexcept>

namespace mollotov {

HandlerContext::HandlerContext(RendererInterface* renderer)
    : renderer_(renderer) {}

void HandlerContext::SetRenderer(RendererInterface* renderer) {
  renderer_ = renderer;
}

RendererInterface* HandlerContext::Renderer() const {
  return renderer_;
}

bool HandlerContext::HasRenderer() const {
  return renderer_ != nullptr;
}

std::string HandlerContext::EvaluateJsReturningString(
    const std::string& script) const {
  return RequireRenderer().EvaluateJs(script);
}

HandlerContext::json HandlerContext::EvaluateJsReturningJson(
    const std::string& script) const {
  const std::string wrapped = "JSON.stringify((" + script + "))";
  const std::string raw = EvaluateJsReturningString(wrapped);
  if (raw.empty() || raw == "null") {
    return json::object();
  }

  try {
    const json parsed = json::parse(raw);
    return parsed.is_null() ? json::object() : parsed;
  } catch (const json::parse_error&) {
    return json::object();
  }
}

RendererInterface& HandlerContext::RequireRenderer() const {
  if (renderer_ == nullptr) {
    throw std::runtime_error("Renderer is not set");
  }
  return *renderer_;
}

}  // namespace mollotov
