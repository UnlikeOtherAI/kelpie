#pragma once

#include <cstdint>
#include <mutex>
#include <string>
#include <vector>

namespace mollotov {

struct Bookmark {
  std::string id;
  std::string title;
  std::string url;
  std::string created_at;
};

class BookmarkStore {
 public:
  void Add(const std::string& title, const std::string& url);
  void Remove(const std::string& id);
  void RemoveAll();
  void LoadJson(const std::string& json);
  std::string ToJson() const;
  std::int32_t Count() const;

 private:
  std::vector<Bookmark> bookmarks_;
  mutable std::mutex mutex_;
};

}  // namespace mollotov
