#pragma once

#include "handler_support.h"
#include "kelpie/desktop_router.h"

namespace kelpie {

class BookmarkHandler {
 public:
  explicit BookmarkHandler(DesktopHandlerRuntime runtime);

  void Register(DesktopRouter& router) const;

 private:
  nlohmann::json List() const;
  nlohmann::json Add(const nlohmann::json& params) const;
  nlohmann::json Remove(const nlohmann::json& params) const;
  nlohmann::json Clear() const;

  DesktopHandlerRuntime runtime_;
};

}  // namespace kelpie
