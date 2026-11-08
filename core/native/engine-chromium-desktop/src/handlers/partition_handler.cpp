#include "partition_handler.h"

namespace kelpie {

PartitionHandler::PartitionHandler(DesktopHandlerRuntime runtime) : runtime_(std::move(runtime)) {}

void PartitionHandler::Register(DesktopRouter& router) const {
  router.Register("get-partitions", [this](const nlohmann::json& params) { return GetPartitions(params); });
  router.Register("delete-partition", [this](const nlohmann::json& params) { return DeletePartition(params); });
}

nlohmann::json PartitionHandler::GetPartitions(const nlohmann::json& params) const {
  if (const auto rejected = RejectBrowserWideTab(params)) return *rejected;
  std::vector<PartitionInfo> partitions;
  const auto result = RequireBrowserControl(runtime_).GetPartitions(&partitions, ControlTimeout(params));
  if (!result.ok) return ControlError(result);
  nlohmann::json entries = nlohmann::json::array();
  for (const PartitionInfo& partition : partitions) {
    // sizeBytes is omitted: Chromium has no cheap on-disk size query, and a
    // number produced by walking the directory would be stale by the time the
    // caller read it.
    entries.push_back({{"id", partition.id}, {"tabCount", partition.tab_count},
                       {"persistent", partition.persistent}});
  }
  return SuccessResponse({{"partitions", std::move(entries)}});
}

nlohmann::json PartitionHandler::DeletePartition(const nlohmann::json& params) const {
  try {
    const std::string id = RequireString(params, "id");
    PartitionDeletion deletion;
    const auto result =
        RequireBrowserControl(runtime_).DeletePartition(id, &deletion, ControlTimeout(params));
    if (!result.ok) {
      // PARTITION_IN_USE still closed the tabs and freed the id, so the counts
      // the caller needs travel with the error rather than being lost.
      nlohmann::json details = result.details.is_object() ? result.details : nlohmann::json::object();
      details["deleted"] = id;
      details["tabsClosed"] = deletion.tabs_closed;
      details["existed"] = deletion.existed;
      return ErrorResponse(result.error_code, result.message, details);
    }
    return SuccessResponse({{"deleted", id}, {"tabsClosed", deletion.tabs_closed},
                            {"existed", deletion.existed}});
  } catch (const std::invalid_argument& exception) { return InvalidParams(exception.what()); }
}

}  // namespace kelpie
