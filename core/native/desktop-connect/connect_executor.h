#pragma once
#include "kelpie/desktop_browser_control.h"
#include "kelpie/desktop_router.h"
#include <atomic>
namespace kelpie::connect {
using Json=nlohmann::json;
class Executor {
 public:
  using Infer=std::function<Json(const Json&)>;
  using Admission=std::function<std::shared_ptr<void>(const std::string&,const Json&)>;
  using Authorization=std::function<bool()>;
  using Control=std::function<Json(const Json&,const TabLease&,const Authorization&)>;
  Executor(DesktopBrowserControl& browser,Infer infer={},Admission admission={},Control control={})
      :browser_(browser),infer_(std::move(infer)),admission_(std::move(admission)),control_(std::move(control)) {}
  Json Execute(const Json& command,std::shared_ptr<const std::atomic<bool>> cancelled);
 private:
  DesktopBrowserControl& browser_; Infer infer_; Admission admission_; Control control_;
};
}
