#pragma once

#include "handler_support.h"
#include "kelpie/desktop_router.h"

namespace kelpie {

// Storage-partition lifecycle: listing what exists and tearing one down.
// Creation is implicit — a partition comes into being when the first
// `new-tab` names it, which BrowserManagementHandler owns.
class PartitionHandler {
 public:
  explicit PartitionHandler(DesktopHandlerRuntime runtime);

  void Register(DesktopRouter& router) const;

 private:
  nlohmann::json GetPartitions(const nlohmann::json& params) const;
  nlohmann::json DeletePartition(const nlohmann::json& params) const;

  DesktopHandlerRuntime runtime_;
};

}  // namespace kelpie
