#pragma once

#include <string>

#include <nlohmann/json.hpp>

#include "kelpie/renderer_interface.h"

namespace kelpie {

class HandlerContext {
 public:
  using json = nlohmann::json;

  HandlerContext() = default;
  explicit HandlerContext(RendererInterface* renderer);

  void SetRenderer(RendererInterface* renderer);
  RendererInterface* Renderer() const;
  bool HasRenderer() const;

  std::string EvaluateJsReturningString(const std::string& script) const;
 json EvaluateJsReturningJson(const std::string& script) const;

 private:
  RendererInterface& RequireRenderer() const;

  // Non-owning. Platform adapters manage renderer lifetime.
  RendererInterface* renderer_ = nullptr;
};

}  // namespace kelpie
