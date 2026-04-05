#include "bookmark_handler.h"

namespace kelpie {

BookmarkHandler::BookmarkHandler(DesktopHandlerRuntime runtime) : runtime_(std::move(runtime)) {}

void BookmarkHandler::Register(DesktopRouter& router) const {
  router.Register("bookmarks-list", [this](const nlohmann::json&) { return List(); });
  router.Register("bookmarks-add", [this](const nlohmann::json& params) { return Add(params); });
  router.Register("bookmarks-remove",
                  [this](const nlohmann::json& params) { return Remove(params); });
  router.Register("bookmarks-clear", [this](const nlohmann::json&) { return Clear(); });

  router.Register("get-bookmarks", [this](const nlohmann::json&) { return List(); });
  router.Register("add-bookmark", [this](const nlohmann::json& params) { return Add(params); });
  router.Register("remove-bookmark",
                  [this](const nlohmann::json& params) { return Remove(params); });
  router.Register("clear-bookmarks", [this](const nlohmann::json&) { return Clear(); });
}

nlohmann::json BookmarkHandler::List() const {
  if (runtime_.bookmark_store == nullptr) {
    return SuccessResponse({{"bookmarks", nlohmann::json::array()}});
  }
  return SuccessResponse({{"bookmarks", ParseJsonText(runtime_.bookmark_store->ToJson())}});
}

nlohmann::json BookmarkHandler::Add(const nlohmann::json& params) const {
  if (runtime_.bookmark_store == nullptr) {
    return Unsupported("bookmarks-add");
  }
  try {
    const std::string url = RequireString(params, "url");
    const auto title_it = params.find("title");
    const std::string title =
        title_it != params.end() && title_it->is_string() ? title_it->get<std::string>() : url;
    runtime_.bookmark_store->Add(title, url);
    return List();
  } catch (const std::invalid_argument& exception) {
    return InvalidParams(exception.what());
  }
}

nlohmann::json BookmarkHandler::Remove(const nlohmann::json& params) const {
  if (runtime_.bookmark_store == nullptr) {
    return Unsupported("bookmarks-remove");
  }
  try {
    runtime_.bookmark_store->Remove(RequireString(params, "id"));
    return List();
  } catch (const std::invalid_argument& exception) {
    return InvalidParams(exception.what());
  }
}

nlohmann::json BookmarkHandler::Clear() const {
  if (runtime_.bookmark_store == nullptr) {
    return SuccessResponse({{"cleared", true}});
  }
  runtime_.bookmark_store->RemoveAll();
  return SuccessResponse({{"cleared", true}});
}

}  // namespace kelpie
