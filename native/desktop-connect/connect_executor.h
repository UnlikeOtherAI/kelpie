#pragma once
#include "kelpie/desktop_browser_control.h"
#include "kelpie/desktop_router.h"
#include <atomic>
namespace kelpie::connect {
using Json=nlohmann::json;
class Executor {
 public:
  using Infer=std::function<Json(const Json&)>;
  Executor(DesktopBrowserControl& browser,Infer infer={})
      :browser_(browser),infer_(std::move(infer)) {}
  Json Execute(const Json& command,std::shared_ptr<const std::atomic<bool>> cancelled);
 private:
  DesktopBrowserControl& browser_; Infer infer_;
};
}
