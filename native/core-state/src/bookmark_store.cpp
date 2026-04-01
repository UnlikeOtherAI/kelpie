#include "mollotov/bookmark_store.h"

#include <algorithm>

#include <nlohmann/json.hpp>

#include "store_support.h"

namespace mollotov {
namespace {

using json = nlohmann::json;

json BookmarkToJson(const Bookmark& bookmark) {
  return json{
      {"id", bookmark.id},
      {"title", bookmark.title},
      {"url", bookmark.url},
      {"created_at", bookmark.created_at},
  };
}

}  // namespace

void BookmarkStore::Add(const std::string& title, const std::string& url) {
  std::lock_guard<std::mutex> lock(mutex_);
  bookmarks_.push_back(Bookmark{
      store_support::GenerateUuidV4(),
      title,
      url,
      store_support::CurrentIso8601Utc(),
  });
}

void BookmarkStore::Remove(const std::string& id) {
  std::lock_guard<std::mutex> lock(mutex_);
  bookmarks_.erase(
      std::remove_if(bookmarks_.begin(), bookmarks_.end(), [&](const Bookmark& bookmark) {
        return bookmark.id == id;
      }),
      bookmarks_.end());
}

void BookmarkStore::RemoveAll() {
  std::lock_guard<std::mutex> lock(mutex_);
  bookmarks_.clear();
}

void BookmarkStore::LoadJson(const std::string& json_text) {
  const json parsed = store_support::ParseJson(json_text);

  std::vector<Bookmark> loaded;
  if (parsed.is_array()) {
    for (const auto& item : parsed) {
      if (!item.is_object()) {
        continue;
      }
      const std::string title = store_support::StringOrDefault(item, {"title"});
      const std::string url = store_support::StringOrDefault(item, {"url"});
      if (title.empty() || url.empty()) {
        continue;
      }
      loaded.push_back(Bookmark{
          store_support::StringOrDefault(item, {"id"}, store_support::GenerateUuidV4()),
          title,
          url,
          store_support::StringOrDefault(item, {"created_at", "createdAt"},
                                         store_support::CurrentIso8601Utc()),
      });
    }
  }

  std::lock_guard<std::mutex> lock(mutex_);
  bookmarks_ = std::move(loaded);
}

std::string BookmarkStore::ToJson() const {
  json output = json::array();

  std::lock_guard<std::mutex> lock(mutex_);
  for (const Bookmark& bookmark : bookmarks_) {
    output.push_back(BookmarkToJson(bookmark));
  }
  return output.dump();
}

std::int32_t BookmarkStore::Count() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return static_cast<std::int32_t>(bookmarks_.size());
}

}  // namespace mollotov
